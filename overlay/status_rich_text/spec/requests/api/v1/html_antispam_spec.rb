# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'HTML status antispam' do
  include_context 'with API authentication', oauth_scopes: 'write:statuses'

  let!(:recipient) { Fabricate(:user, account: Fabricate(:account, username: 'recipient')).account }

  before { redis.sadd('antispam:all_time_spammy_texts', 'banned.example') }

  it 'checks decoded link targets and visible text before immediate or scheduled posts are saved' do
    [nil, 1.hour.from_now.iso8601].each do |scheduled_at|
      [
        'https://banned.example/',
        '<a href="https://bann&#101;d.example/">link</a>',
        '<code><a href="https://bann&#101;d.example/">link</a></code>',
        '<p>bann<strong>ed</strong>.example</p>',
      ].each do |source|
        expect do
          post '/api/v1/statuses', headers: headers, params: { status: "@recipient #{source}", content_type: 'text/html', scheduled_at: scheduled_at }
        end.to not_change(Status, :count).and not_change(ScheduledStatus, :count)

        expect(response).to have_http_status(200)
      end
    end
  end

  it 'preserves ordinary HTML posts and the existing follower exemption' do
    post '/api/v1/statuses', headers: headers, params: { status: '@recipient <strong>safe</strong>', content_type: 'text/html' }

    expect(response).to have_http_status(200)
    expect(user.account.statuses.find(response.parsed_body[:id]).text).to include '<strong>safe</strong>'

    recipient.follow!(user.account)
    post '/api/v1/statuses', headers: headers, params: { status: '@recipient <a href="https://bann&#101;d.example/">link</a>', content_type: 'text/html' }

    expect(response).to have_http_status(200)
    expect(user.account.statuses.find(response.parsed_body[:id]).text).to include 'href="https://bann&#101;d.example/"'
    expect(response.parsed_body[:content]).to include 'href="https://banned.example/"'
  end

  it 'checks an entire banned URL with query parameters inside explicit code links' do
    redis.del('antispam:all_time_spammy_texts')
    redis.sadd('antispam:all_time_spammy_texts', 'https://example.org/?a=1&b=2')

    expect do
      post '/api/v1/statuses', headers: headers, params: { status: '@recipient <code><a href="https://example.org/?a=1&amp;b=2">link</a></code>', content_type: 'text/html' }
    end.to_not change(Status, :count)

    expect(response).to have_http_status(200)
  end
end
