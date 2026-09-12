# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wxw::FederationHtml do
  describe '.format' do
    it 'keeps rich HTML without preformatted blocks unchanged' do
      html = '<h2>Heading</h2><details><summary>Title</summary><p style="color: red;">Body <code lang="en">inline</code></p></details>'.freeze

      expect(described_class.format(html)).to equal html
    end

    it 'moves block code attributes to pre while preserving code and indentation' do
      html = "<p>Before</p><pre style=\"padding: 4px; color: blue;\"><code class=\"language-html\" lang=\"en\" style=\"color: red;\">\n  &lt;p&gt;A &amp;amp; B&lt;/p&gt;\n\n</code></pre><p>After</p>".freeze
      document = Nokogiri::HTML5.fragment(described_class.format(html))
      pre = document.at_css('pre')
      code = pre.at_css('code')

      expect(pre['class']).to eq 'language-html'
      expect(pre['lang']).to eq 'en'
      expect(pre['style']).to eq 'padding: 4px; color: blue; color: red;'
      expect(pre.children.size).to eq 1
      expect(code.attributes).to be_empty
      expect(code.text).to eq "\n  <p>A &amp; B</p>\n\n"
      expect(document.css('p').map(&:text)).to eq %w(Before After)
    end

    it 'removes nested code markup while retaining explicit line breaks and whitespace' do
      html = "<pre><code lang=\"en\">  <span style=\"color: red;\">first</span><br><b>second</b>\n  &lt;tag&gt;</code></pre>"
      document = Nokogiri::HTML5.fragment(described_class.format(html))

      expect(document.css('pre > code').size).to eq 1
      expect(document.at_css('code').element_children).to be_empty
      expect(document.at_css('code').text).to eq "  first\nsecond\n  <tag>"
    end

    it 'wraps bare preformatted text and combines multiple code children without losing spaces' do
      html = "<pre>  first\n\nsecond  </pre><pre> <code>one</code>\n<code>two</code> </pre>"
      document = Nokogiri::HTML5.fragment(described_class.format(html))

      expect(document.css('pre > code').map(&:text)).to eq ["  first\n\nsecond  ", " one\ntwo "]
      expect(document.css('pre').map { |pre| pre.children.size }).to eq [1, 1]
    end

    it 'retains line boundaries of real block elements inside preformatted text' do
      html = '<pre>before<div>middle</div>after<p>one</p><p>two</p>&lt;p&gt;literal&lt;/p&gt;</pre>'
      document = Nokogiri::HTML5.fragment(described_class.format(html))

      expect(document.at_css('code').text).to eq "before\nmiddle\nafter\none\ntwo\n<p>literal</p>"
    end

    it 'preserves a leading newline when reparsing serialized bare preformatted text' do
      html = "<pre>\n\n  first\n</pre>"
      formatted = described_class.format(html)

      expect(Nokogiri::HTML5.fragment(formatted).at_css('code').text).to eq "\n  first\n"
      expect(described_class.format(formatted)).to eq formatted
    end

    it 'does not change code outside preformatted blocks and is idempotent' do
      html = '<p><code lang="en" style="color: red;">inline</code></p><pre><code class="language-ruby">puts &quot;a&quot;</code></pre>'
      formatted = described_class.format(html)

      expect(formatted).to start_with '<p><code lang="en" style="color: red;">inline</code></p>'
      expect(described_class.format(formatted)).to eq formatted
    end

    it 'keeps simple ruby annotations supported by Misskey unchanged' do
      html = '<p><ruby>字<rp>(</rp><rt>zi</rt><rp>)</rp></ruby></p>'.freeze

      expect(described_class.format(html)).to equal html
    end

    it 'keeps every base, annotation and space when complex ruby requires a fallback' do
      {
        '<ruby>New York</ruby>' => 'New York',
        '<ruby>A<rt>a</rt>B B<rt>bb</rt></ruby>' => 'A(a)B B(bb)',
        '<ruby>New York<rp>(</rp><rt>New York City</rt><rp>)</rp></ruby>' => 'New York(New York City)',
        '<ruby>字<rp>note:</rp><rt>zi</rt></ruby>' => '字note:(zi)',
      }.each do |html, text|
        formatted = described_class.format(html.freeze)
        document = Nokogiri::HTML5.fragment(formatted)

        aggregate_failures(html) do
          expect(document.text).to eq text
          expect(document.css('ruby, rt')).to be_empty
          expect(described_class.format(formatted)).to eq formatted
        end
      end
    end

    it 'retains styling and links inside a complex ruby fallback' do
      html = '<ruby><b>New York</b><rt><a href="https://example.org/reading">NY</a></rt></ruby>'
      document = Nokogiri::HTML5.fragment(described_class.format(html))

      expect(document.text).to eq 'New York(NY)'
      expect(document.at_css('b').text).to eq 'New York'
      expect(document.at_css('a')['href']).to eq 'https://example.org/reading'
    end

    it 'preserves the complete label and destination of ordinary @-label links' do
      %w(@home @home@away @home@away@lost).each do |label|
        html = "<p><a href=\"https://example.org/page?a=1&amp;b=2\">#{label}</a></p>".freeze
        formatted = described_class.format(html)
        document = Nokogiri::HTML5.fragment(formatted)

        aggregate_failures(label) do
          expect(document.text).to eq "#{label} (https://example.org/page?a=1&b=2)"
          expect(document.at_css('a')['href']).to eq 'https://example.org/page?a=1&b=2'
          expect(document.at_css('a').text).to eq 'https://example.org/page?a=1&b=2'
          expect(described_class.format(formatted)).to eq formatted
        end
      end
    end

    it 'retains @-labels without a destination as text' do
      document = Nokogiri::HTML5.fragment(described_class.format('<p><a>@lost</a></p>'))

      expect(document.text).to eq '@lost'
      expect(document.css('a')).to be_empty
    end

    it 'keeps canonical mention anchors and already supported rel=me links unchanged' do
      html = '<span class="h-card"><a href="https://example.org/@alice" class="u-url mention"><span>@alice</span></a></span>' \
             '<a href="https://example.org/page" rel="me nofollow noopener">@home</a>'

      expect(described_class.format(html.freeze)).to equal html
    end
  end
end
