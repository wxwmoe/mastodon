# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Remote visibility in /api/v1/statuses' do
  include_context 'with API authentication'

  let(:scopes) { 'read:statuses write:statuses' }

  before do
    user.update!(settings_attributes: { default_privacy: 'public', wxw_default_remote_privacy: 'private' })
  end

  %w(public unlisted private direct).each do |visibility|
    it "follows #{visibility.inspect} visibility when the request omits the remote field" do
      post '/api/v1/statuses', headers: headers, params: { status: 'Default remote audience', visibility: visibility }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:visibility]).to eq visibility
      expect(response.parsed_body).to_not have_key(:wxw_remote_visibility)
      expect(Status.find(response.parsed_body[:id]).wxw_status_setting).to be_nil
    end
  end

  [%w(unlisted public), %w(private public), %w(private unlisted), %w(direct public), %w(direct unlisted), %w(direct private)].each do |visibility, remote_visibility|
    it "safely follows #{visibility} when an API client requests wider #{remote_visibility}" do
      post '/api/v1/statuses', headers: headers, params: { status: 'Restricted API audience', visibility: visibility, wxw_remote_visibility: remote_visibility }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:visibility]).to eq visibility
      expect(response.parsed_body).to_not have_key(:wxw_remote_visibility)
      expect(Status.find(response.parsed_body[:id]).wxw_status_setting).to be_nil
    end
  end

  it 'normalizes scheduled parameters before storage and preserves the local visibility when publishing' do
    post '/api/v1/statuses', headers: headers, params: { status: 'Restricted scheduled audience', visibility: 'private', wxw_remote_visibility: 'public', scheduled_at: 1.hour.from_now.iso8601 }, as: :json

    expect(response).to have_http_status(200)
    scheduled_status = user.account.scheduled_statuses.find(response.parsed_body[:id])
    expect(scheduled_status.params).to include('visibility' => 'private', 'wxw_remote_visibility' => nil)

    PublishScheduledStatusWorker.new.perform(scheduled_status.id)
    expect(user.account.statuses.find_by!(text: 'Restricted scheduled audience')).to have_attributes(visibility: 'private', wxw_remote_visibility: nil)
  end

  it 'restricts old scheduled overrides and legacy user defaults on publication' do
    user.update!(settings_attributes: { default_privacy: 'private' })
    user.settings['wxw_default_remote_privacy'] = 'public'
    user.update_column(:settings, user.settings)
    scheduled_status = user.account.scheduled_statuses.create!(scheduled_at: 1.hour.from_now, params: { text: 'Legacy scheduled override', visibility: 'private', wxw_remote_visibility: 'public' })

    PublishScheduledStatusWorker.new.perform(scheduled_status.id)
    expect(user.account.statuses.find_by!(text: 'Legacy scheduled override')).to have_attributes(visibility: 'private', wxw_remote_visibility: nil)

    post '/api/v1/statuses', headers: headers, params: { status: 'Legacy default override' }, as: :json
    expect(response).to have_http_status(200)
    expect(response.parsed_body[:visibility]).to eq 'private'
    expect(response.parsed_body).to_not have_key(:wxw_remote_visibility)
  end

  it 'normalizes a public remote request after a silenced account is restricted to unlisted' do
    user.account.silence!

    post '/api/v1/statuses', headers: headers, params: { status: 'Silenced audience', visibility: 'public', wxw_remote_visibility: 'public' }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body[:visibility]).to eq 'unlisted'
    expect(response.parsed_body).to_not have_key(:wxw_remote_visibility)
  end

  it 'uses the account remote default when neither visibility is submitted' do
    post '/api/v1/statuses', headers: headers, params: { status: 'Account default audiences' }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to include(visibility: 'public', wxw_remote_visibility: 'private')
    expect(Status.find(response.parsed_body[:id]).wxw_status_setting.settings).to eq('remote_visibility' => 2)
  end

  it 'follows the native account default when neither visibility nor a remote default is present' do
    user.update!(settings_attributes: { default_privacy: 'private' })

    post '/api/v1/statuses', headers: headers, params: { status: 'Native default audience' }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body[:visibility]).to eq 'private'
    expect(response.parsed_body).to_not have_key(:wxw_remote_visibility)
    expect(Status.find(response.parsed_body[:id]).wxw_status_setting).to be_nil
  end

  it 'honors an explicit remote selection from the web composer, including mentions only' do
    post '/api/v1/statuses', headers: headers, params: { status: 'Explicit remote audience', visibility: 'public', wxw_remote_visibility: 'direct' }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to include(visibility: 'public', wxw_remote_visibility: 'direct')
    expect(Status.find(response.parsed_body[:id]).wxw_status_setting.settings).to eq('remote_visibility' => 3)
  end

  [nil, 'public'].each do |remote_visibility|
    it "suppresses the account default for an explicit #{remote_visibility.inspect}" do
      post '/api/v1/statuses', headers: headers, params: { status: 'Ordinary audience', wxw_remote_visibility: remote_visibility }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:visibility]).to eq 'public'
      expect(response.parsed_body).to_not have_key(:wxw_remote_visibility)
      expect(Status.find(response.parsed_body[:id]).wxw_status_setting).to be_nil
    end
  end

  it 'rejects invalid remote values without creating a status or override' do
    expect do
      post '/api/v1/statuses', headers: headers, params: { status: 'Invalid audience', wxw_remote_visibility: 'none' }
    end.to not_change(Status, :count).and not_change(WxwStatusSetting, :count)

    expect(response).to have_http_status(422)
  end

  it 'keeps both visibility values unchanged during native text editing and returns the override for redrafting' do
    status = Fabricate(:status, account: user.account, visibility: :public, wxw_remote_visibility: :private)

    put "/api/v1/statuses/#{status.id}", headers: headers, params: { status: 'Edited text', visibility: 'direct', wxw_remote_visibility: 'public' }

    expect(response).to have_http_status(200)
    expect(status.reload).to have_attributes(text: 'Edited text', visibility: 'public', wxw_remote_visibility: 'private')

    delete "/api/v1/statuses/#{status.id}", headers: headers

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to include(visibility: 'public', wxw_remote_visibility: 'private')
  end

  [nil, 'private'].each do |remote_visibility|
    it "returns the #{remote_visibility.inspect} remote override together with the editing source" do
      status = Fabricate(:status, account: user.account, visibility: :public, wxw_remote_visibility: remote_visibility)

      get "/api/v1/statuses/#{status.id}/source", headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to include(text: status.text, wxw_remote_visibility: remote_visibility)
    end
  end

  it 'snapshots an omitted remote override across scheduled publication and changed defaults' do
    post '/api/v1/statuses', headers: headers, params: { status: 'Scheduled audience', visibility: 'public', scheduled_at: 1.hour.from_now.iso8601 }, as: :json

    expect(response).to have_http_status(200)
    scheduled_status = user.account.scheduled_statuses.find(response.parsed_body[:id])
    expect(scheduled_status.params).to include('visibility' => 'public', 'wxw_remote_visibility' => nil)
    expect(WxwStatusSetting.count).to eq 0

    user.update!(settings_attributes: { default_privacy: 'private', wxw_default_remote_privacy: 'unlisted' })
    PublishScheduledStatusWorker.new.perform(scheduled_status.id)
    published_status = user.account.statuses.find_by!(text: 'Scheduled audience')

    expect(published_status.visibility).to eq 'public'
    expect(published_status.wxw_remote_visibility).to be_nil
  end

  it 'keeps statuses scheduled before this feature on their original audience' do
    scheduled_status = user.account.scheduled_statuses.create!(scheduled_at: 1.hour.from_now, params: { text: 'Old scheduled audience', visibility: 'private' })
    user.update!(settings_attributes: { default_privacy: 'private', wxw_default_remote_privacy: 'public' })

    PublishScheduledStatusWorker.new.perform(scheduled_status.id)
    published_status = user.account.statuses.find_by!(text: 'Old scheduled audience')

    expect(published_status.visibility).to eq 'private'
    expect(published_status.wxw_remote_visibility).to be_nil
  end
end
