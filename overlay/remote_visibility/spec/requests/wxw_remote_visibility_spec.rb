# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Other server visibility' do
  let(:account) { Fabricate(:account) }
  let(:remote_account) { Fabricate(:account, domain: 'example.com') }
  let(:status) { Fabricate(:status, account: account, visibility: :public, wxw_remote_visibility: :private) }

  it 'keeps the public local page while denying anonymous ActivityPub fetches' do
    get short_account_status_path(account_username: account.username, id: status.id, format: :html)
    expect(response).to have_http_status(:success)

    get short_account_status_path(account_username: account.username, id: status.id, format: :json)
    expect(response).to have_http_status(:not_found)

    get activity_account_status_path(account.username, status)
    expect(response).to have_http_status(:not_found)
  end

  it 'allows signed followers without publicly caching their response' do
    remote_account.follow!(account)

    get short_account_status_path(account_username: account.username, id: status.id, format: :json), headers: nil, sign_with: remote_account

    expect(response).to have_http_status(:success)
    expect(response.headers['Vary']).to eq 'Accept, Accept-Language, Cookie, Signature'
    expect(response.headers['Cache-Control']).to eq 'private, no-store'
    expect(response.parsed_body[:to]).to eq [ActivityPub::TagManager.instance.followers_uri_for(account)]
    expect(response.parsed_body[:cc]).to_not include(ActivityPub::TagManager::COLLECTIONS[:public])
  end

  it 'restricts anonymous ActivityPub fetches of legacy wider overrides' do
    legacy_status = Fabricate(:status, account: account, visibility: :private)
    WxwStatusSetting.insert!({ status_id: legacy_status.id, settings: { 'remote_visibility' => 0 } })

    get short_account_status_path(account_username: account.username, id: legacy_status.id, format: :json)
    expect(response).to have_http_status(:not_found)

    get short_account_status_path(account_username: account.username, id: legacy_status.id, format: :html)
    expect(response).to have_http_status(:not_found)

    get account_outbox_path(account_username: account.username, page: true)
    expect(response.parsed_body[:orderedItems]).to be_empty
  end

  it 'denies anonymous access to the restricted status collections' do
    %w(replies likes shares).each do |collection|
      get "/users/#{account.username}/statuses/#{status.id}/#{collection}"
      expect(response).to have_http_status(:not_found)
    end
  end

  it 'omits remote-restricted posts from anonymous outbox and featured collections' do
    Fabricate(:status_pin, account: account, status: status)

    get account_outbox_path(account_username: account.username, page: true)
    expect(response).to have_http_status(:success)
    expect(response.parsed_body[:orderedItems]).to be_empty

    get account_actor_collection_path(id: 'featured', account_username: account.username)
    expect(response).to have_http_status(:success)
    expect(response.parsed_body[:orderedItems]).to be_empty
  end

  it 'omits remote-restricted replies and context items' do
    parent = Fabricate(:status, account: account, visibility: :public)
    reply = Fabricate(:status, account: account, thread: parent, visibility: :public, wxw_remote_visibility: :direct)

    get account_status_replies_path(account_username: account.username, status_id: parent.id)
    expect(response).to have_http_status(:success)
    expect(response.parsed_body[:first][:items]).to be_empty

    get context_path(reply.conversation)
    expect(response).to have_http_status(:success)
    expect(response.parsed_body[:first][:items]).to_not include(ActivityPub::TagManager.instance.uri_for(reply))
  end

  it 'keeps local-only boosts out of ActivityPub without losing an outbox cursor' do
    boost = Fabricate(:status, account: Fabricate(:account), reblog: status, visibility: :public)
    stub_const('ActivityPub::OutboxesController::LIMIT', 1)

    get activity_account_status_path(boost.account.username, boost)
    expect(response).to have_http_status(:not_found)

    get account_outbox_path(account_username: boost.account.username, page: true)
    expect(response).to have_http_status(:success)
    expect(response.parsed_body[:orderedItems]).to be_empty
    expect(response.parsed_body[:next]).to include("max_id=#{boost.id}")
  end
end
