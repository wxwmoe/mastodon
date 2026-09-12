# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Posting format preferences' do
  let(:user) { Fabricate(:user) }

  before { sign_in user }

  it 'offers plain text, Markdown, and HTML with plain text selected initially' do
    get settings_preferences_posting_defaults_path

    expect(response).to have_http_status(200)
    options = Nokogiri::HTML(response.body).css('#user_settings_attributes_wxw_default_post_format option')
    expect(options.map { |option| option['value'] }).to eq %w(plain markdown html)
    expect(options.find { |option| option['selected'] }['value']).to eq 'plain'
    expect(options.first.text).to eq I18n.t('wxw_post_format.formats.plain')

    fields = Nokogiri::HTML(response.body).css('select, input').map { |field| field['id'] }
    format_position = fields.index('user_settings_attributes_wxw_default_post_format')
    expect(format_position).to be > fields.index('user_settings_attributes_default_language')
    expect(format_position).to be < fields.index('user_settings_attributes_default_sensitive')

    presenter = InitialStatePresenter.new(current_account: user.account)
    expect(InitialStateSerializer.new(presenter).compose[:default_format]).to eq 'plain'
  end

  it 'persists all three settings and restores the matching editor default' do
    %w(plain markdown html).each do |format|
      put settings_preferences_posting_defaults_path, params: {
        user: { settings_attributes: { wxw_default_post_format: format } },
      }

      expect(response).to redirect_to(settings_preferences_posting_defaults_path)
      expect(user.reload.settings['wxw_default_post_format']).to eq format
      presenter = InitialStatePresenter.new(current_account: user.account)
      expect(InitialStateSerializer.new(presenter).compose[:default_format]).to eq format

      get settings_preferences_posting_defaults_path

      expect(response).to have_http_status(200)
      selected = Nokogiri::HTML(response.body).at_css('#user_settings_attributes_wxw_default_post_format option[selected]')
      expect(selected['value']).to eq format
    end
  end
end
