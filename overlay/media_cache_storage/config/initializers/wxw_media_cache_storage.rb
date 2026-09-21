# frozen_string_literal: true

require_relative '../../lib/wxw/media_cache_storage/attachment'

if Wxw::MediaCacheStorage.enabled?
  raise Wxw::MediaCacheStorage::ConfigurationError, 'CACHE_S3_ENABLED requires S3_ENABLED=true' unless Paperclip::Attachment.default_options[:storage] == :s3

  Wxw::MediaCacheStorage.profile(:cache)
end

Paperclip::Storage::S3.prepend(Wxw::MediaCacheStorage::Attachment) if Paperclip::Attachment.default_options[:storage] == :s3

Rails.application.reloader.to_prepare do
  Wxw::MediaCacheStorage::ATTACHMENTS.each_key { |name| name.constantize.include(Wxw::MediaCacheStorage::Record) }
  AttachmentBatch.prepend(Wxw::MediaCacheStorage::Batch)
  UpdateMediaAttachmentsPermissionsService.prepend(Wxw::MediaCacheStorage::Permissions)
end
