# frozen_string_literal: true

module Wxw::RemoteVisibilityControllerConcern
  private

  def wxw_authorize_status!(status)
    if request.format == :json || action_name == 'activity'
      wxw_authorize_remote_status!(status, account: current_account)
    else
      authorize status, :show?
    end
  end

  def wxw_authorize_remote_status!(status, account: signed_request_account)
    if status.wxw_remote_visibility.present?
      response.headers['Vary'] = (response.headers['Vary'].to_s.split(',').map(&:strip) | ['Signature']).join(', ')
    end

    raise Mastodon::NotPermittedError unless StatusPolicy.new(account, status, federation: true).show?
  end

  def wxw_federated_featured_items(items)
    items
      .select { |item| item.wxw_federatable? && (item.wxw_remote_visibility.nil? || item.wxw_remote_distributable?) }
      .map { |item| item.wxw_remote_distributable? ? item : ActivityPub::TagManager.instance.uri_for(item) }
  end

  def wxw_filter_outbox_statuses
    @statuses_for_pagination = @statuses
    @statuses = @statuses.select(&:wxw_federatable?)
  end
end
