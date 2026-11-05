# frozen_string_literal: true

class Wxw::PostFormat
  CONTENT_TYPES = { 'plain' => 'text/plain', 'markdown' => 'text/markdown', 'html' => 'text/html' }.freeze

  MARKDOWN_OPTIONS = {
    parse: { smart: false },
    render: { hardbreaks: false, unsafe: true, github_pre_lang: false, escaped_char_spans: false, width: 0 },
    extension: {
      strikethrough: true,
      highlight: true,
      tagfilter: false,
      table: false,
      autolink: false,
      tasklist: false,
      shortcodes: false,
      header_ids: nil,
      footnotes: false,
      superscript: false,
      subscript: false,
    },
  }.freeze
  MARKDOWN_PLUGINS = { syntax_highlighter: nil }.freeze

  class << self
    def render(text, content_type)
      return '' if text.blank?

      normalize_whitespace(Sanitize.fragment(raw_html(text, content_type), Sanitize::Config::MASTODON_STRICT))
    rescue ArgumentError
      # Nokogiri rejects excessively deep HTML; display that input literally.
      ERB::Util.h(text)
    end

    def raw_html(text, content_type)
      content_type == 'text/markdown' ? markdown(text) : text
    end

    def normalize_whitespace(html)
      fragment = Nokogiri::HTML5.fragment(html)
      previous = nil
      reset = lambda do
        if previous&.text?
          previous.content = previous.content.delete_suffix(' ')
          previous.remove if previous.content.empty?
        end
        previous = nil
      end

      # Mastodon's pre-wrap must not turn HTML formatting whitespace into breaks.
      visit = lambda do |parent|
        parent.children.each do |node|
          if node.text?
            content = node.content.gsub(/[\t\n\f\r ]+/, ' ')
            content.delete_prefix!(' ') if previous.nil? || (previous.text? && previous.content.end_with?(' '))
            node.content = content
            if content.empty?
              node.remove
            else
              previous = node
            end
          elsif node.element?
            block = %w(p div br hr blockquote pre ul ol li dl dt dd details summary header footer hgroup h1 h2 h3 h4 h5 h6).include?(node.name)
            reset.call if block
            if %w(pre code).include?(node.name)
              previous = node unless node.content.empty?
            else
              visit.call(node)
            end
            reset.call if block
          end
        end
      end

      visit.call(fragment)
      reset.call
      fragment.inner_html(preserve_newline: true)
    end

    private

    def markdown(text)
      prefix = "wxw#{SecureRandom.hex}x"
      prefix = "wxw#{SecureRandom.hex}x" while text.include?(prefix)
      placeholders = %w(_ * ~ =).to_h { |character| [character, "#{prefix}#{character.ord}x"] }
      # Preserve existing escapes for Markdown to consume.
      source = text.gsub(FetchLinkCardService::URL_PATTERN) do
        before, url = Regexp.last_match.captures
        before + url.gsub(/\\.|[_*~]|=(?!=*\z)/) { |token| placeholders.fetch(token, token) }
      end
      source.gsub!(/(_{1,2})(@#{Account::USERNAME_RE}(?:@[[:word:]]+(?:[.-]+[[:word:]]+)*)?)\1/) do
        delimiter, mention = Regexp.last_match.captures
        delimiter + mention.gsub(/_(?!_*\z)/, placeholders['_']) + delimiter
      end
      # Keep native identifiers intact inside prose, code, and raw HTML.
      source.gsub!(Regexp.union(Account::MENTION_RE, CustomEmoji::SCAN_RE, /[#＃](?:#{Tag::HASHTAG_NAME_PAT})/)) do |entity|
        entity.gsub('_', placeholders['_'])
      end

      document = Commonmarker.parse(source, options: MARKDOWN_OPTIONS)
      document.walk do |node|
        next unless node.type == :image

        # CommonMark source positions omit multiline image titles; serialize the
        # image itself so its label, destination, and title remain visible.
        literal = node.to_commonmark(options: MARKDOWN_OPTIONS, plugins: MARKDOWN_PLUGINS).delete_suffix("\n")
        node.replace(Commonmarker::Node.new(:text, content: literal))
      end
      html = document.to_html(options: MARKDOWN_OPTIONS, plugins: MARKDOWN_PLUGINS)
      html.gsub!(Regexp.union(placeholders.values), placeholders.invert)
      html
    end
  end
end
