# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::WxwStatusesHelper do
  let(:status) { instance_double(Status) }

  it 'reuses the compose labels for the three standard policies' do
    [[%w(public), 'public'], [%w(followers), 'followers'], [[], 'nobody'], [%w(disabled), 'nobody']].each do |automatic, policy|
      allow(status).to receive(:quote_policy_as_keys).with(:automatic).and_return(automatic)
      allow(status).to receive(:quote_policy_as_keys).with(:manual).and_return([])

      expect(helper.wxw_admin_quote_policy(status)).to eq(I18n.t("statuses.quote_policies.#{policy}"))
    end
  end

  it 'does not mislabel remote policies that cannot be represented by a compose option' do
    [[%w(following), []], [%w(unsupported_policy), []], [[], %w(public)]].each do |automatic, manual|
      allow(status).to receive(:quote_policy_as_keys).with(:automatic).and_return(automatic)
      allow(status).to receive(:quote_policy_as_keys).with(:manual).and_return(manual)

      expect(helper.wxw_admin_quote_policy(status)).to eq('—')
    end
  end
end
