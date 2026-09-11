# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wxw::PostFormat do
  it 'renders Markdown separately without modifying its original source' do
    source = '**bold** <u>underlined</u>'.freeze

    expect(described_class.render(source, 'text/markdown')).to include '<strong>bold</strong>', '<u>underlined</u>'
    expect(source).to eq '**bold** <u>underlined</u>'
    expect(described_class.render(source, 'text/html')).to eq source
    expect(described_class.render(nil, 'text/markdown')).to eq ''
  end

  it 'converts Markdown and inline HTML with the Mastodon allowlist' do
    source = "# Heading\n\n**bold** *italic* ~~deleted~~ <u>underlined</u>\n\n> quote\n\n- first\n- second\n\n```\n@user #tag\n```\n\n---"
    document = Nokogiri::HTML5.fragment(described_class.render(source, 'text/markdown'))

    expect(document.css('h1, hr')).to be_empty
    expect(document.css('strong').map(&:text)).to eq %w(Heading bold)
    expect(document.at_css('em').text).to eq 'italic'
    expect(document.at_css('del').text).to eq 'deleted'
    expect(document.at_css('u').text).to eq 'underlined'
    expect(document.at_css('blockquote').text.strip).to eq 'quote'
    expect(document.css('li').map(&:text)).to eq %w(first second)
    expect(document.at_css('pre code').text).to eq "@user #tag\n"
    expect(document.text).to include '---'
  end

  it 'retains escape and entity interpretation and cleans unsupported HTML in rich mode' do
    {
      '\\*literal\\* &amp;' => '*literal* &',
      '<div>outside</div>' => 'outside',
      '<b onclick="bad()">safe</b><script>hidden</script>' => 'safe',
    }.each do |source, expected|
      html = described_class.render(source, 'text/markdown')

      expect(Nokogiri::HTML5.fragment(html).text.strip).to eq expected
      expect(Sanitize.fragment(html, Sanitize::Config::MASTODON_STRICT)).to eq html
    end
  end

  it 'preserves underscores in mentions, custom emoji, and hashtags alongside Markdown' do
    identifiers = '@foo_bar_baz @_foo_ @foo__bar__baz @foo_bar@remote.example :blob_cat_hug: :_foo_: :foo__bar__baz: #hello_world_again #_foo_'
    document = Nokogiri::HTML5.fragment(described_class.render("**Private** #{identifiers}", 'text/markdown'))

    expect(document.at_css('strong').text).to eq 'Private'
    expect(document.css('em')).to be_empty
    expect(document.text.strip).to eq "Private #{identifiers}"
  end

  it 'preserves identifiers inside code and HTML while retaining ordinary emphasis' do
    source = "_italic_ word**bold**word `@_foo_ :_foo_:`\n\n```\n@foo__bar__baz :blob_cat_hug:\n```\n\n<strong>#hello_world_again</strong>"
    document = Nokogiri::HTML5.fragment(described_class.render(source, 'text/markdown'))

    expect(document.at_css('em').text).to eq 'italic'
    expect(document.css('strong').map(&:text)).to eq %w(bold #hello_world_again)
    expect(document.css('code').map(&:text)).to eq ['@_foo_ :_foo_:', "@foo__bar__baz :blob_cat_hug:\n"]
  end

  it 'preserves Markdown punctuation in native URLs through rendering and link extraction' do
    urls = %w(https://example.org/foo_bar_baz https://example.org/a__b__c https://example.org/?q=foo_bar_baz https://example.org/foo*bar*baz https://example.org/?q=foo~~bar~~baz)
    formatter = Wxw::HtmlFormatter.new("**link** #{urls.join(' ')}", content_type: 'text/markdown')
    document = Nokogiri::HTML5.fragment(formatter.to_s)

    expect(document.css('strong').map(&:text)).to eq ['link']
    expect(document.css('em, del')).to be_empty
    expect(document.css('a').map { |link| link['href'] }).to eq urls
    expect(formatter.urls.map(&:to_s)).to eq urls
  end

  it 'renders explicitly escaped URL punctuation without automatically linking it' do
    urls = %w(https://example.org/foo_bar_baz https://example.org/a__b__c https://example.org/foo*bar*baz https://example.org/?q=foo~~bar~~baz&b=c)
    escaped = urls.map { |url| url.gsub(/[._*~]/) { |character| "\\#{character}" }.gsub('&', '&amp;') }
    formatter = Wxw::HtmlFormatter.new("**link** #{escaped.join(' ')}", content_type: 'text/markdown')
    document = Nokogiri::HTML5.fragment(formatter.to_s)

    expect(document.text.strip).to eq "link #{urls.join(' ')}"
    expect(document.css('em, del')).to be_empty
    expect(document.css('a')).to be_empty
    expect(formatter.urls).to be_empty
  end

  it 'respects even and odd backslash runs before URL punctuation' do
    (1..4).each do |count|
      escaped_url = "https://example.org/foo#{'\\' * count}_bar#{'\\' * count}_baz"
      expected_url = "https://example.org/foo#{'\\' * (count / 2)}_bar#{'\\' * (count / 2)}_baz"
      formatter = Wxw::HtmlFormatter.new("**link** #{escaped_url}", content_type: 'text/markdown')
      document = Nokogiri::HTML5.fragment(formatter.to_s)

      expect(document.text.strip).to eq "link #{expected_url}"
      expect(document.css('em')).to be_empty
      expect(document.css('a')).to be_empty
      expect(formatter.urls).to be_empty
    end
  end

  it 'retains genuine Markdown wrapping URLs and explicit link syntax' do
    url = 'https://example.org/foo_bar*baz*qux~~tail~~end'
    source = "*#{url}* **#{url}** ~~#{url}~~ [link](#{url}) <#{url}>"
    document = Nokogiri::HTML5.fragment(described_class.render(source, 'text/markdown'))

    expect(document.css('em').map(&:text)).to eq [url]
    expect(document.css('strong').map(&:text)).to eq [url]
    expect(document.css('del').map(&:text)).to eq [url]
    expect(document.css('a').map { |link| link['href'] }).to eq [url, url]
  end

  it 'keeps URL punctuation in code and HTML without changing ordinary emphasis' do
    url = 'https://example.org/foo_bar*baz*qux~~tail~~end'
    source = "_italic_ word**bold**word `#{url}` <a href=\"#{url}\">link</a>"
    document = Nokogiri::HTML5.fragment(described_class.render(source, 'text/markdown'))

    expect(document.at_css('em').text).to eq 'italic'
    expect(document.at_css('strong').text).to eq 'bold'
    expect(document.at_css('code').text).to eq url
    expect(document.at_css('a')['href']).to eq url
  end

  it 'preserves unsupported image and table syntax as text' do
    ['![alt](https://example.org/image.png)', "|a|b|\n|-|-|\n|1|2|"].each do |source|
      expect(Nokogiri::HTML5.fragment(described_class.render(source, 'text/markdown')).text.strip).to eq source
    end
  end
end
