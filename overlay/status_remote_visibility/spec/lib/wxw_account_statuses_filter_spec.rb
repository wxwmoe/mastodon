# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccountStatusesFilter do
  let(:account) { Fabricate(:account) }
  let(:remote_account) { Fabricate(:account, domain: 'example.com') }
  let!(:original_public) { Fabricate(:status, account: account, visibility: :public) }
  let!(:remote_unlisted) { Fabricate(:status, account: account, visibility: :public, wxw_remote_visibility: :unlisted) }
  let!(:remote_private) { Fabricate(:status, account: account, visibility: :public, wxw_remote_visibility: :private) }
  let!(:remote_direct) { Fabricate(:status, account: account, visibility: :public, wxw_remote_visibility: :direct) }

  it 'preserves local queries and filters anonymous federation queries by the override' do
    expect(described_class.new(account, nil).results).to contain_exactly(original_public, remote_unlisted, remote_private, remote_direct)
    expect(described_class.new(account, nil, federation: true).results).to contain_exactly(original_public, remote_unlisted)
  end

  it 'keeps followers-only overrides when a remote follower excludes mentioned direct posts' do
    remote_account.follow!(account)
    Fabricate(:mention, status: remote_direct, account: remote_account)

    expect(described_class.new(account, remote_account, federation: true).results).to contain_exactly(original_public, remote_unlisted, remote_private, remote_direct)
    expect(described_class.new(account, remote_account, { exclude_direct: true }, federation: true).results).to contain_exactly(original_public, remote_unlisted, remote_private)
  end

  it 'keeps a mentioned followers-only override when a remote non-follower excludes direct messages' do
    mentioned = Fabricate(:status, account: account, visibility: :public, wxw_remote_visibility: :private)
    Fabricate(:mention, status: mentioned, account: remote_account)
    Fabricate(:mention, status: remote_direct, account: remote_account)
    Fabricate(:mention, status: remote_private)

    expect(described_class.new(account, remote_account, federation: true).results).to contain_exactly(original_public, remote_unlisted, mentioned, remote_direct)
    expect(described_class.new(account, remote_account, { exclude_direct: true }, federation: true).results).to contain_exactly(original_public, remote_unlisted, mentioned)
  end

  it 'uses local visibility when a local non-follower excludes direct messages' do
    reader = Fabricate(:account)
    mentioned = Fabricate(:status, account: account, visibility: :private)
    direct = Fabricate(:status, account: account, visibility: :direct)
    Fabricate(:status, account: account, visibility: :private)
    Fabricate(:mention, status: mentioned, account: reader)
    Fabricate(:mention, status: direct, account: reader)

    expect(described_class.new(account, reader, { exclude_direct: true }).results).to contain_exactly(original_public, remote_unlisted, remote_private, remote_direct, mentioned)
  end
end
