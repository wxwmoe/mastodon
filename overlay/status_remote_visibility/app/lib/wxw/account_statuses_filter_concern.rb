# frozen_string_literal: true

module Wxw::AccountStatusesFilterConcern
  def initialize(account, current_account, params = {}, federation: false)
    @wxw_federation = federation
    super(account, current_account, params)
  end

  private

  def wxw_statuses_scope
    @wxw_federation ? account.statuses.left_outer_joins(:wxw_status_setting) : account.statuses
  end

  def wxw_visibility_scope(scope, visibilities)
    @wxw_federation ? scope.wxw_remote_visibility_in(*visibilities) : scope.where(visibility: visibilities)
  end
end
