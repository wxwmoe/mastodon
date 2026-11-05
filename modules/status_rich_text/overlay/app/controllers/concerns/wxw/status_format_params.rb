# frozen_string_literal: true

module Wxw::StatusFormatParams
  private

  def status_params
    @wxw_status_params ||= super.tap do |options|
      next unless action_name == 'create' || params.key?(:content_type)

      content_type = if params.key?(:content_type)
                       params.permit(:content_type)[:content_type]
                     else
                       Wxw::PostFormat::CONTENT_TYPES[current_user.settings['wxw_default_post_format']]
                     end
      raise Mastodon::ValidationError, 'Invalid post format' unless Wxw::PostFormat::CONTENT_TYPES.value?(content_type)

      options[:content_type] = content_type
    end
  end
end
