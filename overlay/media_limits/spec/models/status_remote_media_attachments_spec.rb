# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Status, 'media attachment limits' do
  context 'with remote attachments' do
    let(:account) { Fabricate(:remote_account) }
    let(:initial_count) { 17 }
    let(:attachments) do
      Array.new(17) do |index|
        { 'type' => 'Document', 'mediaType' => 'image/png', 'url' => "https://example.com/media/#{index}.png", 'name' => "Image #{index}" }
      end
    end
    let(:object) do
      {
        'id' => 'https://example.com/status',
        'type' => 'Note',
        'attributedTo' => account.uri,
        'to' => ['https://www.w3.org/ns/activitystreams#Public'],
        'content' => 'Remote attachments',
        'published' => 2.hours.ago.utc.iso8601,
        'attachment' => attachments.first(initial_count),
      }
    end
    let(:activity) do
      {
        '@context' => 'https://www.w3.org/ns/activitystreams',
        'id' => 'https://example.com/create',
        'type' => 'Create',
        'actor' => account.uri,
        'object' => object,
      }
    end
    let(:status) { ActivityPub::Activity::Create.new(activity, account).perform }

    before do
      stub_request(:get, %r{\Ahttps://example.com/media/\d+\.png\z})
        .to_return(body: attachment_fixture('emojo.png'), headers: { 'Content-Type' => 'image/png' })
    end

    it 'receives and serializes the first 16 attachments without downloading the seventeenth' do
      expect(status.media_attachments.size).to eq(16)
      expect(status.ordered_media_attachments.map(&:remote_url)).to eq(attachments.first(16).pluck('url'))

      json = serialized_record_json(status, REST::StatusSerializer, options: { scope: nil, scope_name: :current_user })
      expect(json.fetch('media_attachments').pluck('remote_url')).to eq(attachments.first(16).pluck('url'))
      expect(a_request(:get, attachments.last.fetch('url'))).to_not have_been_made
    end

    context 'when the remote post is edited' do
      let(:initial_count) { 4 }

      it 'accepts up to 16, preserves edit history, and handles reordering and removal' do
        update = object.merge('attachment' => attachments, 'updated' => 1.hour.ago.utc.iso8601)
        ActivityPub::ProcessStatusUpdateService.new.call(status, activity, update)

        expect(status.reload.ordered_media_attachments.map(&:remote_url)).to eq(attachments.first(16).pluck('url'))
        edit_json = serialized_record_json(status.edits.order(:id).last, REST::StatusEditSerializer, options: { scope: nil, scope_name: :current_user })
        expect(edit_json.fetch('media_attachments').pluck('description')).to eq(attachments.first(16).pluck('name'))
        expect(a_request(:get, attachments.last.fetch('url'))).to_not have_been_made

        remaining = attachments.first(4).reverse
        update = object.merge('attachment' => remaining, 'updated' => 30.minutes.ago.utc.iso8601)
        ActivityPub::ProcessStatusUpdateService.new.call(status, activity, update)

        expect(status.reload.ordered_media_attachments.map(&:remote_url)).to eq(remaining.pluck('url'))
        expect(status.edits.order(:id).map { |edit| edit.ordered_media_attachments.size }).to eq([4, 16, 4])
      end
    end
  end

  context 'with local attachments' do
    let(:account) { Fabricate(:account) }
    let(:media_ids) { Array.new(17) { Fabricate(:media_attachment, account: account).id.to_s } }

    it 'serializes up to 16 historical attachments, their order, and edit descriptions' do
      status = Fabricate(:status, account: account)
      media = Array.new(17) { Fabricate(:media_attachment, account: account, status: status) }
      ids = media.map(&:id).reverse
      status.reload.update!(ordered_media_attachment_ids: ids)

      json = serialized_record_json(status, REST::StatusSerializer, options: { scope: nil, scope_name: :current_user })
      expect(json.fetch('media_attachments').pluck('id')).to eq(ids.first(16).map(&:to_s))

      descriptions = ids.map { |id| "Historical #{id}" }
      edit = Fabricate(:status_edit, status: status, account: account, ordered_media_attachment_ids: ids, media_descriptions: descriptions)
      edit_json = serialized_record_json(edit, REST::StatusEditSerializer, options: { scope: nil, scope_name: :current_user })
      expect(edit_json.fetch('media_attachments').pluck('id')).to eq(ids.first(16).map(&:to_s))
      expect(edit_json.fetch('media_attachments').pluck('description')).to eq(descriptions.first(16))

      expect do
        UpdateStatusService.new.call(status, account.id, media_ids: ids)
      end.to raise_error(Mastodon::ValidationError, I18n.t('media_attachments.validations.too_many'))
      expect(status.reload.ordered_media_attachment_ids).to eq(ids)

      status.update!(ordered_media_attachment_ids: nil)
      json = serialized_record_json(status, REST::StatusSerializer, options: { scope: nil, scope_name: :current_user })
      expect(json.fetch('media_attachments').pluck('id')).to eq(media.first(16).map { |attachment| attachment.id.to_s })
      expect(status.media_attachments.size).to eq(17)
    end

    it 'allows 16 attachments when posting and editing' do
      status = PostStatusService.new.call(account, text: 'Local attachments', media_ids: media_ids.first(16))
      expect(status.ordered_media_attachments.map { |media| media.id.to_s }).to eq(media_ids.first(16))

      UpdateStatusService.new.call(status, account.id, media_ids: media_ids.first(16).reverse)
      expect(status.reload.ordered_media_attachments.map { |media| media.id.to_s }).to eq(media_ids.first(16).reverse)
    end

    it 'allows scheduling 16 attachments' do
      status = PostStatusService.new.call(account, text: 'Scheduled attachments', media_ids: media_ids.first(16), scheduled_at: 1.hour.from_now)
      expect(status.media_attachments.size).to eq(16)
    end

    it 'rejects 17 attachments when posting or scheduling' do
      expect do
        PostStatusService.new.call(account, text: 'Local attachments', media_ids: media_ids)
      end.to raise_error(Mastodon::ValidationError, I18n.t('media_attachments.validations.too_many'))

      expect do
        PostStatusService.new.call(account, text: 'Scheduled attachments', media_ids: media_ids, scheduled_at: 1.hour.from_now)
      end.to raise_error(Mastodon::ValidationError, I18n.t('media_attachments.validations.too_many'))
    end

    it 'rejects adding a seventeenth attachment when editing' do
      status = PostStatusService.new.call(account, text: 'Local attachments', media_ids: media_ids.first(16))

      expect do
        UpdateStatusService.new.call(status, account.id, media_ids: media_ids)
      end.to raise_error(Mastodon::ValidationError, I18n.t('media_attachments.validations.too_many'))

      expect(status.reload.ordered_media_attachments.size).to eq(16)
    end

    { audio: 'boop.ogg', video: 'attachment.webm' }.each do |type, fixture|
      it "allows one #{type} but rejects combining it with an image when posting or editing" do
        media = Fabricate(:media_attachment, account: account, file: attachment_fixture(fixture))
        media.update!(type: type)
        image = Fabricate(:media_attachment, account: account)
        mixed_ids = [media.id.to_s, image.id.to_s]

        expect do
          PostStatusService.new.call(account, text: 'Mixed attachments', media_ids: mixed_ids)
        end.to raise_error(Mastodon::ValidationError, I18n.t('media_attachments.validations.images_and_video'))

        status = PostStatusService.new.call(account, text: 'Single attachment', media_ids: [media.id.to_s])
        UpdateStatusService.new.call(status, account.id, text: 'Updated single attachment', media_ids: [media.id.to_s])
        expect(status.reload.text).to eq('Updated single attachment')

        expect do
          UpdateStatusService.new.call(status, account.id, media_ids: mixed_ids)
        end.to raise_error(Mastodon::ValidationError, I18n.t('media_attachments.validations.images_and_video'))
        expect(status.reload.ordered_media_attachment_ids).to eq([media.id])
      end
    end
  end
end
