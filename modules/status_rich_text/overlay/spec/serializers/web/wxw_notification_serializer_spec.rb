# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Web::NotificationSerializer do
  subject(:body) { described_class.new(notification).body }

  let(:account) { Fabricate.build(:account) }
  let(:status) { Fabricate.build(:status, account: account, text: source, wxw_content_type: 'text/markdown') }
  let(:notification) { Fabricate.build(:notification, type: :status, activity: status, status: status, from_account: account) }
  let(:source) { "Please read [documentation](https://example.org/#{'long' * 50}) before replying" }

  it 'renders Markdown link labels before truncating the notification' do
    expect(body).to eq 'Please read documentation before replying'
  end

  it 'extracts readable HTML text' do
    status.text = '<p><strong>Bold</strong> &amp; <em>italic</em></p>'
    status.wxw_content_type = 'text/html'

    expect(body).to eq 'Bold & italic'
  end

  it 'keeps literal markup and entities after extracting rich text' do
    status.text = '<p>&lt;b&gt;literal&lt;/b&gt; &amp;amp;</p>'
    status.wxw_content_type = 'text/html'

    expect(body).to eq '<b>literal</b> &amp;'
  end

  it 'retains the notification length limit for rich text' do
    status.text = "**#{'a' * 200}**"

    expect(body).to eq "#{'a' * 137}..."
  end

  it 'keeps the existing content-warning priority and formatting' do
    status.spoiler_text = '<b>Warning</b> &amp; details'

    expect(body).to eq 'Warning & details'
  end

  it 'keeps native plain-text notification formatting' do
    status.text = '<b>literal</b> &amp; **plain**'
    status.wxw_content_type = 'text/plain'

    expect(body).to eq 'literal & **plain**'
  end

  it 'keeps native remote notification formatting' do
    account.domain = 'remote.example'
    status.text = '<p><b>Remote</b> &amp; text</p>'

    expect(body).to eq 'Remote & text'
  end

  it 'uses the account profile when there is no target status' do
    notification.type = :follow
    notification.status = nil
    account.note = '<p>Profile &amp; text</p>'

    expect(body).to eq 'Profile & text'
  end
end
