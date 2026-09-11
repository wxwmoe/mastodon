# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EmailSubscriptionMailer do
  it 'uses rendered text for the notification subject and plain-text title excerpts' do
    subscription = Fabricate(:email_subscription, account: Fabricate(:account, display_name: 'Alice'), confirmed_at: Time.now.utc)
    status = Fabricate(:status, account: subscription.account, text: '<p><strong>Bold</strong> &amp; plain</p>', wxw_content_type: 'text/html')
    mail = described_class.with(subscription: subscription).notification([status])

    expect(mail.subject).to eq I18n.t('email_subscription_mailer.notification.subject.singular', name: subscription.account.display_name, excerpt: 'Bold & plain')
    expect(mail.text_part.decoded.lines.first.chomp).to eq I18n.t('email_subscription_mailer.notification.title.singular', name: 'Alice', excerpt: 'Bold & plain')
  end
end
