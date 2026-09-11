# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'statuses/show.html.haml' do
  let(:account) { Fabricate(:account, username: 'alice', display_name: 'Alice') }
  let(:status) { Fabricate(:status, account: account, text: '<p><strong>Bold</strong> &amp; <em>plain</em></p><p>Next</p>', wxw_content_type: 'text/html') }

  before do
    view.extend(Module.new do
      def site_title = 'example site'
      def site_hostname = 'example.com'
      def current_account = nil
      def single_user_mode? = false
    end)

    assign(:instance_presenter, InstancePresenter.new)
    assign(:status, status)
    assign(:account, account)
  end

  it 'renders decoded plain text in the page title and sharing descriptions' do
    render

    expect(CGI.unescapeHTML(view.content_for(:page_title))).to eq I18n.t('statuses.title', name: 'Alice', quote: "Bold & plain\nNext")
    metadata = Nokogiri::HTML5.fragment(view.content_for(:header_tags))
    expect(metadata.at_css('meta[property="og:description"]')['content']).to eq "Bold & plain\nNext"
    expect(metadata.at_css('meta[name="description"]')['content']).to eq "Bold & plain\nNext"
  end

  it 'keeps content warnings as the title and hides the body from sharing descriptions' do
    status.update!(spoiler_text: 'Spoilers')

    render

    expect(CGI.unescapeHTML(view.content_for(:page_title))).to eq I18n.t('statuses.title', name: 'Alice', quote: 'Spoilers')
    metadata = Nokogiri::HTML5.fragment(view.content_for(:header_tags))
    expect(metadata.at_css('meta[property="og:description"]')['content']).to eq I18n.t('statuses.content_warning', warning: 'Spoilers')
  end
end
