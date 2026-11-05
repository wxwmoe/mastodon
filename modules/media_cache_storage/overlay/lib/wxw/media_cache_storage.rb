# frozen_string_literal: true

module Wxw
  module MediaCacheStorage
    ATTACHMENTS = {
      'Account' => %i(avatar header),
      'MediaAttachment' => %i(file thumbnail),
      'CustomEmoji' => %i(image),
      'PreviewCard' => %i(image),
    }.freeze

    class ConfigurationError < StandardError; end

    module_function

    def enabled?
      ENV['CACHE_S3_ENABLED'] == 'true'
    end

    def managed?(attachment)
      ATTACHMENTS.fetch(attachment.instance.class.base_class.name, []).include?(attachment.name)
    end

    def eligible?(record)
      record.is_a?(PreviewCard) || (ATTACHMENTS.key?(record.class.base_class.name) && !record.local?)
    end

    def profile(backend)
      prefix = backend.to_sym == :cache ? 'CACHE_' : ''
      raise ConfigurationError, "#{prefix}S3_BUCKET is required" if ENV["#{prefix}S3_BUCKET"].blank?

      region = ENV.fetch("#{prefix}S3_REGION", 'us-east-1')
      credentials = if prefix.empty?
                      {}
                    else
                      %w(AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY).to_h do |key|
                        value = ENV.fetch("#{prefix}#{key}", nil)
                        raise ConfigurationError, "#{prefix}#{key} is required" if value.blank?

                        [key.delete_prefix('AWS_').downcase.to_sym, value]
                      end
                    end

      {
        bucket: ENV.fetch("#{prefix}S3_BUCKET"),
        region: region,
        protocol: ENV.fetch("#{prefix}S3_PROTOCOL", 'https'),
        hostname: ENV.fetch("#{prefix}S3_HOSTNAME", "s3-#{region}.amazonaws.com"),
        alias: ENV["#{prefix}S3_ALIAS_HOST"] || ENV.fetch("#{prefix}S3_CLOUDFRONT_HOST", nil),
        permission: ENV.fetch("#{prefix}S3_PERMISSION", 'public-read').presence,
        path: [ENV.fetch("#{prefix}S3_KEY_PREFIX", nil), ':prefix_url:class/:attachment/:id_partition/:style/:filename'].compact.join('/'),
        options: credentials.merge(
          region: region,
          signature_version: ENV.fetch("#{prefix}S3_SIGNATURE_VERSION", 'v4'),
          http_open_timeout: ENV.fetch("#{prefix}S3_OPEN_TIMEOUT", '5').to_i,
          http_read_timeout: ENV.fetch("#{prefix}S3_READ_TIMEOUT", '5').to_i,
          http_idle_timeout: 5,
          retry_limit: ENV.fetch("#{prefix}S3_RETRY_LIMIT", '0').to_i
        ).merge(ENV.key?("#{prefix}S3_ENDPOINT") ? { endpoint: ENV["#{prefix}S3_ENDPOINT"], force_path_style: ENV["#{prefix}S3_OVERRIDE_PATH_STYLE"] != 'true' } : {}),
      }
    end

    def circuit_key(attachment)
      attachment.respond_to?(:wxw_backend) ? "object-storage-#{attachment.wxw_backend}" : 'object-storage'
    end

    def media_host
      return if ENV['CACHE_S3_BUCKET'].blank?

      host = ENV['CACHE_S3_ALIAS_HOST'] || ENV['CACHE_S3_CLOUDFRONT_HOST'] || ENV['CACHE_S3_HOSTNAME'] || "s3-#{ENV.fetch('CACHE_S3_REGION', 'us-east-1')}.amazonaws.com"
      protocol = ENV.fetch('CACHE_S3_PROTOCOL', 'https').presence || 'https'
      Addressable::URI.parse("#{protocol}://#{host}").tap do |uri|
        uri.path += '/' unless uri.path.blank? || uri.path.end_with?('/')
      end.to_s
    end

    def with_circuit(backend, &block)
      Stoplight("object-storage-#{backend}", cool_off_time: 30, threshold: 10, tracked_errors: [Seahorse::Client::NetworkingError]).run(&block)
    end

    def acl_for(attachment, direction)
      backend = attachment.wxw_backend
      permission = ENV.fetch("#{'CACHE_' if backend == :cache}S3_PERMISSION", 'public-read')
      return if permission.empty?

      direction == :public ? permission : 'private'
    end

    def update_object_permission(attachment, object, direction, retained:)
      permission = acl_for(attachment, direction)
      if permission
        object.acl.put(acl: permission)
        :updated
      elsif retained && direction == :private
        object.delete
        :deleted
      end
    end

    def update_permissions(attachment, style, direction)
      current = attachment.wxw_backend
      attachment.wxw_backends.each do |backend|
        object = nil
        attachment.wxw_with_backend(backend) do
          object = attachment.s3_object(style)
          result = update_object_permission(attachment, object, direction, retained: backend != current)
          CacheBusterWorker.perform_async(attachment.url(style)) if result && backend != current && Rails.configuration.x.cache_buster.enabled
        end
      rescue Aws::S3::Errors::NoSuchKey
        Rails.logger.warn "Tried to change acl on non-existent key #{object.key}"
      rescue Aws::S3::Errors::NotImplemented => e
        Rails.logger.error "Error trying to change ACL on #{object.key}: #{e.message}"
      end
    end

    def bucket(backend)
      attachment = MediaAttachment.new.file
      attachment.wxw_with_backend(backend) { attachment.s3_bucket }
    end

    def delete_locations(locations)
      locations.group_by(&:first).each do |backend, entries|
        urls = entries.to_h { |_, key, url| [key, url] }
        delete_objects(backend, urls.keys) do |deleted_keys|
          CacheBusterWorker.push_bulk(deleted_keys.filter_map { |key| urls[key] }.uniq) { |url| [url] } if Rails.configuration.x.cache_buster.enabled
        end
      end
    end

    def delete_objects(backend, keys)
      return if keys.empty?

      s3_bucket = bucket(backend)
      prefix = backend.to_sym == :cache ? 'CACHE_' : ''
      limit = Integer(ENV.fetch("#{prefix}S3_BATCH_DELETE_LIMIT", '1000')).clamp(1, 1000)
      retries = Integer(ENV.fetch("#{prefix}S3_BATCH_DELETE_RETRY", '3')).clamp(1, 10)
      keys.uniq.each_slice(limit) do |slice|
        attempts = 0
        begin
          result = with_circuit(backend) do
            with_overridden_timeout(s3_bucket.client, 120) do
              s3_bucket.delete_objects(delete: { objects: slice.map { |key| { key: key } }, quiet: true })
            end
          end
          yield(slice - result.errors.map(&:key)) if block_given?
          raise IOError, "S3 refused to delete #{result.errors.size} objects: #{result.errors.first.code}" if result.errors.any?
        rescue Seahorse::Client::NetworkingError, Aws::Errors::ServiceError, IOError
          attempts += 1
          raise if attempts >= retries

          sleep 2**attempts
          retry
        end
      end
    end

    def with_overridden_timeout(s3_client, longer_read_timeout)
      original_timeout = s3_client.config.http_read_timeout
      s3_client.config.http_read_timeout = [original_timeout, longer_read_timeout].max
      begin
        yield
      ensure
        s3_client.config.http_read_timeout = original_timeout
      end
    end

    def cache_associations(klass, associations)
      return associations unless Paperclip::Attachment.default_options[:storage] == :s3

      result = Array.wrap(associations).map do |association|
        if association.is_a?(Hash)
          association.to_h do |name, children|
            reflection = klass.reflect_on_association(name)
            [name, reflection && !reflection.polymorphic? ? cache_associations(reflection.klass, children) : children]
          end
        else
          reflection = klass.reflect_on_association(association)
          reflection && !reflection.polymorphic? && ATTACHMENTS.key?(reflection.klass.name) ? { association => :wxw_media_caches } : association
        end
      end
      result << :wxw_media_caches if ATTACHMENTS.key?(klass.name)
      result.uniq
    end

    module Record
      extend ActiveSupport::Concern

      included do
        has_many :wxw_media_caches, class_name: 'WxwMediaCache', as: :record, dependent: :delete_all, inverse_of: :record
        after_save :wxw_save_media_routes
        after_commit :wxw_commit_media_files
        after_rollback :wxw_rollback_media_files
      end

      private

      def wxw_each_attachment
        MediaCacheStorage::ATTACHMENTS.fetch(self.class.base_class.name).each do |name|
          attachment = public_send(name)
          yield attachment if attachment.respond_to?(:wxw_backend)
        end
      end

      def wxw_save_media_routes
        wxw_each_attachment(&:wxw_save_route)
      end

      def wxw_commit_media_files
        wxw_each_attachment(&:wxw_commit)
      end

      def wxw_rollback_media_files
        wxw_each_attachment(&:wxw_reset)
      end
    end

    module Batch
      def delete
        wxw_remove_routes { super }
      end

      def clear
        wxw_remove_routes { super }
      end

      private

      def wxw_remove_routes
        return yield unless storage_mode == :s3 && MediaCacheStorage::ATTACHMENTS.key?(klass.name)

        klass.transaction do
          @records = klass.where(id: records.map(&:id)).order(:id).lock.includes(:wxw_media_caches).to_a
          result = yield
          WxwMediaCache.where(record_type: klass.base_class.name, record_id: records.map(&:id)).delete_all
          result
        end
      end
    end

    module Permissions
      def call(scope, direction)
        return super unless Paperclip::Attachment.default_options[:storage] == :s3

        scope.find_each do |record|
          record.with_lock { super(MediaAttachment.where(id: record.id), direction) }
        end
      end
    end
  end
end
