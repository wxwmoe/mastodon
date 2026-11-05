# frozen_string_literal: true

module Wxw::AccountStatusesFilterConcern
  module FederatedVisibilityScopes
    def distributable_visibility
      wxw_remote_visibility_in(:public, :unlisted)
    end

    def list_eligible_visibility
      wxw_remote_visibility_in(:public, :unlisted, :private)
    end

    def private_visibility
      wxw_remote_visibility_in(:private)
    end
  end

  def initialize(account, current_account, params = {}, federation: false)
    @wxw_federation = federation
    super(account, current_account, params)
  end

  private

  def wxw_statuses_scope
    return account.statuses unless @wxw_federation

    account.statuses.left_outer_joins(:wxw_status_setting).extending(FederatedVisibilityScopes)
  end
end
