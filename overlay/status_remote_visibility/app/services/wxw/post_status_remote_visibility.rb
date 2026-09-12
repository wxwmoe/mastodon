# frozen_string_literal: true

module Wxw::PostStatusRemoteVisibility
  private

  def wxw_preprocess_remote_visibility!
    @wxw_remote_visibility = @options[:wxw_remote_visibility]
    if !@options.key?(:wxw_remote_visibility) && @options[:visibility].nil?
      @wxw_remote_visibility = @account.user&.wxw_default_remote_privacy
    end

    @wxw_remote_visibility = @wxw_remote_visibility.to_s unless @wxw_remote_visibility.nil?
    @wxw_remote_visibility = :unlisted if @wxw_remote_visibility&.to_sym == :public && @account.silenced?
    @wxw_remote_visibility = WxwStatusSetting.normalize_remote_visibility(@visibility, @wxw_remote_visibility)
  end

  def wxw_snapshot_remote_visibility!(options_hash)
    options_hash[:visibility] = @visibility
    options_hash[:wxw_remote_visibility] = @wxw_remote_visibility
  end
end
