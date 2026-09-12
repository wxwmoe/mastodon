# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WxwStatusSetting do
  let(:account) { Fabricate(:account) }
  let(:public_quote_policy) { InteractionPolicy::POLICY_FLAGS[:public] << 16 }

  %w(public unlisted private direct).product(%w(public unlisted private direct)).each do |visibility, remote_visibility|
    it "keeps #{visibility}/#{remote_visibility} at least as restrictive as native visibility" do
      status = account.statuses.create!(text: 'Remote audience', visibility: visibility, wxw_remote_visibility: remote_visibility)
      effective = [visibility, remote_visibility].max_by { |value| Status.visibilities.fetch(value) }
      override = effective unless effective == visibility

      expect(status.reload.visibility).to eq visibility
      expect(status.wxw_effective_remote_visibility).to eq effective
      expect(status.wxw_remote_visibility).to eq override
      expect(described_class.where(status_id: status.id).count).to eq(override.nil? ? 0 : 1)
    end
  end

  it 'keeps an old status on the native visibility path' do
    status = Fabricate(:status, account: account, visibility: :private)

    expect(status.wxw_remote_visibility).to be_nil
    expect(status.wxw_effective_remote_visibility).to eq 'private'
    expect(status.wxw_status_setting).to be_nil
  end

  it 'normalizes after both visibility attributes have been assigned' do
    status = account.statuses.create!(wxw_remote_visibility: :public, visibility: :private, text: 'Restricted audiences')

    expect(status.reload).to have_attributes(visibility: 'private', wxw_remote_visibility: nil)
  end

  it 'removes an override transactionally when it becomes equal' do
    status = Fabricate(:status, account: account, visibility: :public, wxw_remote_visibility: :private)
    status.wxw_remote_visibility = :public

    expect(described_class.where(status_id: status.id)).to exist

    status.save!

    expect(status.reload.wxw_remote_visibility).to be_nil
    expect(described_class.where(status_id: status.id)).to_not exist
  end

  it 'does not leave an override behind when the status fails validation' do
    status = account.statuses.build(text: '', visibility: :public, wxw_remote_visibility: :private)

    expect { status.save! }.to raise_error(ActiveRecord::RecordInvalid)
    expect(described_class.count).to eq 0
  end

  it 'preserves other settings when an override becomes equal to native visibility' do
    allow(described_class).to receive(:supported_setting_keys).and_return(described_class.supported_setting_keys + ['other'])
    status = Fabricate(:status, account: account, visibility: :public, wxw_remote_visibility: :private)
    status.wxw_write_setting(:other, 'stored')

    status.update!(visibility: :private)

    expect(status.reload.wxw_remote_visibility).to be_nil
    expect(status.wxw_status_setting.settings).to eq('other' => 'stored')
  end

  [nil, '2', 2.5, 4].each do |value|
    it "rejects the invalid stored remote visibility #{value.inspect} in the model and database" do
      status = Fabricate(:status, account: account)
      settings = { 'remote_visibility' => value }
      record = described_class.new(status: status, settings: settings)

      expect(record).to_not be_valid
      expect(record.errors[:settings]).to be_present
      expect { described_class.transaction(requires_new: true) { described_class.insert!({ status_id: status.id, settings: settings }) } }
        .to raise_error(ActiveRecord::StatementInvalid, /wxw_status_settings_remote_visibility/)
    end
  end

  it 'rejects a remote visibility setting on edit rows in the model and database' do
    status = Fabricate(:status, account: account)
    edit = Fabricate(:status_edit, status: status)
    settings = { 'remote_visibility' => 2 }
    record = described_class.new(status_edit: edit, settings: settings)

    expect(record).to_not be_valid
    expect(record.errors[:settings]).to be_present
    expect { described_class.transaction(requires_new: true) { described_class.insert!({ status_edit_id: edit.id, settings: settings }) } }
      .to raise_error(ActiveRecord::StatementInvalid, /wxw_status_settings_edit_keys/)
  end

  %w(private direct).each do |remote_visibility|
    it "normalizes quote policy to native nobody for remote #{remote_visibility} on create and update" do
      status = account.statuses.create!(text: 'Quote audience', visibility: :public, wxw_remote_visibility: remote_visibility, quote_approval_policy: public_quote_policy)

      expect(status.reload.quote_approval_policy).to eq 0

      status.update!(quote_approval_policy: public_quote_policy)

      expect(status.reload.quote_approval_policy).to eq 0
    end
  end

  it 'rejects unsupported and remote-account overrides' do
    invalid = account.statuses.build(text: 'Invalid', visibility: :public, wxw_remote_visibility: :none)
    remote = Fabricate.build(:status, account: Fabricate(:account, domain: 'remote.example'), visibility: :public, wxw_remote_visibility: :private)

    expect(invalid).to_not be_valid
    expect(remote).to_not be_valid
  end

  it 'cascades hard status deletion to the sparse row' do
    status = Fabricate(:status, account: account, wxw_remote_visibility: :private)
    Status.where(id: status.id).delete_all

    expect(described_class.where(status_id: status.id)).to_not exist
  end

  it 'queries effective remote visibility and preloads its association' do
    overridden = Fabricate(:status, account: account, visibility: :public, wxw_remote_visibility: :private)
    ordinary = Fabricate(:status, account: account, visibility: :private)
    public_status = Fabricate(:status, account: account, visibility: :public)

    expect(Status.wxw_remote_visibility_in(:private)).to contain_exactly(overridden, ordinary)
    expect(Status.wxw_remote_visibility_in(:public)).to contain_exactly(public_status)
    expect(Status.with_includes.find(overridden.id).association(:wxw_status_setting)).to be_loaded
  end

  it 'restricts legacy wider rows on reads and removes them when saving' do
    status = Fabricate(:status, account: account, visibility: :private)
    described_class.insert!({ status_id: status.id, settings: { 'remote_visibility' => 0 } })

    expect(status.reload.wxw_remote_visibility).to be_nil
    expect(status.wxw_effective_remote_visibility).to eq 'private'
    expect(Status.wxw_remote_visibility_in(:public)).to_not include(status)
    expect(Status.wxw_remote_visibility_in(:private)).to include(status)

    status.update!(text: 'Safe legacy edit')
    expect(described_class.where(status_id: status.id)).to_not exist
  end

  it 'ignores stray local overrides on remote statuses in both reads and scopes' do
    remote = Fabricate(:status, account: Fabricate(:account, domain: 'remote.example'), visibility: :public)
    described_class.insert!({ status_id: remote.id, settings: { 'remote_visibility' => 3 } })

    expect(remote.reload.wxw_effective_remote_visibility).to eq 'public'
    expect(Status.wxw_remote_visibility_in(:public)).to include(remote)
    expect(Status.wxw_remote_visibility_in(:direct)).to_not include(remote)
  end

  it 'clears a user default override when the two defaults become equal' do
    user = Fabricate(:user)
    user.update!(settings_attributes: { default_privacy: 'public', wxw_default_remote_privacy: 'private' })
    expect(user.reload.settings['wxw_default_remote_privacy']).to eq 'private'

    user.update!(settings_attributes: { default_privacy: 'private' })

    expect(user.reload.settings.as_json).to_not have_key(:wxw_default_remote_privacy)
  end
end
