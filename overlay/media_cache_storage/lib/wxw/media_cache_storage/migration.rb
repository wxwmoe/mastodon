# frozen_string_literal: true

require 'digest'
require 'tempfile'

class Wxw::MediaCacheStorage::Migration
  def self.call(record, attachment_name, target:, dry_run: false, source_permission: nil)
    new(record, attachment_name, target.to_sym, dry_run, source_permission).call
  end

  def initialize(record, attachment_name, target, dry_run, source_permission)
    @record = record
    @attachment_name = attachment_name
    @target = target
    @dry_run = dry_run
    @source_permission = source_permission
  end

  def call
    raise ArgumentError, 'Storage must be main or cache' unless %i(main cache).include?(@target)
    raise ArgumentError, 'Source permission must be public-read or private' unless @source_permission.nil? || %w(public-read private).include?(@source_permission)

    @record.with_lock do
      raise ArgumentError, 'Only remote media can migrate to cache' if @target == :cache && !Wxw::MediaCacheStorage.eligible?(@record)

      @record.association(:wxw_media_caches).reset
      attachment = @record.public_send(@attachment_name)
      return 0 if attachment.blank? || attachment.wxw_backend == @target
      return attachment.size if @dry_run

      source = attachment.wxw_backend
      size = ([:original] | attachment.styles.keys).sum do |style|
        copy_style(attachment, style, source)
      end

      rows = WxwMediaCache.where(record: @record, attachment_name: @attachment_name.to_s)
      if @target == :cache
        rows.create!(generation: 1)
      else
        rows.delete_all
      end
      @record.touch
      size
    end
  ensure
    @record.association(:wxw_media_caches).reset
  end

  private

  def copy_style(attachment, style, source_backend)
    source = attachment.wxw_with_backend(source_backend) { attachment.s3_object(style) }
    target = attachment.wxw_with_backend(@target) { attachment.s3_object(style) }
    raise ArgumentError, 'Source and target must use different buckets or endpoints' if source.bucket_name == target.bucket_name && source.client.config.endpoint == target.client.config.endpoint

    Tempfile.create('media-cache-copy') do |file|
      file.binmode
      begin
        response = source.get(response_target: file)
      rescue Aws::S3::Errors::NoSuchKey
        raise if style == :original

        return 0
      end
      file.flush
      permission = source_permission(source, source_backend)
      target_permission = Wxw::MediaCacheStorage.profile(@target)[:permission]
      raise Wxw::MediaCacheStorage::ConfigurationError, 'Cannot preserve object permissions with this ACL configuration' if (permission.nil? && target_permission.present?) || (permission == 'private' && target_permission.nil?)

      headers = response.to_h.slice(:content_type, :content_disposition, :content_encoding, :content_language, :cache_control, :expires, :metadata).compact
      headers[:acl] = permission if target_permission
      prefix = @target == :cache ? 'CACHE_' : ''
      headers[:storage_class] = ENV["#{prefix}S3_STORAGE_CLASS"] if ENV["#{prefix}S3_STORAGE_CLASS"].present?
      headers[:multipart_threshold] = ENV.fetch("#{prefix}S3_MULTIPART_THRESHOLD", 15.megabytes).to_i
      target.upload_file(file.path, headers)

      expected = Digest::SHA256.file(file.path).hexdigest
      actual = Digest::SHA256.new
      target.get { |chunk| actual.update(chunk) }
      raise IOError, "Checksum mismatch for #{target.key}" unless expected == actual.hexdigest

      file.size
    end
  end

  def source_permission(object, backend)
    prefix = backend == :cache ? 'CACHE_' : ''
    return @source_permission if ENV["#{prefix}S3_PERMISSION"] == ''

    acl = object.client.get_object_acl(bucket: object.bucket_name, key: object.key)
    public_read = false
    acl.grants.each do |grant|
      if grant.grantee.id == acl.owner.id && grant.grantee.type == 'CanonicalUser'
        next
      elsif grant.grantee.uri == 'http://acs.amazonaws.com/groups/global/AllUsers' && grant.permission == 'READ'
        public_read = true
      else
        raise Wxw::MediaCacheStorage::ConfigurationError, 'Custom S3 grants cannot be migrated automatically'
      end
    end
    public_read ? 'public-read' : 'private'
  end
end
