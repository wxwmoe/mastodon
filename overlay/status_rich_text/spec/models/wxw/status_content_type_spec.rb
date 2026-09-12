# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WxwStatusSetting do
  let(:account) { Fabricate(:account) }

  it 'stores the source format without storing the plain default' do
    plain = Fabricate(:status, account: account)
    rich = Fabricate(:status, account: account, text: '**source**', wxw_content_type: 'text/markdown')

    expect(plain.reload.wxw_content_type).to eq 'text/plain'
    expect(plain.wxw_status_setting).to be_nil
    expect(rich.reload.text).to eq '**source**'
    expect(rich.wxw_status_setting.settings).to eq('text_type' => 'markdown')
    expect(described_class.where(status_id: rich.id).count).to eq 1
  end

  it 'tracks resetting a new rich-text draft to plain text without saving a row' do
    status = account.statuses.build(text: 'Draft', wxw_content_type: 'text/markdown')
    expect(status.wxw_content_type_changed?).to be true

    status.wxw_content_type = 'text/plain'
    expect(status.wxw_content_type_changed?).to be false
    status.save!
    expect(status.reload.wxw_status_setting).to be_nil
  end

  it 'detects format changes independently of other settings' do
    allow(described_class).to receive(:supported_setting_keys).and_return(described_class.supported_setting_keys + ['other'])
    status = Fabricate(:status, account: account, wxw_content_type: 'text/markdown')
    expect(status.wxw_content_type_changed?).to be false

    status.wxw_write_setting(:other, 'stored')
    expect(status.wxw_content_type_changed?).to be false

    status.wxw_content_type = 'text/html'
    expect(status.wxw_content_type_changed?).to be true
    status.save!
    expect(status.wxw_content_type_changed?).to be false

    status.wxw_content_type = 'text/plain'
    expect(status.wxw_content_type_changed?).to be true
    status.save!
    expect(status.reload.wxw_status_setting.settings).to eq('other' => 'stored')
  end

  [nil, 'plain', 'text/markdown', 'text/html', 2].each do |value|
    it "rejects the invalid stored format #{value.inspect} in the model and database" do
      status = Fabricate(:status, account: account)
      settings = { 'text_type' => value }
      record = described_class.new(status: status, settings: settings)

      expect(record).to_not be_valid
      expect(record.errors[:settings]).to be_present
      expect { described_class.transaction(requires_new: true) { described_class.insert!({ status_id: status.id, settings: settings }) } }
        .to raise_error(ActiveRecord::StatementInvalid, /wxw_status_settings_text_type/)
    end
  end

  it 'rejects an unsupported content type at assignment' do
    status = Fabricate(:status, account: account)

    expect { status.wxw_content_type = 'text/unknown' }.to raise_error(ArgumentError, 'Invalid content type')
  end

  it 'snapshots the original format independently of later edits' do
    status = Fabricate(:status, account: account, text: '**original**', wxw_content_type: 'text/markdown')
    snapshot = status.build_snapshot(rate_limit: false)
    snapshot.save!
    status.update!(text: 'Updated', wxw_content_type: 'text/plain')

    expect(snapshot.reload.text).to eq '**original**'
    expect(snapshot.wxw_content_type).to eq 'text/markdown'
    expect(snapshot.wxw_status_setting).to have_attributes(status_id: nil, status_edit_id: snapshot.id, settings: { 'text_type' => 'markdown' })
    expect(status.reload.wxw_status_setting).to be_nil
    expect(status.build_snapshot(rate_limit: false).wxw_status_setting).to be_nil
  end

  it 'uses HTML for remote content without storing a local setting' do
    status = Fabricate(:status, account: Fabricate(:account, domain: 'remote.example'))

    expect(status.wxw_content_type).to eq 'text/html'
    expect(status.wxw_content_type_changed?).to be false
    expect(status.wxw_status_setting).to be_nil
  end
end
