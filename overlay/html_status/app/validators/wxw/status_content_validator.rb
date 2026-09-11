# frozen_string_literal: true

class Wxw::StatusContentValidator < ActiveModel::Validator
  def validate(status)
    return unless status.local? && status.text.present?
    return if status.with_media? || status.reblog? || status.with_quote?

    formatter = Wxw::HtmlFormatter.for_status(status)
    status.errors.add(:text, :blank) if formatter.rich? && formatter.plain_text.blank?
  end
end
