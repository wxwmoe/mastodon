# frozen_string_literal: true

require_relative 'migration'

module Wxw::MediaCacheStorage::CLI
  TYPES = { 'attachments' => 'MediaAttachment', 'accounts' => 'Account', 'emojis' => 'CustomEmoji', 'previews' => 'PreviewCard' }.freeze

  def wxw_migrate_storage
    fail_with_message 'This command requires S3 storage' unless Paperclip::Attachment.default_options[:storage] == :s3
    fail_with_message '--to must be main or cache' unless %w(main cache).include?(options[:to])
    fail_with_message '--start-after requires --type' if options[:start_after] && !options[:type]
    fail_with_message '--retries must be between 0 and 10' unless (0..10).cover?(options[:retries])

    types = options[:type] ? [TYPES.fetch(options[:type]) { fail_with_message "Unknown type: #{options[:type]}" }] : TYPES.values
    failures = Concurrent::AtomicFixnum.new(0)
    last_error = Concurrent::AtomicReference.new
    types.each do |type|
      scope = type.constantize.all
      scope = scope.remote unless type == 'PreviewCard' || options[:to] == 'main'
      scope = scope.where(id: WxwMediaCache.where(record_type: type).select(:record_id)) if options[:to] == 'main'
      scope = scope.where('id > ?', Integer(options[:start_after], 10)) if options[:start_after]
      processed, bytes = parallelize_with_progress(scope) do |record|
        Wxw::MediaCacheStorage::ATTACHMENTS.fetch(type).sum do |name|
          attempts = 0
          begin
            Wxw::MediaCacheStorage::Migration.call(record, name, target: options[:to], dry_run: dry_run?, source_permission: options[:source_permission])
          rescue Seahorse::Client::NetworkingError, Aws::Errors::ServiceError, IOError
            attempts += 1
            retry if attempts <= options[:retries]

            raise
          end
        end
      rescue => e
        failures.increment
        last_error.set("#{type} #{record.id}: #{e.message}")
        raise
      end
      say("Visited #{processed} #{type} records; migrated #{number_to_human_size(bytes)}#{dry_run_mode_suffix}", :green)
    end
    fail_with_message "#{failures.value} records failed; rerun the command to retry them. Last error: #{last_error.get}" if failures.value.positive?
    say('Source copies were retained. Clear the Rails cache before retiring their URLs; use remove-orphans --remove-migrated for later cleanup.') unless dry_run?
  end

  def wxw_remove_s3_orphans
    backends = if options[:storage] == 'all'
                 [:main, *(ENV['CACHE_S3_BUCKET'].present? || WxwMediaCache.exists? ? [:cache] : [])]
               else
                 [options[:storage].to_sym]
               end
    fail_with_message '--storage must be main, cache or all' unless (backends - %i(main cache)).empty?
    fail_with_message '--start-after requires one --storage' if backends.size > 1 && options[:start_after]
    fail_with_message '--days must be nonnegative' if options[:days].negative?
    Wxw::MediaCacheStorage.profile(:cache) if backends.include?(:cache)

    removed = 0
    bytes = 0
    backends.each do |backend|
      prefix = backend == :cache ? 'CACHE_' : ''
      key_prefix = ENV.key?("#{prefix}S3_KEY_PREFIX") ? "#{ENV.fetch("#{prefix}S3_KEY_PREFIX")}/".delete_prefix('/') : ''
      bucket = Wxw::MediaCacheStorage.bucket(backend)
      objects = bucket.objects(prefix: key_prefix + options[:prefix].to_s, start_after: options[:start_after])
      objects.each do |object|
        location = wxw_object_location(object.key.delete_prefix(key_prefix))
        next unless location

        type, id, name, filename = location
        type.constantize.transaction do
          record = type.constantize.lock.find_by(id: id)
          attachment = record&.public_send(name)
          live = attachment.present? && attachment.variant?(filename)
          current_backend = attachment.respond_to?(:wxw_backend) ? attachment.wxw_backend : :main
          if live && options[:fix_permissions] && !dry_run?
            result = attachment.wxw_with_backend(backend) do
              Wxw::MediaCacheStorage.update_object_permission(attachment, object, wxw_permission_direction(record), retained: current_backend != backend)
            end
            if result == :deleted
              removed += 1
              bytes += object.size
              say("#{backend}: #{object.key}")
              next
            end
          end
          next if live && (current_backend == backend || !options[:remove_migrated])
          next if object.last_modified > options[:days].days.ago

          object.delete unless dry_run?
          removed += 1
          bytes += object.size
          say("#{backend}: #{object.key}")
        end
      rescue => e
        fail_with_message "#{backend}: #{object.key}: #{e.message}; rerun with --storage=#{backend} to retry"
      end
    end
    say("Removed #{removed} orphans (#{number_to_human_size(bytes)})#{dry_run_mode_suffix}", :green)
  end

  private

  def wxw_object_location(key)
    segments = key.delete_prefix('cache/').split('/')
    return unless [7, 10].include?(segments.length)

    type = segments.first.classify
    return unless self.class::PRELOADED_MODELS.include?(type)
    return unless segments[2...-2].all? { |part| /\A\d{3}\z/.match?(part) }

    name = segments[1].singularize.to_sym
    return unless type.constantize.attachment_definitions.key?(name)

    [type, segments[2...-2].join.to_i, name, segments.last]
  end

  def wxw_permission_direction(record)
    record.is_a?(Backup) || (record.is_a?(MediaAttachment) && (record.discarded? || record.account&.suspended?)) ? :private : :public
  end
end
