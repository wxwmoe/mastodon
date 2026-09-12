# frozen_string_literal: true

class Wxw::HtmlFormatter < TextFormatter
  BLOCKS = %w(p div br blockquote pre ul ol li h1 h2 h3 h4 h5 h6).freeze
  PROSE_ELEMENTS = (Sanitize::Config::MASTODON_STRICT[:elements] - %w(a code pre) + %w(div h1 h2 h3 h4 h5 h6)).freeze

  def self.for_status(status, options = {})
    new(status.text, options.merge(content_type: status.wxw_content_type))
  end

  def self.format(text, local, options = {})
    local ? new(text, options).to_s : HtmlAwareFormatter.new(text, false, options).to_s
  end

  def self.status_plain_text(status)
    return for_status(status).plain_text if status.local?

    PlainTextFormatter.new(status.text, status.local?).to_s
  end

  def rich?
    %w(text/markdown text/html).include?(options[:content_type])
  end

  def to_s
    return super unless rich?

    fragment = document.dup
    prose_entities(fragment).each do |node, entities|
      entities.each do |entity|
        next unless entity[:screen_name]

        username, domain = entity[:screen_name].split('@')
        domain = TagManager.instance.normalize_domain(domain) unless TagManager.instance.local_domain?(domain)
        entity[:screen_name] = [username, domain].compact.join('@')
      end
      formatter = TextFormatter.new(node.text, options.merge(multiline: false, quoted_status: nil))
      formatter.instance_variable_set(:@entities, entities)
      node.replace(formatter.to_s)
    end

    # Use the unmodified Mastodon allowlist, including attributes and link protocols.
    html = Sanitize.fragment(fragment.inner_html(preserve_newline: true), Sanitize::Config::MASTODON_STRICT).strip
    Sanitize.fragment(add_quote_fallback(html), Sanitize::Config::MASTODON_STRICT).html_safe # rubocop:disable Rails/OutputSafety
  end

  def entity_text
    return text unless rich?

    prose_entities(document).flat_map { |node, entities| entities.map { |entity| node.text[entity[:indices].first...entity[:indices].last] } }.join(' ')
  end

  def rewrite_mentions
    return text.gsub(Account::MENTION_RE) { |match| yield match, Regexp.last_match(1) } unless rich?

    fragment = document.dup
    mentions = prose_entities(fragment) do |context|
      context.to_enum(:scan, Account::MENTION_RE).map do
        match = Regexp.last_match
        { screen_name: match[1], indices: [match.char_begin(0), match.char_end(0)] }
      end
    end

    replacements = Hash.new { |hash, key| hash[key] = {} }
    mentions.each do |node, entities|
      entities.each do |entity|
        range = entity[:indices].first...entity[:indices].last
        original = node.text
        match = original[range]
        replacement = yield(match, entity[:screen_name])
        next if replacement == match

        rewritten = original.dup
        rewritten[range] = replacement
        node.content = rewritten
        replacements[match][Digest::SHA256.hexdigest(fragment.inner_html(preserve_newline: true))] = replacement
        node.content = original
      end
    end

    return text if replacements.empty?

    rewrite_mention_source(replacements)
  end

  def plain_text
    return PlainTextFormatter.new(text, true).to_s unless rich?

    PlainTextFormatter.new(rendered_html, false).to_s
  end

  def antispam_text
    return text unless rich?

    [CGI.unescapeHTML(rendered_html), plain_text, *urls].join("\n")
  end

  def urls
    return text.scan(FetchLinkCardService::URL_PATTERN).map { |array| Addressable::URI.parse(array[1]).normalize } unless rich?

    entities = prose_entities(document)
    links = document.xpath('.//a | .//text()').flat_map do |node|
      next [] if node.ancestors.any? { |parent| parent.element? && !PROSE_ELEMENTS.include?(parent.name) }

      node.element? ? [node['href']].compact : entities.fetch(node, []).filter_map { |entity| entity[:url] }
    end

    links.filter_map do |link|
      uri = Addressable::URI.parse(link).normalize
      uri if %w(http https).include?(uri.scheme) && URI.parse(uri.to_s).host.present?
    rescue Addressable::URI::InvalidURIError, IDN::Idna::IdnaError, URI::InvalidURIError
      nil
    end
  end

  private

  def rewrite_mention_source(replacements)
    edits = []
    replacements.each do |match, expected|
      text.to_enum(:scan, Regexp.new(Regexp.escape(match))).each do
        range = Regexp.last_match.char_begin(0)...Regexp.last_match.char_end(0)
        expected.values.uniq.each do |replacement|
          candidate = text.dup
          candidate[range] = replacement
          rendered = self.class.new(candidate, options).send(:document).inner_html(preserve_newline: true)
          next unless expected[Digest::SHA256.hexdigest(rendered)] == replacement

          edits << [range, replacement]
          break
        end
      end
    end

    edits.sort_by { |range, _| -range.begin }.each_with_object(text.dup) { |(range, replacement), source| source[range] = replacement }
  end

  def prose_entities(fragment)
    context = +''
    nodes = []
    append_context(fragment, context, nodes)
    entities = block_given? ? yield(context) : Extractor.extract_entities_with_indices(context, extract_url_without_protocol: false)

    entities.sort_by { |entity| entity[:indices].first }.each_with_object({}) do |entity, result|
      first, last = entity[:indices]
      node, offset, ending = nodes.bsearch { |_, _, finish| finish > first }
      # Inline markup is not a word boundary. Keep split entities literal, and
      # retain link/code text as context without extracting entities from it.
      next unless node && first >= offset && last <= ending
      next unless literal_ranges.include?(first...last)

      (result[node] ||= []) << entity.merge(indices: [first - offset, last - offset])
    end
  end

  def append_context(node, context, nodes, excluded = false)
    return if Sanitize::Config::DEFAULT[:remove_contents].include?(node.name)

    if node.text?
      offset = context.length
      context << node.text
      nodes << [node, offset, context.length] unless excluded
    else
      block = BLOCKS.include?(node.name)
      context << "\n" if block
      excluded ||= node.element? && !PROSE_ELEMENTS.include?(node.name)
      node.children.each { |child| append_context(child, context, nodes, excluded) }
      context << "\n" if block
    end
  end

  def literal_ranges
    return @literal_ranges if defined?(@literal_ranges)

    blocked = []
    text.to_enum(:scan, /&#(?:x[0-9a-f]+|\d+);?|&[a-z][a-z0-9]*;?|\\[[:punct:]]|\p{Default_Ignorable_Code_Point}|<!--[\s\S]*?-->/i).each do |token|
      match = Regexp.last_match
      next if token.start_with?('&') && Nokogiri::HTML5.fragment(token).text == token

      blocked << (match.char_begin(0)...match.char_end(0))
    end
    candidates = Extractor.extract_entities_with_indices(text, extract_url_without_protocol: false)
    if options[:content_type] == 'text/markdown'
      context = +''
      nodes = []
      append_context(document, context, nodes)
      mentions = Extractor.extract_entities_with_indices(context, extract_url_without_protocol: false).filter_map do |entity|
        first, last = entity[:indices]
        node, offset, ending = nodes.bsearch { |_, _, finish| finish > first }
        context[first...last] if entity[:screen_name] && node && first >= offset && last <= ending
      end.uniq
      unless mentions.empty?
        pattern = Regexp.new("(?<=_)(?:#{Regexp.union(mentions.sort_by { |token| -token.length }).source})(?=_)", Regexp::IGNORECASE)
        text.to_enum(:scan, pattern).each do
          match = Regexp.last_match
          candidates << { indices: [match.char_begin(0), match.char_end(0)] }
        end
      end
    end
    # The rendered context supplies boundaries; markup may wrap a whole hashtag.
    text.to_enum(:scan, /[#＃](?:#{Tag::HASHTAG_NAME_PAT})/).each do
      match = Regexp.last_match
      candidates << { indices: [match.char_begin(0), match.char_end(0)] }
    end
    candidates = Extractor.remove_overlapping_entities(candidates).reject do |entity|
      first, last = entity[:indices]
      range = blocked.bsearch { |item| item.end >= first }
      range && range.begin <= last
    end
    @literal_ranges = Set.new
    return @literal_ranges if candidates.empty?

    # Shared markers keep Markdown reference labels matching their definitions.
    prefix = "wxw#{SecureRandom.hex}x"
    prefix = "wxw#{SecureRandom.hex}x" while text.include?(prefix)
    tokens = candidates.map { |entity| text[entity[:indices].first...entity[:indices].last] }.uniq
    markers = tokens.map(&:downcase).uniq.each_with_index.to_h { |token, index| [token, "#{prefix}#{index}x"] }
    source = text.dup
    candidates.sort_by { |entity| -entity[:indices].last }.each do |entity|
      first, last = entity[:indices]
      source.insert(last, markers.fetch(text[first...last].downcase))
    end

    fragment = parse_document(source)
    lookup = tokens.group_by { |token| markers.fetch(token.downcase) }
    pattern = Regexp.union(lookup.keys)
    ranges = {}
    fragment.traverse do |node|
      if node.text? || node.cdata?
        restored = +''
        ranges[node] = []
        cursor = 0
        original = node.text
        original.to_enum(:scan, pattern).each do
          match = Regexp.last_match
          restored << original[cursor...match.char_begin(0)]
          lookup.fetch(match[0]).each do |token|
            ranges[node] << ((restored.length - token.length)...restored.length) if restored.end_with?(token)
          end
          cursor = match.char_end(0)
        end
        node.content = restored << original[cursor..]
      elsif node.comment?
        node.content = node.content.gsub(pattern, '')
      elsif node.element?
        node.attribute_nodes.each { |attribute| attribute.value = attribute.value.gsub(pattern, '') }
      end
    end

    # Recognition must never change how Markdown or HTML parses the source.
    return @literal_ranges unless fragment.inner_html(preserve_newline: true) == document.inner_html(preserve_newline: true)

    nodes = []
    append_context(fragment, +'', nodes)
    nodes.each do |node, offset, _ending|
      ranges.fetch(node, []).each { |range| @literal_ranges << ((offset + range.begin)...(offset + range.end)) }
    end
    @literal_ranges
  end

  def rendered_html
    @rendered_html ||= Wxw::PostFormat.render(text, options[:content_type])
  end

  def document
    @document ||= parse_document(text)
  end

  def parse_document(source)
    Nokogiri::HTML5.fragment(Wxw::PostFormat.raw_html(source, options[:content_type]))
  rescue ArgumentError
    # Nokogiri rejects excessively deep HTML; keep that input as literal text.
    Nokogiri::HTML5.fragment(ERB::Util.h(source))
  end
end
