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

    expect(document.at_css('h1').text).to eq 'Heading'
    expect(document.css('hr').size).to eq 1
    expect(document.css('strong').map(&:text)).to eq ['bold']
    expect(document.at_css('em').text).to eq 'italic'
    expect(document.at_css('del').text).to eq 'deleted'
    expect(document.at_css('u').text).to eq 'underlined'
    expect(document.at_css('blockquote').text.strip).to eq 'quote'
    expect(document.css('li').map(&:text)).to eq %w(first second)
    expect(document.at_css('pre code').text).to eq "@user #tag\n"
    expect(document.text).not_to include '---'
  end

  it 'preserves all six heading levels' do
    {
      'text/markdown' => (1..6).map { |level| "#{'#' * level} Heading #{level}" }.join("\n\n"),
      'text/html' => (1..6).map { |level| "<h#{level}>\n Heading #{level}\n </h#{level}>" }.join("\n"),
    }.each do |content_type, source|
      html = described_class.render(source, content_type)
      document = Nokogiri::HTML5.fragment(html)

      expect(document.children.map(&:name)).to eq %w(h1 h2 h3 h4 h5 h6)
      expect(document.children.map(&:text)).to eq (1..6).map { |level| "Heading #{level}" }
      expect(html).not_to include "\n"
    end
  end

  it 'distinguishes soft line breaks, hard line breaks, and paragraphs' do
    {
      "first\nsecond" => [0, 1],
      "first  \nsecond" => [1, 1],
      "first   \nsecond" => [1, 1],
      "first\n\nsecond" => [0, 2],
    }.each do |source, (breaks, paragraphs)|
      document = Nokogiri::HTML5.fragment(described_class.render(source, 'text/markdown'))

      expect(document.css('br').size).to eq breaks
      expect(document.css('p').size).to eq paragraphs
    end
  end

  it 'ends a list at an unindented code fence and preserves following list numbers' do
    source = <<~MARKDOWN
      1. first
      2. second
      3. Nginx configuration:
      ```
          location / {
              try_files $uri $uri/ /index.php$is_args$args;
          }
      ```
      4. Docker commands:
      ```
          1. cd wxwClub/
          2. docker build -t 'wxwclub:worker' .
      ```
      5. last
    MARKDOWN
    document = Nokogiri::HTML5.fragment(described_class.render(source.freeze, 'text/markdown'))

    expect(document.children.map(&:name)).to eq %w(ol pre ol pre ol)
    expect(document.css('ol').map { |list| list['start'] }).to eq [nil, '4', '5']
    expect(document.css('pre code').map(&:text)).to eq [
      "    location / {\n        try_files $uri $uri/ /index.php$is_args$args;\n    }\n",
      "    1. cd wxwClub/\n    2. docker build -t 'wxwclub:worker' .\n",
    ]
  end

  it 'keeps indented code fences inside list items and closes an unfinished fence at the end' do
    source = "1. first\n   ```ruby\n   puts 'hello'\n   ```\n2. second\n\n```\nlast line"
    document = Nokogiri::HTML5.fragment(described_class.render(source, 'text/markdown'))

    expect(document.children.map(&:name)).to eq %w(ol pre)
    expect(document.at_css('li pre code').text).to eq "puts 'hello'\n"
    expect(document.css('pre code').last.text).to eq 'last line'
    expect(document.css('pre code').map { |node| node['class'] }).to eq ['language-ruby', nil]
    expect(document.css('pre span')).to be_empty
  end

  it 'keeps the first fence info word as language metadata without highlighting' do
    %w(js c++ c# Future_Lang.v2).each do |language|
      code = "  puts '<tag>'\n\n    next\n"
      source = "```#{language} extra options\n#{code}```"
      html = described_class.render(source.freeze, 'text/markdown')
      document = Nokogiri::HTML5.fragment(html)

      aggregate_failures(language) do
        expect(document.at_css('pre > code')['class']).to eq "language-#{language}"
        expect(document.at_css('pre > code').text).to eq code
        expect(document.css('pre span')).to be_empty
        expect(Sanitize.fragment(html, Sanitize::Config::MASTODON_STRICT)).to eq html
      end
    end
  end

  it 'normalizes whitespace across inline and block boundaries consistently' do
    source = "<p>\n<b>first </b>\n<span> </span><em>second </em>\n</p>\n<p>\nthird<br>\n<span>\nlast\n</span>\n</p>"
    html = described_class.render(source, 'text/html')
    document = Nokogiri::HTML5.fragment(html)

    expect(document.css('p').map(&:text)).to eq ['first second', 'thirdlast']
    expect(html).not_to include "\n"
    expect(described_class.render(html, 'text/html')).to eq html
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

  it 'keeps entity recognition stable when serializing long unsupported images' do
    source = "![#{'text ' * 12}@alice](image.png) @alice #topic".freeze
    formatter = Wxw::HtmlFormatter.new(source, content_type: 'text/markdown')

    expect(formatter.entity_text).to eq '@alice @alice #topic'
    expect(formatter.text).to eq source
    expect(Nokogiri::HTML5.fragment(formatter.to_s).css('img')).to be_empty
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

  it 'preserves unsupported Markdown extensions as text' do
    {
      '![alt](https://example.org/image.png)' => '![alt](https://example.org/image.png)',
      "|a|b|\n|-|-|\n|1|2|" => '|a|b| |-|-| |1|2|',
      'x^2^' => 'x^2^',
    }.each do |source, expected|
      expect(Nokogiri::HTML5.fragment(described_class.render(source, 'text/markdown')).text.strip).to eq expected
    end
  end

  it 'uses GFM single and double tilde strikethrough without enabling superscript or subscript' do
    document = Nokogiri::HTML5.fragment(described_class.render('x^2^ H~2~O ~~deleted~~', 'text/markdown'))

    expect(document.css('sup, sub')).to be_empty
    expect(document.css('del').map(&:text)).to eq %w(2 deleted)
    expect(document.text).to eq 'x^2^ H2O deleted'
  end

  it 'keeps image labels, destinations, and titles visible using normalized Markdown syntax' do
    {
      '前文 ![标*记*](https://example.org/a_b.png "题名") 后文' => '前文 ![标*记*](https://example.org/a_b.png "题名") 后文',
      "![alt][ref]\n\n[ref]: https://example.org/image.png \"title\"" => '![alt](https://example.org/image.png "title")',
      "![alt][]\n\n[alt]: https://example.org/image.png" => '![alt](https://example.org/image.png)',
      "中文 ![line\r\none](https://example.org/image.png\r\n\"title\") 后文" => '中文 ![line one](https://example.org/image.png "title") 后文',
    }.each do |source, expected|
      document = Nokogiri::HTML5.fragment(described_class.render(source.freeze, 'text/markdown'))

      expect(document.text.strip).to eq expected
      expect(document.css('img, em, a')).to be_empty
    end
  end

  it 'preserves nested image syntax and its surrounding link destination' do
    source = '[![outer ![inner](inner.png)](outer.png)](https://example.org)'
    document = Nokogiri::HTML5.fragment(described_class.render(source.freeze, 'text/markdown'))

    expect(document.css('img')).to be_empty
    expect(document.css('a').size).to eq 1
    expect(document.at_css('a')['href']).to eq 'https://example.org'
    expect(document.at_css('a').text).to eq '![outer ![inner](inner.png)](outer.png)'
  end

  it 'leaves escaped image syntax and images inside code unchanged and sanitizes raw images' do
    {
      '\\![alt](image.png)' => '!alt',
      '`![alt](image.png)`' => '![alt](image.png)',
      '<img src="image.png" alt="raw">' => '',
    }.each do |source, expected|
      document = Nokogiri::HTML5.fragment(described_class.render(source, 'text/markdown'))

      expect(document.text.strip).to eq expected
      expect(document.css('img')).to be_empty
    end
  end
end
