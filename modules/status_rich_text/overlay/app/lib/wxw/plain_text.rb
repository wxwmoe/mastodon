# frozen_string_literal: true

module Wxw::PlainText
  NEWLINE_TAGS_RE = %r{(<br(?=[\s/>])(?:[^>"']|"[^"]*"|'[^']*')*>|</p>|</h[1-6]>)+}i
  BLOCK_ELEMENTS = %w(blockquote dd details div dl dt footer h1 h2 h3 h4 h5 h6 header hgroup hr li ol p pre summary ul).freeze

  def self.with_block_newlines(node)
    result = +''
    pending_newline = false

    visit = lambda do |child|
      block = BLOCK_ELEMENTS.include?(child.name)
      pending_newline = true if block
      if child.text? || %w(pre code).include?(child.name)
        value = child.text
        unless value.empty?
          result << "\n" if pending_newline && !result.empty? && !result.end_with?("\n") && !value.start_with?("\n")
          result << value
          pending_newline = false
        end
      elsif child.element?
        child.children.each(&visit)
      end
      pending_newline = true if block
    end

    node.children.each(&visit)
    result
  end
end
