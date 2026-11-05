# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Status source settings' do
  let(:user) { Fabricate(:user) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read:statuses') }
  let(:headers) { { 'Authorization' => "Bearer #{token.token}" } }

  %w(text/plain text/markdown text/html).each do |content_type|
    it "returns #{content_type} source and reads the status and settings in one SELECT" do
      status = Fabricate(:status, account: user.account, text: '**source** <b>HTML</b>', wxw_content_type: content_type)
      request_headers = headers
      queries = []
      subscriber = lambda do |_name, _started, _finished, _id, payload|
        sql = payload[:sql]
        queries << sql if sql.start_with?('SELECT') && sql.match?(/\b(?:FROM|JOIN) "(?:statuses|wxw_status_settings)"/)
      end

      Status.uncached do
        ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
          get "/api/v1/statuses/#{status.id}/source", headers: request_headers
        end
      end

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('text' => status.text, 'content_type' => content_type)
      expect(queries.size).to eq 1
      expect(queries.first).to include('LEFT OUTER JOIN "wxw_status_settings"')
    end
  end
end
