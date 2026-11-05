# frozen_string_literal: true

module Admin::WxwStatusesHelper
  def wxw_admin_quote_policy(status)
    automatic = status.quote_policy_as_keys(:automatic)
    manual = status.quote_policy_as_keys(:manual)
    policy = if automatic.include?('public')
               'public'
             elsif (automatic - %w(followers disabled)).any? || (manual - ['disabled']).any?
               return '—'
             elsif automatic.include?('followers')
               'followers'
             else
               'nobody'
             end

    t("statuses.quote_policies.#{policy}")
  end
end
