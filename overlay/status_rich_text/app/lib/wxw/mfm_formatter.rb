# frozen_string_literal: true

class Wxw::MfmFormatter
  BREAK = "\0"
  LANGUAGE = /\Alanguage-([a-z0-9][a-z0-9_+.#-]{0,63})\z/i
  MFM_ELEMENTS = %w(h1 h2 h3 h4 h5 h6 details summary ul ol).freeze

  def initialize(html, mentions: [], emojis: [])
    @html = html
    @mentions = mentions
    @emojis = emojis.map(&:shortcode).to_set
  end

  def to_s
    @needs_mfm = false
    document = Nokogiri::HTML5.fragment(@html)
    content = finish(children(document))
    content if @needs_mfm
  rescue ArgumentError
    # Keep the HTML representation if the document exceeds the parser's limits.
    nil
  end

  private

  def children(node, depth: 0, inline: false, list_depth: 0)
    node.children.map { |child| render(child, depth: depth, inline: inline, list_depth: list_depth) }.join
  end

  def render(node, depth:, inline:, list_depth:)
    return text(node.text) if node.text?
    return '' unless node.element?

    @needs_mfm ||= MFM_ELEMENTS.include?(node.name)
    options = { depth: depth, inline: inline, list_depth: list_depth }
    case node.name
    when 'br' then "\n"
    when 'hr' then block('────────')
    when 'wbr' then ''
    when 'pre' then code_block(node, inline: inline)
    when 'code', 'kbd' then inline_code(node.text)
    when 'a' then link(node, **options)
    when 'details' then details(node, **options)
    when 'ul', 'ol' then list(node, **options)
    when 'blockquote'
      quote_nodes = node.children.reject { |child| child.comment? || (child.text? && child.text.strip.empty?) }
      quote_nodes = quote_nodes.first.children if quote_nodes.one? && quote_nodes.first.name == 'p'
      @needs_mfm ||= quote_nodes.any? { |child| child.element? && child.name != 'br' }
      content = finish(children(node, **options.merge(depth: depth + 1)))
      prefix = inline || depth >= 16 ? literal('> ') : '> '
      block(content.lines.map { |line| "#{prefix}#{line}" }.join)
    when 'ruby' then ruby(node, **options)
    when 'rt' then " (#{children(node, **options)})"
    when 'rp' then ''
    else
      formatted_element(node, **options)
    end
  end

  def formatted_element(node, depth:, inline:, list_depth:)
    template = case node.name
               when 'b', 'strong' then "<b>#{BREAK}</b>"
               when 'i', 'em' then "<i>#{BREAK}</i>"
               when 's', 'strike', 'del' then "<s>#{BREAK}</s>"
               when 'small' then "<small>#{BREAK}</small>"
               when 'h1', 'h2' then "$[x2 <b>#{BREAK}</b>]"
               when 'h3', 'h4' then "<b>#{BREAK}</b>"
               when 'h5', 'h6' then "<small><b>#{BREAK}</b></small>"
               else BREAK
               end
    base_template = template
    style = node['style']
    style = "color: black; background-color: yellow; #{style}" if node.name == 'mark'
    template = Wxw::MfmStyles.wrap(template, style)
    nesting = template.scan(/\$\[|<(?:b|i|s|small)>/).size
    # Leave room for literal text and links within Misskey's 20-level limit.
    template = BREAK if depth + nesting > 16 || (!inline && node.at_css('pre, blockquote, details'))
    nesting = 0 if template == BREAK
    centered = Sanitize::RichTextStyles.sanitize(node['style']).scan(/text-align: ([a-z]+);/).last == ['center']
    centered &&= !inline && depth + nesting < 16 && !node.at_css('pre, blockquote, details')
    content = children(node, depth: depth + nesting + (centered ? 1 : 0), inline: inline || template != BREAK || centered, list_depth: list_depth)
    unless template == BREAK || content.empty?
      @needs_mfm ||= template != base_template
      before, after = template.split(BREAK, 2)
      content = "#{before}#{finish(content)}#{after}"
    end

    if centered && !content.empty?
      @needs_mfm = true
      content = "<center>\n#{finish(content)}\n</center>"
    end
    Wxw::HtmlFormatter::BLOCKS.include?(node.name) || centered ? block(content) : content
  end

  def language(node)
    node['class'].to_s.split.filter_map { |name| LANGUAGE.match(name)&.captures&.first }.first
  end

  def code_block(node, inline:)
    content = Wxw::FederationHtml.code_text(node).gsub(/\r\n?/, "\n")
    code = node.at_css('code')
    lang = language(code || node)
    @needs_mfm ||= lang.present?
    # MFM has only triple-backtick fences. Preserve colliding fences as literal code.
    return block(inline_code(content)) if inline || content.empty? || content.match?(/^```/)

    block("```#{lang}\n#{content}\n```")
  end

  def inline_code(content)
    return '' if content.empty?
    return "`#{content}`" unless content.match?(/[`´\r\n]/)

    @needs_mfm = true
    "$[font.monospace #{literal(content)}]"
  end

  def details(node, depth:, inline:, list_depth:)
    summary = node.element_children.find { |child| child.name == 'summary' }
    heading = summary ? children(summary, depth: depth, inline: true, list_depth: list_depth) : ''
    body = node.children.reject { |child| child == summary }.map do |child|
      render(child, depth: depth + 1, inline: true, list_depth: list_depth)
    end.join
    body = finish(body)
    body = "$[blur #{body}]" unless body.empty? || depth >= 16
    block([heading, body].reject(&:empty?).join("\n"))
  end

  def list(node, depth:, inline:, list_depth:)
    number = node['start'].to_i
    number = 1 unless node['start']
    items = node.children.map do |item|
      next render(item, depth: depth, inline: inline, list_depth: list_depth) unless item.name == 'li'

      number = item['value'].to_i if item['value']
      marker = node.name == 'ol' ? "#{number}. " : '• '
      number += 1
      content = finish(children(item, depth: depth, inline: inline, list_depth: list_depth + 1))
      separator = content.start_with?('```', '<center>', '> ') ? "\n" : ''
      "#{'  ' * list_depth}#{marker}#{separator}#{content}"
    end
    block(items.reject(&:empty?).join("\n"))
  end

  def link(node, depth:, inline:, list_depth:)
    href = node['href']
    account = mention_accounts[href] if node['class'].to_s.split.include?('mention')
    return "@#{account.username}@#{account.local? ? Rails.configuration.x.local_domain : account.domain}" if account

    label = finish(formatted_element(node, depth: depth + 1, inline: true, list_depth: list_depth))
    return label if href.to_s.empty?
    return "#{label} (#{literal(href)})" unless href.match?(/\Ahttps?:\/\//i)

    url = href.gsub(/[[:space:][:cntrl:]<>]/) { |character| character.bytes.map { |byte| format('%%%02X', byte) }.join }
    return "#{label} (#{literal(href)})" if depth >= 16 || label.include?("\n")

    "[#{label.empty? ? literal(href) : label}](<#{url}>)"
  end

  def ruby(node, depth:, inline:, list_depth:)
    reading = node.element_children.select { |child| child.name == 'rt' }
    base = node.children.select(&:text?).map(&:text).join
    if depth < 16 && reading.one? && node.element_children.all? { |child| %w(rt rp).include?(child.name) } &&
       [base, reading.first.text].all? { |value| /\A[\p{L}\p{M}\p{N}]+\z/.match?(value) }
      "$[ruby #{base} #{reading.first.text}]"
    else
      children(node, depth: depth, inline: inline, list_depth: list_depth)
    end
  end

  def mention_accounts
    @mention_accounts ||= @mentions.each_with_object({}) do |mention, result|
      account = mention.account
      [account.uri, account.url, ActivityPub::TagManager.instance.uri_for(account), ActivityPub::TagManager.instance.url_for(account)].compact.each do |url|
        result[url] = account
      end
    end
  end

  def text(content)
    content.split(/(:[a-z0-9_]+:)/i).map do |part|
      @emojis.include?(part[1...-1]) && part.start_with?(':') && part.end_with?(':') ? part : literal(part)
    end.join
  end

  def literal(content)
    content.gsub(/\r\n?/, "\n").split("\n", -1).map do |line|
      next line if line.empty?

      # Splitting the closing tag keeps literal HTML from ending the plain region.
      line.split(/(?<=<)(?=\/plain>)/).map { |part| "<plain>#{part}</plain>" }.join
    end.join("\n")
  end

  def block(content)
    content.empty? ? '' : "#{BREAK}#{content}#{BREAK}"
  end

  def finish(content)
    content.sub(/\A\0+/, '').sub(/\0+\z/, '').gsub(/\0+/, "\n\n")
  end
end
