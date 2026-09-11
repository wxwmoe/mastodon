# frozen_string_literal: true

module Wxw::StatusSourceController
  private

  def set_status
    @status = Status.eager_load(:wxw_status_setting).find(params[:status_id])
    authorize @status, :show?
  rescue ActiveRecord::RecordNotFound, Mastodon::NotPermittedError
    not_found
  end
end
