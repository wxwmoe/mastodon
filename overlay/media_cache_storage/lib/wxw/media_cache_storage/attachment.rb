# frozen_string_literal: true

module Wxw::MediaCacheStorage::Attachment
  def wxw_backend
    return @wxw_override if @wxw_override
    return @wxw_write_backend if @wxw_write_backend
    return :main unless Wxw::MediaCacheStorage.managed?(self)

    instance.wxw_media_caches.any? { |row| row.attachment_name == name.to_s } ? :cache : :main
  end

  def wxw_with_backend(backend)
    previous = @wxw_override
    @wxw_override = backend.to_sym
    yield
  ensure
    @wxw_override = previous
  end

  def wxw_backends
    current = wxw_backend
    return [current] unless Wxw::MediaCacheStorage.managed?(self) && (current == :cache || Wxw::MediaCacheStorage.eligible?(instance))

    [current, :main, (:cache if ENV['CACHE_S3_BUCKET'].present?)].compact.uniq
  end

  def wxw_locations(style)
    wxw_backends.map do |backend|
      wxw_with_backend(backend) { [backend.to_s, style_name_as_path(style), url(style)] }
    end
  end

  def assign(uploaded_file)
    result = super
    @wxw_write_backend = wxw_new_backend if dirty? && !options[:preserve_files] && Wxw::MediaCacheStorage.managed?(self)
    result
  end

  def save
    return super unless Wxw::MediaCacheStorage.managed?(self) && (dirty? || @queued_for_write.any? || @queued_for_delete.any?)

    wxw_locked do
      @wxw_write_backend = wxw_new_backend if @wxw_write_backend && !options[:preserve_files]
      result = super
      @wxw_saved = true
      result
    end
  end

  def reprocess!(*styles)
    return super unless Wxw::MediaCacheStorage.managed?(self)

    wxw_locked { super }
  end

  def queue_all_for_delete
    return super unless Wxw::MediaCacheStorage.managed?(self) && !options[:preserve_files]

    wxw_capture_deletes([:original] | styles.keys) { super }
  end

  def queue_some_for_delete(*styles)
    return super unless Wxw::MediaCacheStorage.managed?(self) && !options[:preserve_files]

    wxw_capture_deletes(styles.uniq) { super }
  end

  def flush_deletes
    return super unless Wxw::MediaCacheStorage.managed?(self)

    (@wxw_deferred_deletes ||= []).concat(@wxw_queued_deletes || [])
    @wxw_queued_deletes = []
    @queued_for_delete = []
    wxw_commit if instance.destroyed? && !instance.class.connection.transaction_open?
  end

  def wxw_save_route
    return unless @wxw_saved || (!file? && instance.saved_change_to_attribute?("#{name}_file_name"))

    rows = WxwMediaCache.where(record: instance, attachment_name: name.to_s)
    if file? && wxw_backend == :cache
      row = rows.first_or_initialize
      row.generation += 1
      row.save!
    else
      rows.delete_all
    end
    @wxw_saved = false
    instance.association(:wxw_media_caches).reset
  end

  def wxw_commit
    deletions = @wxw_deferred_deletes
    WxwMediaCacheCleanupWorker.perform_async(instance.class.base_class.name, instance.id, name.to_s, deletions.uniq) if deletions.present?
    wxw_reset
  rescue Redis::BaseError => e
    Rails.logger.error "Media cleanup could not be queued: #{e.message}"
    wxw_reset
  end

  def wxw_reset
    @wxw_write_backend = @wxw_saved = nil
    @wxw_deferred_deletes = @wxw_queued_deletes = nil
    instance.association(:wxw_media_caches).reset
  end

  def path(style_name = default_style)
    return super unless wxw_backend == :cache
    return unless original_filename

    interpolate(Wxw::MediaCacheStorage.profile(:cache)[:path], style_name)
  end

  def url(*args)
    return super unless wxw_backend == :cache

    previous = @options[:url]
    @options[:url] = Wxw::MediaCacheStorage.profile(:cache)[:alias] ? ':s3_alias_url' : ':s3_path_url'
    begin
      super
    ensure
      @options[:url] = previous
    end
  end

  def s3_interface
    return super unless wxw_backend == :cache

    obtain_s3_instance_for(Wxw::MediaCacheStorage.profile(:cache)[:options])
  end

  def s3_bucket
    wxw_backend == :cache ? s3_interface.bucket(bucket_name) : super
  end

  def bucket_name
    wxw_backend == :cache ? Wxw::MediaCacheStorage.profile(:cache)[:bucket] : super
  end

  def s3_host_name
    wxw_backend == :cache ? Wxw::MediaCacheStorage.profile(:cache)[:hostname] : super
  end

  def s3_host_alias
    wxw_backend == :cache ? Wxw::MediaCacheStorage.profile(:cache)[:alias] : super
  end

  def s3_protocol(style = default_style, with_colon = false) # rubocop:disable Style/OptionalBooleanParameter -- Paperclip API
    return super unless wxw_backend == :cache

    protocol = Wxw::MediaCacheStorage.profile(:cache)[:protocol]
    with_colon && protocol.present? ? "#{protocol}:" : protocol
  end

  def s3_permissions(style = default_style)
    wxw_backend == :cache ? Wxw::MediaCacheStorage.profile(:cache)[:permission] : super
  end

  def s3_storage_class(style = default_style)
    wxw_backend == :cache ? ENV.fetch('CACHE_S3_STORAGE_CLASS', nil) : super
  end

  def s3_transfer_manager
    return super unless wxw_backend == :cache

    @wxw_transfer_manager ||= Aws::S3::TransferManager.new(client: s3_interface.client) if Aws::S3.const_defined?(:TransferManager, false)
  end

  def flush_writes
    return super unless wxw_backend == :cache

    headers = @s3_headers
    @s3_headers = { multipart_threshold: ENV.fetch('CACHE_S3_MULTIPART_THRESHOLD', 15.megabytes).to_i, cache_control: 'public, max-age=315576000, immutable' }
    begin
      super
    ensure
      @s3_headers = headers
    end
  end

  def copy_to_local_file(style, local_dest_path)
    return super unless wxw_backend == :cache

    download_options = {}
    download_options[:mode] = 'single_request' if ENV['CACHE_S3_FORCE_SINGLE_REQUEST'] == 'true'
    download_options[:checksum_mode] = 'DISABLED' unless ENV['CACHE_S3_ENABLE_CHECKSUM_MODE'] == 'true'
    s3_object(style).download_file(local_dest_path, download_options)
  rescue Aws::Errors::ServiceError => e
    warn("#{e} - cannot copy #{path(style)} to local file #{local_dest_path}")
    false
  end

  private

  def wxw_new_backend
    Wxw::MediaCacheStorage.enabled? && Wxw::MediaCacheStorage.eligible?(instance) ? :cache : :main
  end

  def wxw_capture_deletes(styles)
    locations = file? ? styles.flat_map { |style| wxw_locations(style) } : []
    result = yield
    (@wxw_queued_deletes ||= []).concat(locations)
    result
  end

  def wxw_locked
    instance.class.transaction do
      instance.class.where(id: instance.id).lock.pick(:id) if instance.persisted?
      instance.association(:wxw_media_caches).reset
      yield
    end
  end
end
