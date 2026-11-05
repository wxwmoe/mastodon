# frozen_string_literal: true

module Wxw::RemoteVisibilityPolicy
  def initialize(current_account, record, federation: false)
    super(current_account, record)
    @wxw_federation = federation || current_account&.remote?
  end

  def show?
    (!@wxw_federation || record.wxw_federatable?) && super
  end

  private

  def requires_mention?
    @wxw_federation ? %w(direct limited).include?(record.wxw_effective_remote_visibility) : super
  end

  def private?
    @wxw_federation ? record.wxw_effective_remote_visibility == 'private' : super
  end
end
