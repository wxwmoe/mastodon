# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WxwStatusSetting do
  let(:account) { Fabricate(:account) }

  before do
    allow(described_class).to receive(:supported_setting_keys).and_return(%w(example other))
  end

  it 'stores settings in one sparse row without changing the source' do
    status = Fabricate(:status, account: account, text: 'Original source')
    expect(status.wxw_status_setting).to be_nil

    status.wxw_write_setting(:example, 'stored')
    status.wxw_write_setting(:other, 2)
    status.save!

    expect(status.reload.text).to eq 'Original source'
    expect(status.wxw_status_setting.settings).to eq('example' => 'stored', 'other' => 2)
    expect(described_class.where(status_id: status.id).count).to eq 1
  end

  it 'clears each key independently and deletes the row only when it becomes empty' do
    status = Fabricate(:status, account: account)
    status.wxw_write_setting(:example, 'stored')
    status.wxw_write_setting(:other, 2)
    status.save!
    status.wxw_write_setting(:other, nil)
    status.save!
    expect(status.reload.wxw_status_setting.settings).to eq('example' => 'stored')

    status.wxw_write_setting(:other, 2)
    status.wxw_write_setting(:example, nil)
    status.save!
    expect(status.reload.wxw_status_setting.settings).to eq('other' => 2)

    status.wxw_write_setting(:other, nil)
    expect(status.wxw_setting(:other)).to be_nil
    expect(described_class.where(status_id: status.id)).to exist
    status.save!
    expect(status.reload.wxw_status_setting).to be_nil
  end

  %i(status status_edit).each do |owner_type|
    %w(example other).each do |enabled_key|
      it "updates and clears #{enabled_key} on #{owner_type} while preserving disabled settings" do
        status = Fabricate(:status, account: account)
        owner = owner_type == :status ? status : Fabricate(:status_edit, status: status)
        owner.wxw_write_setting(:example, 'stored')
        owner.wxw_write_setting(:other, 2)
        owner.save!
        retained = owner.wxw_status_setting.settings.except(enabled_key)
        allow(described_class).to receive(:supported_setting_keys).and_return([enabled_key])

        owner.wxw_write_setting(enabled_key, 'updated')
        owner.save!
        expect(owner.reload.wxw_status_setting.settings).to eq(retained.merge(enabled_key => 'updated'))

        owner.wxw_write_setting(enabled_key, nil)
        owner.save!
        expect(owner.reload.wxw_status_setting.settings).to eq retained
      end
    end
  end

  it 'rejects additions, changes and removal of unsupported settings on an existing row' do
    status = Fabricate(:status, account: account)
    record = described_class.create!(status: status, settings: { 'example' => 'stored', 'other' => 2 })
    allow(described_class).to receive(:supported_setting_keys).and_return(%w(example))

    [
      { 'unknown' => true },
      { 'unknown' => nil },
      { 'other' => 3 },
      { 'other' => nil },
    ].each do |changes|
      record.reload.settings.merge!(changes)
      expect(record).to_not be_valid
      expect(record.errors[:settings]).to be_present
    end

    record.reload.settings.delete('other')
    expect(record).to_not be_valid
    expect(record.errors[:settings]).to be_present
  end

  it 'can restore a setting after clearing it and failing parent validation' do
    status = Fabricate(:status, account: account)
    status.wxw_write_setting(:example, 'stored')
    status.save!
    status.text = ''
    status.wxw_write_setting(:example, nil)
    expect(status).to_not be_valid

    status.wxw_write_setting(:example, 'restored')
    status.update!(text: 'Restored')
    expect(status.reload.wxw_setting(:example)).to eq 'restored'
    expect(described_class.where(status_id: status.id).count).to eq 1
  end

  it 'can add settings after deleting the final key on the same status instance' do
    status = Fabricate(:status, account: account)
    status.wxw_write_setting(:example, 'stored')
    status.save!
    status.wxw_write_setting(:example, nil)
    status.save!
    expect(described_class.where(status_id: status.id)).to_not exist

    status.wxw_write_setting(:example, 'restored')
    status.save!
    expect(status.reload.wxw_setting(:example)).to eq 'restored'
    expect(described_class.where(status_id: status.id).count).to eq 1
  end

  it 'does not build a row when a new draft has no remaining settings' do
    status = account.statuses.build(text: 'Draft')
    status.wxw_write_setting(:example, nil)
    expect(status.wxw_status_setting).to be_nil

    status.wxw_write_setting(:example, 'stored')
    status.wxw_write_setting(:example, nil)
    status.save!
    expect(status.reload.wxw_status_setting).to be_nil
  end

  it 'does not leave settings behind when the parent fails validation' do
    status = account.statuses.build(text: '')
    status.wxw_write_setting(:example, 'stored')

    expect { status.save! }.to raise_error(ActiveRecord::RecordInvalid)
    expect(described_class.count).to eq 0
  end

  [nil, [], {}, { 'unknown' => true }].each do |settings|
    it "rejects invalid settings #{settings.inspect}" do
      record = described_class.new(status: Fabricate(:status, account: account), settings: settings)

      expect(record).to_not be_valid
      expect(record.errors[:settings]).to be_present
    end
  end

  [nil, 'stored'].each do |value|
    it "reads the status and #{value.inspect} setting with one SELECT" do
      original = Fabricate(:status, account: account)
      original.wxw_write_setting(:example, value)
      original.save!
      queries = []
      subscriber = ->(_name, _started, _finished, _id, payload) { queries << payload[:sql] if payload[:sql].start_with?('SELECT') }

      Status.uncached do
        ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
          status = Status.eager_load(:wxw_status_setting).find(original.id)
          expect(status.wxw_setting(:example)).to eq value
          expect(status.wxw_setting('example')).to eq value
        end
      end

      expect(queries.size).to eq 1
      expect(queries.first).to include('LEFT OUTER JOIN "wxw_status_settings"')
    end
  end

  it 'requires exactly one local owner' do
    status = Fabricate(:status, account: account)
    edit = Fabricate(:status_edit, status: status)
    remote = Fabricate(:status, account: Fabricate(:account, domain: 'remote.example'))
    settings = { 'example' => 'stored' }

    expect(described_class.new(settings: settings)).to_not be_valid
    expect(described_class.new(status: status, status_edit: edit, settings: settings)).to_not be_valid
    expect(described_class.new(status: remote, settings: settings)).to_not be_valid
    expect(described_class.new(status: status, settings: settings)).to be_valid
    expect(described_class.new(status_edit: edit, settings: settings)).to be_valid
  end

  it 'cascades hard deletion of either owner' do
    status = Fabricate(:status, account: account)
    edit = Fabricate(:status_edit, status: status)
    [status, edit].each do |owner|
      owner.wxw_write_setting(:example, 'stored')
      owner.save!
    end

    StatusEdit.where(id: edit.id).delete_all
    expect(described_class.where(status_edit_id: edit.id)).to_not exist
    expect(described_class.where(status_id: status.id)).to exist

    Status.where(id: status.id).delete_all
    expect(described_class.where(status_id: status.id)).to_not exist
  end

  it 'enforces owner, uniqueness, and JSON constraints on direct database inserts' do
    status = Fabricate(:status, account: account)
    edit = Fabricate(:status_edit, status: status)
    settings = { 'example' => 'stored' }
    described_class.create!(status: status, settings: settings)
    described_class.create!(status_edit: edit, settings: settings)
    ordinary = Fabricate(:status, account: account)
    ordinary_edit = Fabricate(:status_edit, status: ordinary)
    invalid = [
      [{ settings: settings }, 'wxw_status_settings_owner'],
      [{ status_id: ordinary.id, status_edit_id: ordinary_edit.id, settings: settings }, 'wxw_status_settings_owner'],
      [{ status_id: status.id, settings: settings }, 'index_wxw_status_settings_on_status_id'],
      [{ status_edit_id: edit.id, settings: settings }, 'index_wxw_status_settings_on_status_edit_id'],
      [{ status_id: ordinary.id, settings: {} }, 'wxw_status_settings_object'],
      [{ status_id: ordinary.id, settings: [] }, 'wxw_status_settings_object'],
    ]

    aggregate_failures do
      invalid.each do |attributes, constraint|
        expect { described_class.transaction(requires_new: true) { described_class.insert!(attributes) } }
          .to raise_error(ActiveRecord::StatementInvalid, /#{constraint}/)
      end
    end
  end
end
