# frozen_string_literal: true

module Wxw::RichTextNoteSerializer
  extend ActiveSupport::Concern

  included do
    context_extensions :misskey_content
    attribute :wxw_misskey_content, key: :_misskey_content, if: :wxw_misskey_content?
  end

  def wxw_federation_content
    html = wxw_formatted_content
    return html unless object.local? && %w(text/html text/markdown).include?(object.wxw_content_type)

    Wxw::FederationHtml.format(html)
  end

  def wxw_misskey_content
    return unless markdown_source?
    return @wxw_misskey_content if defined?(@wxw_misskey_content)

    @wxw_misskey_content = Wxw::MfmFormatter.new(wxw_formatted_content, mentions: object.active_mentions.to_a, emojis: object.emojis).to_s
  end

  def wxw_misskey_content?
    wxw_misskey_content.present?
  end

  private

  def wxw_formatted_content
    @wxw_formatted_content ||= status_content_format(object)
  end
end
