# frozen_string_literal: true

class WxwMediaCacheCleanupWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'scheduler', retry: 5

  def perform(record_type, record_id, attachment_name, deletions)
    return unless Wxw::MediaCacheStorage::ATTACHMENTS.fetch(record_type, []).include?(attachment_name.to_sym)

    record_type.constantize.transaction do
      record = record_type.constantize.lock.find_by(id: record_id)
      attachment = record&.public_send(attachment_name)
      live_keys = attachment.present? ? ([:original] | attachment.styles.keys).map { |style| [attachment.wxw_backend.to_s, attachment.style_name_as_path(style)] } : []
      deletions = deletions.reject { |backend, key, _url| live_keys.include?([backend, key]) }
      Wxw::MediaCacheStorage.delete_locations(deletions)
    end
  end
end
