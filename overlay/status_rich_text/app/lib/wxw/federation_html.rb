# frozen_string_literal: true

class Wxw::FederationHtml
  def self.format(html)
    return html unless html.match?(/<(?:pre|ruby|a)[\s>]/i)

    fragment = Nokogiri::HTML5.fragment(html)
    changed = false
    fragment.css('pre').each do |pre|
      code = pre.element_children.first
      if pre.element_children.one? && code.name == 'code'
        %w(class lang).each { |name| pre[name] = code[name] if code[name] }
        pre['style'] = [pre['style'], code['style']].compact.join(' ') if code['style']
      end

      # Misskey reads <pre> as raw text and only unwraps an attribute-free <code>.
      # Flatten nested presentation markup instead of printing it.
      code = fragment.document.create_element('code', code_text(pre))
      pre.children = code
      changed = true
    end

    fragment.css('ruby').reverse_each do |ruby|
      next if simple_ruby?(ruby)

      # Misskey's ruby conversion can discard spaced or unmatched bases.
      # Keep complex annotations readable without relying on that parser.
      ruby.name = 'span'
      ruby.css('rp').each { |node| node.remove if %w[( ) （ ）].include?(node.text) }
      ruby.css('rt').each do |node|
        node.add_previous_sibling(fragment.document.create_text_node('('))
        node.add_next_sibling(fragment.document.create_text_node(')'))
        node.name = 'span'
      end
      changed = true
    end

    fragment.css('a').each do |link|
      next unless link.text.start_with?('@')
      next if link['class']&.split&.include?('mention') || link['rel']&.start_with?('me ')

      # An ordinary @-label is not an ActivityPub mention.
      # Keep both its label and destination when Misskey would otherwise reinterpret the anchor.
      label = fragment.document.create_text_node(link.text)
      if link['href'].to_s.empty?
        link.replace(label)
      else
        link.add_previous_sibling(label)
        link.add_previous_sibling(fragment.document.create_text_node(' ('))
        link.content = link['href']
        link.add_next_sibling(fragment.document.create_text_node(')'))
      end
      changed = true
    end

    changed ? fragment.inner_html(preserve_newline: true) : html
  end

  def self.code_text(pre)
    text = +''
    visit = lambda do |node|
      if node.text?
        text << node.text
      elsif node.name == 'br'
        text << "\n"
      elsif node.element?
        block = Wxw::HtmlFormatter::BLOCKS.include?(node.name)
        text << "\n" if block && !text.empty? && !text.end_with?("\n")
        node.children.each(&visit)
        text << "\n" if block && !text.end_with?("\n")
      end
    end
    pre.children.each(&visit)
    text
  end

  def self.simple_ruby?(ruby)
    children = ruby.children.reject { |node| node.name == 'rp' && %w[( ) （ ）].include?(node.text) }
    children.size == 2 && children.first.text? && children.last.name == 'rt' &&
      children.none? { |node| node.text.empty? || node.text.match?(/[\s\[\]]/) }
  end
  private_class_method :simple_ruby?
end
