# frozen_string_literal: true

class Wxw::PostFormat
  CONTENT_TYPES = { 'plain' => 'text/plain', 'markdown' => 'text/markdown', 'html' => 'text/html' }.freeze

  class Renderer < Redcarpet::Render::HTML
    def header(text, _level)
      "<p><strong>#{text}</strong></p>\n"
    end

    def hrule
      "<p>---</p>\n"
    end
  end

  class << self
    def render(text, content_type)
      return '' if text.blank?

      Sanitize.fragment(raw_html(text, content_type), Sanitize::Config::MASTODON_STRICT).strip
    rescue ArgumentError
      # Nokogiri rejects excessively deep HTML; display that input literally.
      ERB::Util.h(text)
    end

    def raw_html(text, content_type)
      content_type == 'text/markdown' ? markdown(text) : text
    end

    private

    def markdown(text)
      prefix = "wxw#{SecureRandom.hex}x"
      prefix = "wxw#{SecureRandom.hex}x" while text.include?(prefix)
      placeholders = %w(_ * ~).to_h { |character| [character, "#{prefix}#{character.ord}x"] }
      # Preserve existing escapes for Markdown to consume.
      source = text.gsub(FetchLinkCardService::URL_PATTERN) do
        before, url = Regexp.last_match.captures
        before + url.gsub(/\\.|[_*~]/) { |token| placeholders.fetch(token, token) }
      end
      source.gsub!(/(_{1,2})(@#{Account::USERNAME_RE}(?:@[[:word:]]+(?:[.-]+[[:word:]]+)*)?)\1/) do
        delimiter, mention = Regexp.last_match.captures
        delimiter + mention.gsub(/_(?!_*\z)/, placeholders['_']) + delimiter
      end
      # Keep native identifiers intact inside prose, code, and raw HTML.
      source.gsub!(Regexp.union(Account::MENTION_RE, CustomEmoji::SCAN_RE, /[#＃](?:#{Tag::HASHTAG_NAME_PAT})/)) do |entity|
        entity.gsub('_', placeholders['_'])
      end

      renderer = Renderer.new(hard_wrap: true, no_images: true)
      html = Redcarpet::Markdown.new(renderer, fenced_code_blocks: true, strikethrough: true, space_after_headers: true).render(source)
      html.gsub!(Regexp.union(placeholders.values), placeholders.invert)
      html
    end
  end
end
