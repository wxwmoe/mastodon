# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Posting defaults with remote visibility' do
  let(:user) { Fabricate(:user) }

  before { sign_in user }

  it 'offers the native options and descriptions plus private mentions for remote defaults' do
    get settings_preferences_posting_defaults_path

    expect(response).to have_http_status(200)
    document = Nokogiri::HTML(response.body)
    options = document.css('#user_settings_attributes_wxw_default_remote_privacy option')
    expect(options.map { |option| option['value'] }).to eq %w(public unlisted private direct)
    expect(options.first(3).map(&:text)).to eq document.css('#user_settings_attributes_default_privacy option').map(&:text)
    expect(options.find { |option| option['selected'] }['value']).to eq user.setting_default_privacy
  end

  it 'offers only followers or mentions for private local defaults and safely normalizes wider submitted values' do
    user.update!(settings_attributes: { default_privacy: 'private' })
    get settings_preferences_posting_defaults_path

    document = Nokogiri::HTML(response.body)
    expect(document.css('#user_settings_attributes_wxw_default_remote_privacy option:not([disabled])').map { |option| option['value'] }).to eq %w(private direct)

    put settings_preferences_posting_defaults_path, params: {
      user: { settings_attributes: { default_privacy: 'private', wxw_default_remote_privacy: 'public' } },
    }
    expect(user.reload.wxw_default_remote_privacy).to be_nil

    put settings_preferences_posting_defaults_path, params: {
      user: { settings_attributes: { default_privacy: 'private', wxw_default_remote_privacy: 'direct', default_quote_policy: 'public' } },
    }
    expect(user.reload.wxw_default_remote_privacy).to eq 'direct'
    expect(user.setting_default_quote_policy).to eq 'nobody'
  end

  it 'saves only differing defaults and limits quotes through the native setting' do
    put settings_preferences_posting_defaults_path, params: {
      user: { settings_attributes: { default_privacy: 'public', wxw_default_remote_privacy: 'private', default_quote_policy: 'public' } },
    }

    expect(response).to redirect_to(settings_preferences_posting_defaults_path)
    expect(user.reload.settings['wxw_default_remote_privacy']).to eq 'private'
    expect(user.setting_default_quote_policy).to eq 'nobody'

    put settings_preferences_posting_defaults_path, params: {
      user: { settings_attributes: { default_privacy: 'private', wxw_default_remote_privacy: 'private', default_quote_policy: 'public' } },
    }

    expect(user.reload.settings.as_json).not_to have_key('wxw_default_remote_privacy')
    expect(user.setting_default_quote_policy).to eq 'nobody'
  end

  it 'updates remote defaults without rewriting existing posts' do
    status = Fabricate(:status, account: user.account, visibility: :public)
    put settings_preferences_posting_defaults_path, params: {
      user: { settings_attributes: { default_privacy: 'public', wxw_default_remote_privacy: 'unlisted', default_quote_policy: 'public' } },
    }

    expect(user.reload.settings['wxw_default_remote_privacy']).to eq 'unlisted'
    expect(user.setting_default_quote_policy).to eq 'public'
    expect(status.reload.wxw_remote_visibility).to be_nil
  end
end
