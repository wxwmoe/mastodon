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

  it 'includes followers-only overrides for a remote follower' do
    remote_account.follow!(account)

    expect(described_class.new(account, remote_account, federation: true).results).to contain_exactly(original_public, remote_unlisted, remote_private)
  end

  it 'includes a private mention, unless direct messages are excluded' do
    Fabricate(:mention, status: remote_direct, account: remote_account)

    expect(described_class.new(account, remote_account, federation: true).results).to contain_exactly(original_public, remote_unlisted, remote_direct)
    expect(described_class.new(account, remote_account, { exclude_direct: true }, federation: true).results).to contain_exactly(original_public, remote_unlisted)
  end
end
