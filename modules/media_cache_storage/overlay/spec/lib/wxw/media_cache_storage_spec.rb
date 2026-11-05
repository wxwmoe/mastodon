# frozen_string_literal: true

require 'rails_helper'
require 'aws-sdk-s3'
require_relative '../../../lib/wxw/media_cache_storage/migration'
require_relative '../../../lib/mastodon/cli/media'

RSpec.describe Wxw::MediaCacheStorage do
  let(:objects) { {} }
  let(:requests) { [] }
  let(:multipart_uploads) { {} }
  let(:account) { Fabricate(:account, domain: 'remote.example') }

  around do |example|
    ClimateControl.modify(
      CACHE_S3_ENABLED: 'true', CACHE_S3_BUCKET: 'cache-media', CACHE_AWS_ACCESS_KEY_ID: 'cache-key', CACHE_AWS_SECRET_ACCESS_KEY: 'cache-secret',
      CACHE_S3_ALIAS_HOST: 'cache.example', CACHE_S3_PROTOCOL: 'https', CACHE_S3_KEY_PREFIX: 'second', CACHE_S3_PERMISSION: 'public-read',
      S3_BUCKET: 'main-media', S3_PERMISSION: 'public-read', S3_KEY_PREFIX: 'first'
    ) do
      original = Paperclip::Attachment.default_options.deep_dup
      Paperclip::Attachment.default_options.merge!(storage: :s3, path: 'first/:prefix_url:class/:attachment/:id_partition/:style/:filename', url: ':s3_alias_url', s3_host_alias: 'main.example', s3_protocol: 'https', s3_region: 'us-east-1',
                                                   s3_credentials: { bucket: 'main-media', access_key_id: 'main-key', secret_access_key: 'main-secret' }, s3_permissions: 'public-read')
      Paperclip::Storage::S3.prepend(Wxw::MediaCacheStorage::Attachment) unless Paperclip::Storage::S3 < Wxw::MediaCacheStorage::Attachment
      Thread.current[:paperclip_s3_instances] = {}
      example.run
    ensure
      Paperclip::Attachment.default_options.replace(original)
      Thread.current[:paperclip_s3_instances] = {}
    end
  end

  before do
    allow(Aws::S3::Resource).to receive(:new).and_wrap_original do |original, options|
      original.call(options.merge(stub_responses: true)).tap { |resource| stub_storage(resource.client) }
    end
  end

  after(:each, use_transactional_tests: false) do
    MediaAttachment.where(account: account).find_each(&:destroy!)
    account.destroy!
  end

  def stub_storage(client)
    client.stub_responses(:create_multipart_upload, lambda { |context|
      id = SecureRandom.hex
      multipart_uploads[id] = { params: context.params, parts: {} }
      requests << [context.operation_name, context.params]
      { upload_id: id }
    })
    client.stub_responses(:upload_part, lambda { |context|
      params = context.params
      multipart_uploads.fetch(params[:upload_id])[:parts][params[:part_number]] = params[:body].read
      { etag: "part-#{params[:part_number]}" }
    })
    client.stub_responses(:complete_multipart_upload, lambda { |context|
      upload = multipart_uploads.fetch(context.params[:upload_id])
      params = upload[:params]
      objects[[params[:bucket], params[:key]]] = { body: upload[:parts].sort.map(&:last).join, content_type: params[:content_type], acl: params[:acl] || 'private' }
      { etag: 'multipart-etag' }
    })
    client.stub_responses(:put_object, lambda { |context|
      params = context.params
      body = params[:body]
      objects[[params[:bucket], params[:key]]] = { body: body.respond_to?(:read) ? body.read : body.to_s, content_type: params[:content_type], acl: params[:acl] || 'private' }
      requests << [context.operation_name, params]
      {}
    })
    %i(head_object get_object).each do |operation|
      client.stub_responses(operation, lambda { |context|
        object = objects[[context.params[:bucket], context.params[:key]]]
        next 'NoSuchKey' unless object

        response = { content_length: object[:body].bytesize, content_type: object[:content_type] || 'image/jpeg', metadata: {} }
        response[:body] = object[:body] if operation == :get_object
        response
      })
    end
    client.stub_responses(:get_object_acl, lambda { |context|
      object = objects.fetch([context.params[:bucket], context.params[:key]])
      grants = [{ grantee: { type: 'CanonicalUser', id: 'owner' }, permission: 'FULL_CONTROL' }]
      grants << { grantee: { type: 'Group', uri: 'http://acs.amazonaws.com/groups/global/AllUsers' }, permission: 'READ' } if object[:acl] == 'public-read'
      { owner: { id: 'owner' }, grants: grants }
    })
    client.stub_responses(:put_object_acl, lambda { |context|
      next 'NoSuchKey' unless objects.key?([context.params[:bucket], context.params[:key]])

      requests << [context.operation_name, context.params]
      objects.fetch([context.params[:bucket], context.params[:key]])[:acl] = context.params[:acl]
      {}
    })
    client.stub_responses(:delete_objects, lambda { |context|
      requests << [context.operation_name, context.params]
      context.params[:delete][:objects].each { |object| objects.delete([context.params[:bucket], object[:key]]) }
      {}
    })
    client.stub_responses(:delete_object, lambda { |context|
      requests << [context.operation_name, context.params]
      objects.delete([context.params[:bucket], context.params[:key]])
      {}
    })
    client.stub_responses(:list_objects_v2, lambda { |context|
      contents = objects.filter_map do |(bucket, key), object|
        next unless bucket == context.params[:bucket] && key.start_with?(context.params[:prefix].to_s)

        { key: key, size: object[:body].bytesize, last_modified: 10.days.ago }
      end
      { contents: contents, is_truncated: false }
    })
  end

  def upload(remote: true)
    Fabricate(:media_attachment, account: account, remote_url: remote ? 'https://remote.example/image.jpg' : '')
  end

  def keys(record, attachment_name = :file)
    attachment = record.public_send(attachment_name)
    [attachment.bucket_name, attachment.style_name_as_path(:original)]
  end

  it 'routes new remote files to cache and local files to main, including URLs and signed downloads' do
    remote = upload
    local = upload(remote: false)

    expect(remote.wxw_media_caches.pluck(:attachment_name)).to eq(['file'])
    expect(local.wxw_media_caches).to be_empty
    expect(objects).to have_key(keys(remote))
    expect(remote.file.url).to start_with('https://cache.example/second/cache/media_attachments/')
    expect(local.file.url).to start_with('https://main.example/first/media_attachments/')
    expect(remote.file.expiring_url(60)).to include('cache-media', 'X-Amz-Expires=60')
    expect(Aws::S3::Resource).to have_received(:new).with(hash_including(access_key_id: 'cache-key', secret_access_key: 'cache-secret')).at_least(:once)
  end

  it 'routes remote profile images, emojis and previews, leaving imported local emojis on main' do
    emoji = Fabricate(:custom_emoji, domain: 'remote.example')
    local_emoji = Fabricate(:custom_emoji)
    preview = Fabricate(:preview_card, image: attachment_fixture('attachment.jpg'))
    account.update!(avatar: attachment_fixture('attachment.jpg'), header: attachment_fixture('attachment.jpg'))

    expect(account.wxw_media_caches.pluck(:attachment_name)).to match_array(%w(avatar header))
    expect(emoji.image.wxw_backend).to eq(:cache)
    expect(preview.image.wxw_backend).to eq(:cache)
    expect(local_emoji.image.wxw_backend).to eq(:main)
  end

  it 'keeps existing cache routes readable when disabled and refuses missing cache credentials' do
    media = upload
    ClimateControl.modify(CACHE_S3_ENABLED: 'false') do
      expect(media.reload.file.wxw_backend).to eq(:cache)
      expect(upload.file.wxw_backend).to eq(:main)
    end
    ClimateControl.modify(CACHE_AWS_ACCESS_KEY_ID: nil) do
      expect { media.file.s3_bucket }.to raise_error(described_class::ConfigurationError)
    end
  end

  it 'keeps the original until commit when replacing a main file with a cache file' do
    media = ClimateControl.modify(CACHE_S3_ENABLED: 'false') { upload }
    original = keys(media)
    media.update!(file: attachment_fixture('attachment.jpg'))

    expect(media.reload.file.wxw_backend).to eq(:cache)
    expect(objects).to have_key(original)
    WxwMediaCacheCleanupWorker.drain
    expect(objects).to_not have_key(original)
    expect(objects).to have_key(keys(media))
  end

  it 'retains the committed route and original when the owner transaction rolls back' do
    media = upload
    original = keys(media)
    ClimateControl.modify(CACHE_S3_ENABLED: 'false') do
      MediaAttachment.transaction(requires_new: true) do
        media.update!(file: attachment_fixture('attachment.jpg'))
        raise ActiveRecord::Rollback
      end
    end
    WxwMediaCacheCleanupWorker.drain

    expect(media.reload.file.wxw_backend).to eq(:cache)
    expect(keys(media)).to eq(original)
    expect(objects).to have_key(original)
  end

  it 'does not publish a cache route when uploading fails' do
    media = ClimateControl.modify(CACHE_S3_ENABLED: 'false') { upload }
    original = keys(media)
    media.file = attachment_fixture('attachment.jpg')
    media.file.s3_interface.client.stub_responses(:put_object, 'AccessDenied')

    expect { media.save! }.to raise_error(Aws::S3::Errors::AccessDenied)
    expect(media.reload.file.wxw_backend).to eq(:main)
    expect(objects).to have_key(original)
    expect(WxwMediaCacheCleanupWorker.jobs).to be_empty
  end

  it 'retains the backend during reprocessing even when new cache writes are disabled' do
    media = upload
    ClimateControl.modify(CACHE_S3_ENABLED: 'false') { media.file.reprocess!(:original) }

    expect(media.reload.file.wxw_backend).to eq(:cache)
    expect(objects).to have_key(keys(media))
  end

  it 'retains migration source copies when reprocessing a specific style in either direction' do
    %i(main cache).each do |target|
      media = ClimateControl.modify(CACHE_S3_ENABLED: (target == :main).to_s) { upload }
      source = keys(media)
      source_object = objects.fetch(source).dup
      described_class::Migration.call(media, :file, target: target)

      ClimateControl.modify(CACHE_S3_ENABLED: (target == :main).to_s) { media.reload.file.reprocess!(:original) }
      WxwMediaCacheCleanupWorker.drain

      expect(media.reload.file.wxw_backend).to eq(target)
      expect(objects).to have_key(keys(media))
      expect(objects.fetch(source)).to eq(source_object)
    end
  end

  it 'retains migration source copies during background post-processing' do
    media = ClimateControl.modify(CACHE_S3_ENABLED: 'false') { upload }
    media.update!(file_meta: {})
    source = keys(media)
    source_object = objects.fetch(source).dup
    described_class::Migration.call(media, :file, target: :cache)

    PostProcessMediaWorker.new.perform(media.id)
    WxwMediaCacheCleanupWorker.drain

    expect(media.reload).to be_processing_complete
    expect(media.file.wxw_backend).to eq(:cache)
    expect(objects.fetch(source)).to eq(source_object)
  end

  it 'groups batch deletions by backend and removes location rows' do
    remote = upload
    local = upload(remote: false)
    AttachmentBatch.new(MediaAttachment, [remote, local]).clear

    expect(objects).to be_empty
    expect(WxwMediaCache.where(record_type: 'MediaAttachment', record_id: [remote.id, local.id])).to be_empty
    deletions = requests.filter_map { |operation, params| params[:bucket] if operation == :delete_objects }
    expect(deletions).to contain_exactly('main-media', 'cache-media')
    expect(remote.reload.file).to be_blank
  end

  it 'does not clear records on partial S3 batch deletion errors' do
    media = upload
    media.file.s3_interface.client.stub_responses(:delete_objects, errors: [{ key: keys(media).last, code: 'AccessDenied' }])
    ClimateControl.modify(CACHE_S3_BATCH_DELETE_RETRY: '1') do
      expect { AttachmentBatch.new(MediaAttachment, [media]).clear }.to raise_error(IOError)
    end
    expect(media.reload.file).to be_present
    expect(media.wxw_media_caches).to_not be_empty
  end

  it 'changes ACLs per backend without the main ACL setting suppressing cache calls' do
    media = upload
    ClimateControl.modify(S3_PERMISSION: '') do
      UpdateMediaAttachmentsPermissionsService.new.call(MediaAttachment.where(id: media.id), :private)
    end
    expect(objects.fetch(keys(media))[:acl]).to eq('private')
    ClimateControl.modify(CACHE_S3_PERMISSION: '') do
      UpdateMediaAttachmentsPermissionsService.new.call(MediaAttachment.where(id: media.id), :public)
    end
    expect(objects.fetch(keys(media))[:acl]).to eq('private')
  end

  it 'copies, verifies and switches storage while preserving permissions and retaining source files' do
    media = ClimateControl.modify(CACHE_S3_ENABLED: 'false') { upload }
    original = keys(media)
    objects.fetch(original)[:acl] = 'private'
    described_class::Migration.call(media, :file, target: :cache)

    expect(media.reload.file.wxw_backend).to eq(:cache)
    expect(objects.fetch(keys(media))).to eq(objects.fetch(original))
    expect(described_class::Migration.call(media, :file, target: :cache)).to eq(0)
    described_class::Migration.call(media, :file, target: :main)
    expect(media.reload.wxw_media_caches).to be_empty
    expect(objects).to have_key(original)
  end

  it 'leaves the source authoritative if verification fails or the run is a dry run' do
    media = ClimateControl.modify(CACHE_S3_ENABLED: 'false') { upload }
    described_class::Migration.call(media, :file, target: :cache, dry_run: true)
    expect(objects.size).to eq(1)
    media.file.wxw_with_backend(:cache) { media.file.s3_interface.client.stub_responses(:get_object, body: 'corrupt') }

    expect { described_class::Migration.call(media, :file, target: :cache) }.to raise_error(IOError, /Checksum mismatch/)
    expect(media.reload.file.wxw_backend).to eq(:main)
    expect(objects).to have_key(keys(media))
  end

  it 'does not remove a copy that became live again after reverse migration' do
    media = upload
    cached = keys(media)
    cached_url = media.file.url(:original)
    described_class::Migration.call(media, :file, target: :main)
    described_class::Migration.call(media, :file, target: :cache)
    allow(Rails.configuration.x.cache_buster).to receive(:enabled).and_return(true)
    WxwMediaCacheCleanupWorker.new.perform('MediaAttachment', media.id, 'file', [['cache', cached.last, cached_url]])

    expect(objects).to have_key(cached)
    expect(CacheBusterWorker.jobs).to be_empty
  end

  it 'preserves migration copies during ordinary cleanup and removes them only on explicit cleanup' do
    media = upload
    cached = keys(media)
    described_class::Migration.call(media, :file, target: :main)
    command = Mastodon::CLI::Media.new([], { storage: 'cache', days: 7, dry_run: false, remove_migrated: false })
    command.remove_orphans
    expect(objects).to have_key(cached)
    command = Mastodon::CLI::Media.new([], { storage: 'cache', days: 7, dry_run: false, remove_migrated: true })
    command.remove_orphans
    expect(objects).to_not have_key(cached)
    expect(objects).to have_key(keys(media))
  end

  it 'preloads cache locations with cached status associations' do
    status = Fabricate(:status, account: account)
    media = upload
    media.update!(status: status)
    loaded = Status.with_includes.find(status.id)

    expect(loaded.account.association(:wxw_media_caches)).to be_loaded
    expect(loaded.media_attachments.first.association(:wxw_media_caches)).to be_loaded
    expect(loaded.media_attachments.first.file.wxw_backend).to eq(:cache)
  end

  it 'uploads multipart files to cache with its own storage class and preserves every byte' do
    Tempfile.create(['media-cache', '.jpg']) do |file|
      file.binmode
      content = File.binread(attachment_fixture('attachment.jpg').path) + ('x' * 6.megabytes)
      file.write(content)
      file.rewind
      media = ClimateControl.modify(CACHE_S3_MULTIPART_THRESHOLD: 5.megabytes.to_s, CACHE_S3_STORAGE_CLASS: 'STANDARD_IA') do
        Fabricate(:media_attachment, account: account, remote_url: 'https://remote.example/image.jpg', file: file)
      end
      expect(media.file.wxw_backend).to eq(:cache)
      expect(objects.fetch(keys(media))[:body]).to eq(content)
      creation = requests.find { |operation, _| operation == :create_multipart_upload }.last
      expect(creation).to include(bucket: 'cache-media', storage_class: 'STANDARD_IA')
      expect(multipart_uploads.values.first[:parts].size).to be >= 2
    end
  end

  it 'retains a cache marker on metadata-only saves without changing its generation' do
    media = upload
    generation = media.wxw_media_caches.first.generation
    media.update!(description: 'Updated description')

    expect(media.reload.wxw_media_caches.first.generation).to eq(generation)
    expect(media.file.wxw_backend).to eq(:cache)
  end

  it 'cleans up locations and files after an attachment or its owner is destroyed' do
    media = upload
    media.file.destroy
    expect(objects).to_not be_empty
    media.save!
    WxwMediaCacheCleanupWorker.drain
    expect(objects).to be_empty
    expect(media.reload.wxw_media_caches).to be_empty

    media = upload
    media.destroy!
    WxwMediaCacheCleanupWorker.drain
    expect(objects).to be_empty
    expect(WxwMediaCache.where(record: media)).to be_empty
  end

  it 'migrates all existing styles together and leaves the route unchanged if any style cannot be verified' do
    media = upload
    original = objects.fetch(keys(media))
    style = media.file.styles.keys.first
    thumbnail_key = [media.file.bucket_name, media.file.style_name_as_path(style)]
    objects[thumbnail_key] = original.merge(body: 'thumbnail')
    media.file.wxw_with_backend(:main) do
      client = media.file.s3_interface.client
      client.stub_responses(:get_object, lambda { |context|
        key = [context.params[:bucket], context.params[:key]]
        { body: context.params[:key].include?("/#{style}/") ? 'corrupt' : objects.fetch(key)[:body] }
      })
    end

    expect { described_class::Migration.call(media, :file, target: :main) }.to raise_error(IOError, /Checksum mismatch/)
    expect(media.reload.file.wxw_backend).to eq(:cache)
    expect(objects).to have_key(thumbnail_key)
  end

  it 'omits cache ACLs when disabled and refuses to migrate private files to an ACL-disabled backend' do
    media = upload
    described_class::Migration.call(media, :file, target: :main)
    objects.fetch(keys(media))[:acl] = 'private'
    ClimateControl.modify(CACHE_S3_PERMISSION: '') do
      other = upload
      put = requests.reverse.find { |operation, params| operation == :put_object && params[:key] == keys(other).last }.last
      expect(put[:acl]).to be_nil
      expect { described_class::Migration.call(media, :file, target: :cache) }.to raise_error(described_class::ConfigurationError)
    end
    expect(media.reload.file.wxw_backend).to eq(:main)
  end

  it 'fails closed on database lookup errors instead of reading main storage' do
    media = upload
    media.reload
    allow(media).to receive(:wxw_media_caches).and_raise(ActiveRecord::StatementInvalid, 'database unavailable')

    expect { media.file.s3_object }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it 'keeps unknown keys and live backups private during permission repair' do
    backup = Fabricate(:backup)
    backup.update_columns(dump_file_name: 'export.tar.gz', dump_content_type: 'application/gzip', dump_file_size: 3)
    backup.reload
    backup_key = keys(backup, :dump)
    objects[backup_key] = { body: 'tar', acl: 'private' }
    objects[['main-media', 'first/unknown/application.dat']] = { body: 'unknown', acl: 'private' }
    command = Mastodon::CLI::Media.new([], { storage: 'main', days: 7, dry_run: false, remove_migrated: true, fix_permissions: true })
    command.remove_orphans

    expect(objects.fetch(backup_key)[:acl]).to eq('private')
    expect(objects).to have_key(['main-media', 'first/unknown/application.dat'])
  end

  it 'runs the migration command with worker threads and resumes without recopying completed records', type: :cli, use_transactional_tests: false do
    media = ClimateControl.modify(CACHE_S3_ENABLED: 'false') { upload }
    command = Mastodon::CLI::Media.new([], { to: 'cache', type: 'attachments', concurrency: 2, retries: 0, dry_run: false })
    command.migrate_storage

    expect(media.reload.file.wxw_backend).to eq(:cache)
    requests.clear
    command.migrate_storage
    expect(requests).to be_empty
  end

  it 'reports failed migrations through the CLI and keeps the old location', type: :cli, use_transactional_tests: false do
    media = ClimateControl.modify(CACHE_S3_ENABLED: 'false') { upload }
    objects.clear
    command = Mastodon::CLI::Media.new([], { to: 'cache', type: 'attachments', concurrency: 1, retries: 0, dry_run: false })

    expect { command.migrate_storage }.to raise_error(Thor::Error, /records failed/)
    expect(media.reload.file.wxw_backend).to eq(:main)
  end

  it 'uses explicit source permissions when migrating from an ACL-disabled provider' do
    media = ClimateControl.modify(CACHE_S3_PERMISSION: '') { upload }
    ClimateControl.modify(CACHE_S3_PERMISSION: '') do
      expect { described_class::Migration.call(media, :file, target: :main) }.to raise_error(described_class::ConfigurationError)
      described_class::Migration.call(media, :file, target: :main, source_permission: 'private')
    end

    expect(media.reload.file.wxw_backend).to eq(:main)
    expect(objects.fetch(keys(media))[:acl]).to eq('private')
  end

  it 'removes a location record when clearing an attachment whose objects are already missing' do
    media = upload
    objects.clear
    media.file.destroy
    media.save!

    expect(media.reload.file).to be_blank
    expect(media.wxw_media_caches).to be_empty
  end

  it 'revokes and restores permissions on migration copies in both directions, then removes them on deletion' do
    media = ClimateControl.modify(CACHE_S3_ENABLED: 'false') { upload }
    original = keys(media)
    described_class::Migration.call(media, :file, target: :cache)
    cached = keys(media.reload)
    directions = %i(private public)

    %i(cache main).each do |backend|
      described_class::Migration.call(media, :file, target: backend)
      media.reload
      directions.each do |direction|
        UpdateMediaAttachmentsPermissionsService.new.call(MediaAttachment.where(id: media.id), direction)
        expect(objects.values.pluck(:acl).uniq).to eq([direction == :private ? 'private' : 'public-read'])
        expect(objects.keys).to contain_exactly(original, cached)
      end
    end

    media.destroy!
    WxwMediaCacheCleanupWorker.drain
    expect(objects).to be_empty
  end

  it 'removes both migration copies when clearing or batch deleting an attachment' do
    allow(Rails.configuration.x.cache_buster).to receive(:enabled).and_return(true)
    %i(clear delete).each do |action|
      media = ClimateControl.modify(CACHE_S3_ENABLED: 'false') { upload }
      original_url = media.file.url(:original)
      described_class::Migration.call(media, :file, target: :cache)
      cached_url = media.reload.file.url(:original)

      AttachmentBatch.new(MediaAttachment, [media]).public_send(action)
      expect(objects).to be_empty
      expect(CacheBusterWorker.jobs.pluck('args').flatten).to include(original_url, cached_url)
    end
  end

  it 'invalidates both URLs after successful deferred deletion of migrated media' do
    media = ClimateControl.modify(CACHE_S3_ENABLED: 'false') { upload }
    original_url = media.file.url(:original)
    original = keys(media)
    described_class::Migration.call(media, :file, target: :cache)
    cached_url = media.reload.file.url(:original)
    cached = keys(media)
    allow(Rails.configuration.x.cache_buster).to receive(:enabled).and_return(true)

    media.destroy!
    expect(objects.keys).to contain_exactly(original, cached)
    CacheBusterWorker.clear
    allow(CacheBusterWorker).to receive(:push_bulk).and_wrap_original do |method, urls, &block|
      expect(objects).to_not have_key(original) if urls.include?(original_url)
      expect(objects).to_not have_key(cached) if urls.include?(cached_url)
      method.call(urls, &block)
    end
    WxwMediaCacheCleanupWorker.drain

    expect(objects).to be_empty
    expect(CacheBusterWorker.jobs.pluck('args').flatten).to include(original_url, cached_url)
  end

  it 'invalidates only successfully deleted objects when a batch partially fails' do
    locations = [['cache', 'removed', 'https://cache.example/removed'], ['cache', 'retained', 'https://cache.example/retained']]
    client = described_class.bucket(:cache).client
    client.stub_responses(:delete_objects, errors: [{ key: 'retained', code: 'AccessDenied' }])
    allow(Rails.configuration.x.cache_buster).to receive(:enabled).and_return(true)

    ClimateControl.modify(CACHE_S3_BATCH_DELETE_RETRY: '1') do
      expect { described_class.delete_locations(locations) }.to raise_error(IOError)
      expect(CacheBusterWorker.jobs.pluck('args')).to contain_exactly(['https://cache.example/removed'])

      CacheBusterWorker.clear
      client.stub_responses(:delete_objects, 'AccessDenied')
      expect { described_class.delete_locations(locations) }.to raise_error(Aws::S3::Errors::AccessDenied)
      expect(CacheBusterWorker.jobs).to be_empty
    end
  end

  it 'removes old migration copies on replacement even when the current object is missing' do
    media = ClimateControl.modify(CACHE_S3_ENABLED: 'false') { upload }
    original = keys(media)
    described_class::Migration.call(media, :file, target: :cache)
    objects.delete(keys(media.reload))

    media.update!(file: attachment_fixture('attachment.jpg'))
    WxwMediaCacheCleanupWorker.drain
    expect(objects).to_not have_key(original)
    expect(objects).to have_key(keys(media.reload))
  end

  it 'deletes retained copies that cannot have their ACL revoked and invalidates their old URLs' do
    media = upload
    cached = keys(media)
    old_url = media.file.url(:original)
    described_class::Migration.call(media, :file, target: :main)
    allow(Rails.configuration.x.cache_buster).to receive(:enabled).and_return(true)

    ClimateControl.modify(CACHE_S3_PERMISSION: '') do
      UpdateMediaAttachmentsPermissionsService.new.call(MediaAttachment.where(id: media.id), :private)
    end

    expect(objects).to_not have_key(cached)
    expect(objects.fetch(keys(media.reload))[:acl]).to eq('private')
    expect(CacheBusterWorker.jobs.pluck('args').flatten).to include(old_url)
  end

  it 'revokes permissions on an incomplete migration target without a cache marker' do
    media = ClimateControl.modify(CACHE_S3_ENABLED: 'false') { upload }
    media.file.wxw_with_backend(:cache) { media.file.s3_interface.client.stub_responses(:get_object, body: 'corrupt') }
    expect { described_class::Migration.call(media, :file, target: :cache) }.to raise_error(IOError)

    UpdateMediaAttachmentsPermissionsService.new.call(MediaAttachment.where(id: media.id), :private)
    expect(objects.values.pluck(:acl).uniq).to eq(['private'])
    media.destroy!
    WxwMediaCacheCleanupWorker.drain
    expect(objects).to be_empty
  end

  it 'repairs permissions on retained copies without selecting them for removal' do
    media = ClimateControl.modify(CACHE_S3_ENABLED: 'false') { upload }
    original = keys(media)
    described_class::Migration.call(media, :file, target: :cache)
    account.update_column(:suspended_at, Time.current)

    command = Mastodon::CLI::Media.new([], { storage: 'main', days: 7, dry_run: false, remove_migrated: false, fix_permissions: true })
    command.remove_orphans
    expect(objects.fetch(original)[:acl]).to eq('private')
  end

  it 'does not contact cache storage for local attachments when its credentials are unavailable' do
    media = upload(remote: false)
    ClimateControl.modify(CACHE_AWS_ACCESS_KEY_ID: nil) do
      UpdateMediaAttachmentsPermissionsService.new.call(MediaAttachment.where(id: media.id), :private)
      AttachmentBatch.new(MediaAttachment, [media]).clear
    end
    expect(objects).to be_empty
  end

  it 'extends batch deletion timeouts to at least 120 seconds and restores them after success or failure' do
    client = described_class.bucket(:cache).client
    [5, 180].each do |timeout|
      client.config.http_read_timeout = timeout
      client.stub_responses(:delete_objects, lambda { |_context|
        expect(client.config.http_read_timeout).to eq([timeout, 120].max)
        {}
      })
      described_class.delete_objects(:cache, ['test-key'])
      expect(client.config.http_read_timeout).to eq(timeout)
    end
    client.config.http_read_timeout = 5
    client.stub_responses(:delete_objects, lambda { |_context|
      expect(client.config.http_read_timeout).to eq(120)
      'AccessDenied'
    })
    ClimateControl.modify(CACHE_S3_BATCH_DELETE_RETRY: '1') do
      expect { described_class.delete_objects(:cache, ['test-key']) }.to raise_error(Aws::S3::Errors::AccessDenied)
    end
    expect(client.config.http_read_timeout).to eq(5)
  end

  it 'treats configured cache media paths as directories in CSP sources' do
    {
      'cdn.example' => 'https://cdn.example',
      'cdn.example/cache' => 'https://cdn.example/cache/',
      'cdn.example/cache/' => 'https://cdn.example/cache/',
    }.each do |host, expected|
      ClimateControl.modify(CACHE_S3_ALIAS_HOST: host) do
        expect(ContentSecurityPolicy.new.media_hosts).to include(expected)
      end
    end
    ClimateControl.modify(CACHE_S3_ALIAS_HOST: nil, CACHE_S3_CLOUDFRONT_HOST: 'cdn.example/cache', CACHE_S3_PROTOCOL: 'http') do
      expect(ContentSecurityPolicy.new.media_hosts).to include('http://cdn.example/cache/')
    end
  end
end
