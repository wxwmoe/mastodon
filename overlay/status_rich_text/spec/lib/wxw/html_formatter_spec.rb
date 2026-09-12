# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wxw::HtmlFormatter do
  let(:account) { Fabricate.build(:account, username: 'alice') }

  def formatter_for(text, **options)
    described_class.new(text, { content_type: 'text/html', preloaded_accounts: [account] }.merge(options))
  end

  def format(text, **options)
    formatter_for(text, **options).to_s
  end

  it 'retains every shared Mastodon allowlisted element and no other elements' do
    source = '<p><b>b</b> <strong>s</strong> <i>i</i> <em>e</em> <u>u</u> <del>d</del> <s>s</s><br><span>span</span> <a href="https://example.com/">link</a> <ruby>字<rt>zi</rt><rp>(</rp></ruby></p><blockquote>quote</blockquote><pre><code>code</code></pre><ul><li>a</li></ul><ol start="3"><li value="4">b</li></ol>' \
             '<h1>one</h1><h2>two</h2><h3>three</h3><h4>four</h4><h5>five</h5><h6>six</h6><p><abbr title="Hypertext Markup Language">HTML</abbr> H<sub>2</sub>O x<sup>2</sup></p>' \
             '<p><small>small</small><wbr><time datetime="2026-09-12">time</time><mark>mark</mark><kbd>kbd</kbd><ins>ins</ins></p><hr>' \
             '<hgroup><h2>group</h2><p>subtitle</p></hgroup><header>header</header><footer>footer</footer>' \
             '<dl><dt>term</dt><dd>definition</dd></dl><details><summary>summary</summary><p>detail</p></details>' \
             '<div style="text-align: center;">centered</div>'
    html = format(source)
    document = Nokogiri::HTML5.fragment(html)

    expect(document.css('*').map(&:name).uniq).to match_array Sanitize::Config::MASTODON_STRICT[:elements]
    expect(Sanitize.fragment(html, Sanitize::Config::MASTODON_STRICT)).to eq html
    expect(document.at_css('ol')['start']).to eq '3'
    expect(document.at_css('ol li')['value']).to eq '4'
    expect(document.at_css('div')['style']).to eq 'text-align: center;'
    expect(document.at_css('div').text).to eq 'centered'
  end

  it 'retains only abbreviation titles and keeps the added elements inline' do
    source = "<p>H<sub style=\"position:fixed\">2</sub>O x<sup onclick=\"bad()\">2</sup> <abbr title=\"Hypertext &amp; Markup\" id=\"label\" class=\"custom\" onclick=\"bad()\">HTML</abbr>\n text</p>"
    document = Nokogiri::HTML5.fragment(format(source))

    expect(document.at_css('p').text).to eq 'H2O x2 HTML text'
    expect(document.at_css('abbr').attributes.keys).to eq ['title']
    expect(document.at_css('abbr')['title']).to eq 'Hypertext & Markup'
    expect(document.css('sub, sup').flat_map { |node| node.attributes.keys }).to be_empty
    expect(document.css('br')).to be_empty
  end

  it 'keeps headings separate from adjacent paragraphs and headings in plain text' do
    source = '<p>before</p>' + (1..6).map { |level| "<h#{level}>heading#{level}</h#{level}>" }.join + '<p>after</p>'
    plain = formatter_for(source).plain_text

    expect(plain).to start_with 'before'
    expect(plain.lines.map(&:strip).reject(&:empty?)).to eq %w(before heading1 heading2 heading3 heading4 heading5 heading6 after)
  end

  it 'keeps styled line breaks through HTML and Markdown rendering and remote formatting' do
    source = '<h6>heading</h6><p>one<br style="color:red"><br lang="en">two</p>'

    %w(text/html text/markdown).each do |content_type|
      formatter = formatter_for(source, content_type: content_type)
      document = Nokogiri::HTML5.fragment(formatter.to_s)
      expect(document.at_css('h6').text).to eq 'heading'
      expect(document.css('br').size).to eq 2
      expect(document.at_css('br')['style']).to eq 'color: red;'
      expect(formatter.plain_text).to eq "heading\none\ntwo"
    end

    remote_html = HtmlAwareFormatter.new(source, false).to_s
    expect(Nokogiri::HTML5.fragment(remote_html).at_css('h6').text).to eq 'heading'
    expect(Nokogiri::HTML5.fragment(remote_html).at_css('br')['style']).to eq 'color: red;'
    expect(PlainTextFormatter.new(remote_html, false).to_s).to eq "heading\none\ntwo"
  end

  it 'retains plain-text block boundaries after normalizing HTML and Markdown whitespace' do
    ["- first item\n- second item", "1. first item\n2. second item"].each do |source|
      expect(formatter_for(source, content_type: 'text/markdown').plain_text).to eq "first item\nsecond item"
    end

    %w(p h1 h2 h3 h4 h5 h6 blockquote pre ul ol li).each do |tag|
      source = "before\n<#{tag}>first</#{tag}>\n<#{tag}>second</#{tag}>\nafter"
      expect(formatter_for(source).plain_text).to eq "before\nfirst\nsecond\nafter"
    end

    source = "before<pre><code>  first\n\n  second\n</code></pre>after"
    expect(formatter_for(source).plain_text).to eq "before\n  first\n\n  second\nafter"
    expect(formatter_for("one<code>  two\nthree  </code>four").plain_text).to eq "one  two\nthree  four"
  end

  it 'keeps static styles while removing unsafe declarations and event handlers' do
    source = '<p style="color: RED; background-color: #FFEECC; padding: 4px; position: fixed" onclick="bad()">before ' \
             '<mark style="font-weight: 700; opacity: 0" onmouseover="bad()">marked</mark></p>'

    %w(text/html text/markdown).each do |content_type|
      formatter = formatter_for(source.freeze, content_type: content_type)
      html = formatter.to_s
      document = Nokogiri::HTML5.fragment(html)

      expect(document.at_css('p')['style']).to eq 'color: red; background-color: #ffeecc; padding: 4px;'
      expect(document.at_css('mark')['style']).to eq 'font-weight: 700;'
      expect(document.css('[onclick], [onmouseover]')).to be_empty
      expect(formatter.text).to eq source
      expect(formatter.plain_text).to eq 'before marked'
      expect(HtmlAwareFormatter.new(html, false).to_s).to eq html
    end
  end

  it 'keeps time metadata and closed details content without allowing additional attributes' do
    source = '<details open ontoggle="bad()" style="padding: 4px"><summary id="title">More</summary>' \
             '<p><time datetime="2026-09-12T10:00:00Z" title="extra" onclick="bad()" style="font-style: italic">today</time> ' \
             '<ins datetime="2026-09-12">added</ins></p></details>'
    document = Nokogiri::HTML5.fragment(format(source))

    expect(document.at_css('details').attributes.keys).to eq ['style']
    expect(document.at_css('details')['style']).to eq 'padding: 4px;'
    expect(document.at_css('summary').attributes).to be_empty
    expect(document.at_css('time').attributes.keys).to match_array %w(datetime style)
    expect(document.at_css('time')['datetime']).to eq '2026-09-12T10:00:00Z'
    expect(document.at_css('time')['style']).to eq 'font-style: italic;'
    expect(document.at_css('ins').attributes).to be_empty
    expect(document.at_css('details p').text).to eq 'today added'
  end

  it 'separates structural elements and collapsed content in plain text without spacing word breaks' do
    source = '<p>before</p><header>header</header><hgroup><h2>heading</h2><p>subtitle</p></hgroup>' \
             '<details><summary>summary</summary>body<dl><dt>term</dt><dd>definition</dd></dl>tail</details>' \
             'left<hr>right<footer>footer</footer><p>ab<wbr>cd</p>'

    expect(formatter_for(source).plain_text.lines.map(&:strip).reject(&:empty?)).to eq %w(before header heading subtitle summary body term definition tail left right footer abcd)
    expect(Nokogiri::HTML5.fragment(format(source)).css('p').last.text).to eq 'abcd'
  end

  it 'uses the original formatter unchanged for plain text and literal Markdown' do
    ['**bold** *italic* ~~deleted~~', "first\n\nsecond", '1 < 2 & 3 > 2', '<unknown>literal</unknown>', '<b>literal</b>', '&lt;b&gt;literal&lt;/b&gt;'].each do |text|
      expect(format(text, content_type: 'text/plain')).to eq TextFormatter.new(text, preloaded_accounts: [account]).to_s
    end
  end

  it 'renders and sanitizes HTML without changing its source' do
    source = '<p style="position:fixed"><b>safe</b><script>hidden</script></p>'.freeze
    formatter = formatter_for(source)

    expect(formatter.to_s).to eq '<p><b>safe</b></p>'
    expect(formatter.text).to eq source
    expect(formatter.plain_text).to eq 'safe'
    expect(formatter_for('<p><img src="image.png"></p>').plain_text).to eq ''
  end

  it 'filters scripts, event handlers, unsafe styles, images and unsafe destinations' do
    document = Nokogiri::HTML5.fragment(format('<strong onclick="alert(1)" style="position:fixed">bold</strong><script>alert(1)</script><img src=x onerror=alert(1)><a href="javascript:alert(1)">bad</a><a href="/admin">relative</a><iframe>hidden</iframe>'))

    expect(document.css('script, img, iframe, [onclick], [onerror], [style], a')).to be_empty
    expect(document.text).to eq 'boldbadrelative'
  end

  it 'keeps explicit HTML breaks without inserting extra breaks between block elements' do
    html = format("<strong>a</strong><br>\n<em>b</em><br><br>end\n<p>block</p>\n<ul>\n<li>one</li>\n<li>two</li>\n</ul>")
    document = Nokogiri::HTML5.fragment(html)

    expect(html).not_to include "\n"
    expect(document.css('br')).to have_attributes(size: 3)
    expect(document.at_css('br').next_sibling.name).to eq 'em'
    expect(document.css('ul > br, p > ul')).to be_empty
    expect(document.at_css('ul').children.map(&:name)).to eq %w(li li)
    expect(document.css('li').map(&:text)).to eq %w(one two)
  end

  it 'preserves code whitespace and does not linkify inside code or existing links' do
    source = "<pre><code>  @alice #topic\n https://example.com/\n</code></pre><code>inline\n\t code</code><a href=\"https://example.net/\">@alice #topic</a>"
    document = Nokogiri::HTML5.fragment(format(source))

    expect(document.css('code').map(&:text)).to eq ["  @alice #topic\n https://example.com/\n", "inline\n\t code"]
    expect(document.css('code a, code br, a a')).to be_empty
    expect(document.css('a')).to have_attributes(size: 1)
  end

  it 'keeps only the first bounded language class on code blocks across local and remote formatting' do
    classes = {
      'language-Ruby' => 'language-Ruby',
      "custom\tlanguage-c++\nlanguage-ruby mention" => 'language-c++',
      'language-! language-c#' => 'language-c#',
      'language-Future_Lang.v2' => 'language-Future_Lang.v2',
      "language-#{'a' * 64}" => "language-#{'a' * 64}",
      "language-#{'a' * 65}" => nil,
      'language-' => nil,
      'language-.ruby' => nil,
      'language-ruby/path' => nil,
      'language-ruby:extra' => nil,
      "language-ruby\u00a0custom" => nil,
      'mention custom' => nil,
      '' => nil,
    }
    code = "  @alice #topic <tag>\n\n    https://example.com/\n"

    classes.each do |source_class, expected_class|
      source = "<pre><code class=\"#{source_class}\">#{ERB::Util.h(code)}</code></pre>"

      [format(source), format(source, content_type: 'text/markdown'), HtmlAwareFormatter.new(source, false).to_s].each do |html|
        document = Nokogiri::HTML5.fragment(html)
        aggregate_failures(source_class) do
          expect(document.at_css('pre > code')['class']).to eq expected_class
          expect(document.at_css('pre > code').text).to eq code
          expect(document.css('code a, code span')).to be_empty
          expect(Sanitize.fragment(html, Sanitize::Config::MASTODON_STRICT)).to eq html
        end
      end
    end
  end

  it 'drops language classes outside direct pre children without changing existing semantic classes' do
    source = '<p class="mention language-ruby"><code class="language-ruby">inline</code></p>' \
             '<pre class="language-ruby"><span class="language-ruby"><code class="language-ruby">nested</code></span></pre>' \
             '<pre><code>unlabelled</code></pre>'

    [format(source), HtmlAwareFormatter.new(source, false).to_s].each do |html|
      document = Nokogiri::HTML5.fragment(html)
      expect(document.css('code').map(&:text)).to eq %w(inline nested unlabelled)
      expect(document.css('code[class], [class*="language-"]')).to be_empty
      expect(document.at_css('p')['class']).to eq 'mention'
      expect(Sanitize.fragment(html, Sanitize::Config::MASTODON_STRICT)).to eq html
    end
  end

  it 'collapses HTML whitespace separating emphasis and links while retaining nonbreaking spaces' do
    { ' ' => ' ', "\n" => ' ', "\t" => ' ', " \r\n\t " => ' ', '&nbsp;' => "\u00a0" }.each do |source_space, expected_space|
      source = "<p><strong>one</strong>#{source_space}<em>two</em>#{source_space}<a href=\"https://example.org/\">three</a></p>"
      document = Nokogiri::HTML5.fragment(format(source))

      expect(document.at_css('p').text).to eq "one#{expected_space}two#{expected_space}three"
      expect(document.css('br')).to be_empty
    end
  end

  it 'normalizes Markdown line breaks without changing the source or prose entities' do
    source = "first\n[link](https://explicit.example/)\n@alice #topic https://example.org/  \nlast\n\nnext".freeze
    formatter = formatter_for(source, content_type: 'text/markdown')
    html = formatter.to_s
    document = Nokogiri::HTML5.fragment(html)

    expect(html).not_to include "\n"
    expect(document.at_css('p').text).to start_with 'first link @alice #topic '
    expect(document.css('br')).to have_attributes(size: 1)
    expect(document.at_css('br').next_sibling.text).to eq 'last'
    expect(document.css('p').map(&:text).last).to eq 'next'
    expect(document.css('p')).to have_attributes(size: 2)
    expect(document.css('a.mention:not(.hashtag)').map(&:text)).to eq ['@alice']
    expect(document.css('a.hashtag').map(&:text)).to eq ['#topic']
    expect(formatter.urls.map(&:to_s)).to eq ['https://explicit.example/', 'https://example.org/']
    expect(formatter.text).to eq source
    expect(formatter.rewrite_mentions { '@bob' }).to eq source.sub('@alice', '@bob')
  end

  it 'keeps native mentions, hashtags, URL shortening and emoji shortcodes in prose' do
    document = Nokogiri::HTML5.fragment(format('<b>@alice #topic :blob_cat:</b> https://example.com/path?q=a&b=c'))

    expect(document.at_css('b a.mention').text).to eq '@alice'
    expect(document.at_css('b a.hashtag').text).to eq '#topic'
    expect(document.text).to include ':blob_cat:'
    expect(document.css('a').map { |node| node['href'] }).to include 'https://example.com/path?q=a&b=c'
    expect(document.at_css('a span.invisible')).to be_present
  end

  it 'only extracts prose entities and valid HTTP links outside code' do
    formatter = formatter_for('<b>@alice #topic</b> <a title="@attribute" href="https://example.com/">@label #label</a><code>@code #code https://code.example/ <a href="https://code.example/">link</a></code><pre>@pre #pre</pre><a href="https://[bad">bad</a><a href="xmpp:user@example.com">chat</a> https://plain.example.org/')

    expect(formatter.entity_text).to include '@alice #topic'
    expect(formatter.entity_text).to_not match(/@attribute|@label|#label|@code|#code|@pre|#pre/)
    expect(formatter.urls.map(&:to_s)).to eq ['https://example.com/', 'https://plain.example.org/']
    expect(formatter.plain_text).to include '@alice #topic', '@code #code'
    expect(formatter.plain_text).to_not include '<b>', '<code>'
  end

  it 'adds the native quote fallback once' do
    quote = Fabricate.build(:status, account: account)
    allow(ActivityPub::TagManager.instance).to receive(:url_for).with(quote).and_return('https://example.com/quoted')

    document = Nokogiri::HTML5.fragment(format('<b>quote</b>', quoted_status: quote))
    expect(document.at_css('p.quote-inline a')['href']).to eq 'https://example.com/quoted'
    expect(Nokogiri::HTML5.fragment(format('<a href="https://example.com/quoted">quote</a>', quoted_status: quote)).css('.quote-inline')).to be_empty
    ['<script>https://example.com/quoted</script><p>hi</p>', '<!-- https://example.com/quoted --><p>hi</p>'].each do |source|
      expect(Nokogiri::HTML5.fragment(format(source, quoted_status: quote)).at_css('p.quote-inline a')['href']).to eq 'https://example.com/quoted'
    end
  end

  it 'rewrites mention accounts only in prose while retaining rich markup' do
    ['@alice', '<p>@alice</p><code>@alice</code><a href="https://example.com/@alice">@alice</a>'].each do |source|
      accounts = []
      result = formatter_for(source).rewrite_mentions do |_match, acct|
        accounts << acct
        '@bob'
      end

      expect(accounts).to eq ['alice']
      expect(result).to eq source.sub('@alice', '@bob')
    end
  end

  it 'retains native plain-text mention rewriting' do
    result = formatter_for('@alice', content_type: 'text/plain').rewrite_mentions { |_match, _acct| '@bob' }

    expect(result).to eq '@bob'
  end

  it 'changes only the original source spans belonging to rendered prose mentions' do
    {
      'text/html' => [
        ['<p title="@alice">@alice &#64;alice</p><!-- @alice --><code>@alice</code>', '<p title="@alice">@bob &#64;alice</p><!-- @alice --><code>@alice</code>'],
        ['🍵 @alice \\@alice &commat;alice &#x40;alice', '🍵 @bob \\@alice &commat;alice &#x40;alice'],
      ],
      'text/markdown' => [
        ["**@alice** `@alice` [@alice](https://example.com/@alice)\n\n[@alice]: https://example.com/", "**@bob** `@alice` [@alice](https://example.com/@alice)\n\n[@alice]: https://example.com/"],
        ["[@alice][@alice]\n\n@alice\n\n[@alice]: https://example.com/", "[@alice][@alice]\n\n@bob\n\n[@alice]: https://example.com/"],
        ['*&#64;alice* @ali&#99;e @alice\\@remote.example @alice', '*&#64;alice* @ali&#99;e @alice\\@remote.example @bob'],
        ['\\@alice @ali\\_ce @alice', '\\@alice @ali\\_ce @bob'],
      ],
    }.each do |content_type, cases|
      cases.each do |source, expected|
        result = formatter_for(source, content_type: content_type).rewrite_mentions { |_match, _acct| '@bob' }

        expect(result).to eq expected
      end
    end
  end

  it 'rewrites only literal Markdown prose mentions while retaining encoded text, code and links' do
    source = "`@alice`\n\n**@alice** &#64;alice [@alice](https://example.com/)".freeze
    accounts = []
    result = formatter_for(source, content_type: 'text/markdown').rewrite_mentions do |_match, acct|
      accounts << acct
      '@bob'
    end

    expect(accounts).to eq ['alice']
    expect(result).to eq "`@alice`\n\n**@bob** &#64;alice [@alice](https://example.com/)"
    expect(Nokogiri::HTML5.fragment(format(source, content_type: 'text/markdown')).css('a.mention')).to have_attributes(size: 1)
  end

  it 'recognizes complete underscore emphasis without confusing bare underscore usernames' do
    {
      '_@alice_' => [['alice'], '_@bob_'],
      '__@alice__' => [['alice'], '__@bob__'],
      '_@alice_ @alice_' => [%w(alice alice_), '_@bob_ @bob'],
      '_@al_ice_' => [['al_ice'], '_@bob_'],
      '__@al_ice__' => [['al_ice'], '__@bob__'],
      '_@alice__ @bob' => [['bob'], '_@alice__ @bob'],
      '_@alice___ @bob' => [['bob'], '_@alice___ @bob'],
      '__@alice___ @bob' => [['bob'], '__@alice___ @bob'],
      '_@ali**ce**_' => [[], '_@ali**ce**_'],
      '_@ali&#99;e_' => [[], '_@ali&#99;e_'],
    }.each do |source, (expected_accounts, expected_source)|
      formatter = formatter_for(source, content_type: 'text/markdown')
      accounts = []
      rewritten = formatter.rewrite_mentions do |_match, acct|
        accounts << acct
        '@bob'
      end

      expect(accounts).to eq expected_accounts
      expect(rewritten).to eq expected_source
    end
    %w(_ __).each do |delimiter|
      document = Nokogiri::HTML5.fragment(format("#{delimiter}@alice#{delimiter}", content_type: 'text/markdown'))
      expect(document.css('em a.mention, strong a.mention').map(&:text)).to eq ['@alice']
    end
  end

  it 'preserves underscore emphasis when resolving a canonical username containing underscores' do
    %w(_ __).each do |delimiter|
      %w(@foo_bar @foo_bar@remote.example).each do |replacement|
        source = "#{delimiter}@alice#{delimiter}"
        rewritten = formatter_for(source, content_type: 'text/markdown').rewrite_mentions { replacement }

        expect(rewritten).to eq "#{delimiter}#{replacement}#{delimiter}"
        expect(Nokogiri::HTML5.fragment(Wxw::PostFormat.render(rewritten, 'text/markdown')).css('em, strong').map(&:text)).to eq [replacement]
      end
    end
  end

  it 'keeps Markdown reference labels case insensitive without losing prose entities' do
    [
      ["[link][#TOPIC]\n\n@alice #topic\n\n[#topic]: https://example.org/", "[link][#TOPIC]\n\n@bob #topic\n\n[#topic]: https://example.org/"],
      ["[@ALICE][@ALICE]\n\n@alice\n\n[@alice]: https://example.org/", "[@ALICE][@ALICE]\n\n@bob\n\n[@alice]: https://example.org/"],
      ["[@alice]: https://example.org/\n\n[@alice][@alice]\n\n@ALICE", "[@alice]: https://example.org/\n\n[@alice][@alice]\n\n@bob"],
    ].each do |source, expected|
      formatter = formatter_for(source, content_type: 'text/markdown')
      accounts = []
      rewritten = formatter.rewrite_mentions do |_match, acct|
        accounts << acct
        '@bob'
      end

      expect(accounts.size).to eq 1
      expect(rewritten).to eq expected
      expect(formatter.urls.map(&:to_s)).to eq ['https://example.org/']
      expect(Nokogiri::HTML5.fragment(formatter.to_s).at_css('a')['href']).to eq 'https://example.org/'
    end
  end

  %w(text/html text/markdown).each do |content_type|
    it "only recognizes complete literal entities in #{content_type}" do
      cases = {
        'literal' => ['@alice #topic https://example.org/', true],
        'whole element' => ['<b>@alice #topic https://example.org/</b>', true],
        'separate elements' => ['<b>@alice</b> <b>#topic</b> <b>https://example.org/</b>', true],
        'heading' => ['word<h1>@alice #topic https://example.org/</h1>', true],
        'abbreviation' => ['<abbr title="@attribute #attribute">@alice #topic https://example.org/</abbr>', true],
        'subscript' => ['<sub>@alice #topic https://example.org/</sub>', true],
        'superscript' => ['<sup>@alice #topic https://example.org/</sup>', true],
        'division' => ['word<div>@alice #topic https://example.org/</div>', true],
        'internal element' => ['@ali<b>ce</b> #top<b>ic</b> https://exa<b>mple</b>.org/', false],
        'internal added element' => ['@ali<sub>ce</sub> #top<sup>ic</sup> https://exa<abbr>mple</abbr>.org/', false],
        'empty element' => ['@ali<i></i>ce #top<i></i>ic https://exa<i></i>mple.org/', false],
        'comment' => ['@ali<!-- gap -->ce #top<!-- gap -->ic https://exa<!-- gap -->mple.org/', false],
        'removed element' => ['@ali<font>ce</font> #top<font>ic</font> https://exa<font>mple</font>.org/', false],
        'removed content' => ['@ali<script>x</script>ce #top<script>x</script>ic https://exa<script>x</script>mple.org/', false],
        'removed whitespace' => ['@ali<script> </script>ce #top<script> </script>ic https://exa<script> </script>mple.org/', false],
        'encoded start' => ['&#64;alice &#35;topic &#104;ttps://example.org/', false],
        'named entities' => ['&commat;alice &num;topic https&colon;//example.org/', false],
        'encoded interior' => ['@ali&#99;e #top&#105;c https://exam&#112;le.org/', false],
        'hex entities' => ['@ali&#x63;e #top&#x69;c https://exam&#x70;le.org/', false],
        'escapes' => ['\\@alice \\#topic https://example\\.org/', false],
        'escaped interior' => ['@ali\\_ce #top\\_ic https://example.org/a\\_b', false],
        'zero width' => ["@ali\u200bce #top\u200bic https://exa\u200bmple.org/", false],
        'word joiner' => ["@ali\u2060ce #top\u2060ic https://exa\u2060mple.org/", false],
        'variation selector' => ["@ali\uFE0Fce #top\uFE0Fic https://exa\uFE0Fmple.org/", false],
        'encoded separator' => ['@ali&#32;ce #top&#32;ic https://example.org/&#32;path', false],
        'code' => ['<code>@alice #topic https://example.org/</code>', false],
        'preformatted' => ['<pre>@alice #topic https://example.org/</pre>', false],
        'attributes' => ['<span title="@alice #topic https://example.org/">label</span>', false],
        'explicit link' => ['<a href="https://explicit.example/">@alice #topic https://example.org/</a>', false, ['https://explicit.example/']],
        'unsafe link label' => ['<a href="javascript:alert(1)">@alice #topic https://example.org/</a>', false],
        'relative link label' => ['<a href="/relative">@alice #topic https://example.org/</a>', false],
      }
      if content_type == 'text/markdown'
        cases.merge!(
          'whole emphasis' => ['**@alice** *#topic* ~~https://example.org/~~', true],
          'internal emphasis' => ['@ali**ce** #top**ic** https://exa<em>mple</em>.org/', false],
          'inline code' => ['`@alice #topic https://example.org/`', false],
          'fenced code' => ["```\n@alice #topic https://example.org/\n```", false],
          'Markdown link' => ['[@alice #topic https://example.org/](https://explicit.example/)', false, ['https://explicit.example/']],
        )
      end

      cases.each do |label, (source, recognized, explicit_urls)|
        aggregate_failures(label) do
          formatter = formatter_for(source, content_type: content_type)
          accounts = []
          rewritten = formatter.rewrite_mentions do |match, acct|
            accounts << acct
            match
          end
          document = Nokogiri::HTML5.fragment(formatter.to_s)

          expect(rewritten).to eq source
          expect(accounts).to eq(recognized ? ['alice'] : [])
          expect(Extractor.extract_hashtags(formatter.entity_text)).to eq(recognized ? ['topic'] : [])
          expect(document.css('a.mention:not(.hashtag)').map(&:text)).to eq(recognized ? ['@alice'] : [])
          expect(document.css('a.hashtag').map(&:text)).to eq(recognized ? ['#topic'] : [])
          expect(formatter.urls.map(&:to_s)).to eq(explicit_urls || (recognized ? ['https://example.org/'] : []))
          expect(document.css('a:not(.mention)').map { |link| link['href'] }).to eq(explicit_urls || (recognized ? ['https://example.org/'] : []))
        end
      end
    end

    it "keeps encoded names literal beside the same unencoded names in #{content_type}" do
      source = '@alice &#64;alice @ali&#99;e #topic &#35;topic #top&#105;c https://example.org/ https://exam&#112;le.org/'
      formatter = formatter_for(source, content_type: content_type)
      accounts = []
      rewritten = formatter.rewrite_mentions do |_match, acct|
        accounts << acct
        '@bob'
      end
      document = Nokogiri::HTML5.fragment(formatter.to_s)

      expect(accounts).to eq ['alice']
      expect(rewritten).to eq source.sub('@alice', '@bob')
      expect(document.css('a.mention:not(.hashtag)').map(&:text)).to eq ['@alice']
      expect(document.css('a.hashtag').map(&:text)).to eq ['#topic']
      expect(formatter.urls.map(&:to_s)).to eq ['https://example.org/']
      expect(formatter.plain_text).to eq '@alice @alice @alice #topic #topic #topic https://example.org/ https://example.org/'
      expect(formatter_for('<svg><![CDATA[@alice]]></svg> @alice', content_type: content_type).entity_text).to eq '@alice'
    end

    it "only recognizes text with ordinary prose ancestors in #{content_type}" do
      body = '@alice #topic https://example.org/'
      [
        "<textarea>#{body}</textarea>",
        "<title>#{body}</title>",
        "<select><option>#{body}</option></select>",
        "<div><unknown><p><span>#{body}</span></p></unknown></div>",
        "<p><unknown><span>#{body}</span></unknown></p>",
        "<code><span>#{body}</span></code>",
      ].each do |source|
        formatter = formatter_for(source, content_type: content_type)
        document = Nokogiri::HTML5.fragment(formatter.to_s)
        accounts = []
        rewritten = formatter.rewrite_mentions do |match, acct|
          accounts << acct
          match
        end

        expect(accounts).to be_empty
        expect(rewritten).to eq source
        expect(formatter.entity_text).to eq ''
        expect(formatter.urls).to be_empty
        expect(document.css('a')).to be_empty
        expect(document.text.strip).to eq body
        expect(formatter.plain_text.strip).to eq body
      end

      formatter = formatter_for('<unknown><span><a href="https://example.org/">link</a></span></unknown>', content_type: content_type)
      expect(formatter.urls).to be_empty
    end

    it "retains native word boundaries at real whitespace in #{content_type}" do
      formatter = formatter_for("@alice ce #topic ic https://example.org/ tail\n@alice", content_type: content_type)
      accounts = []
      formatter.rewrite_mentions do |match, acct|
        accounts << acct
        match
      end

      expect(accounts).to eq %w(alice alice)
      expect(Extractor.extract_hashtags(formatter.entity_text)).to eq ['topic']
      expect(formatter.urls.map(&:to_s)).to eq ['https://example.org/']
    end
  end

  it 'normalizes rich-text mention domains for preloaded account matching' do
    remote = Fabricate.build(:account, username: 'sneak', domain: 'xn--hresiar-mxa.ch', url: 'https://example.org/@sneak')
    source = '<strong>@sneak@hæresiar.ch</strong>'
    document = Nokogiri::HTML5.fragment(format(source, preloaded_accounts: [remote]))

    expect(document.at_css('strong a.mention').text).to eq '@sneak'
  end

  it 'falls back to literal text when HTML exceeds the parser nesting limit' do
    text = ('<span>' * 600) + 'deep' + ('</span>' * 600)

    expect(Nokogiri::HTML5.fragment(format(text)).text).to include 'deep'
  end

  it 'keeps inline boundaries from creating partial mentions or email recipients' do
    [
      '@alice@<strong>remote.example</strong>',
      '@<b>alice</b>@remote.example',
      'word<strong>@alice</strong>.example',
      '<a href="https://example.com/">word</a>@alice',
      '@alice@<code>remote.example</code>',
      '@alice@<span></span>remote.example',
    ].each do |source|
      formatter = formatter_for("<p>#{source}</p>")

      expect { |callback| formatter.rewrite_mentions(&callback) }.not_to yield_control
      expect(Nokogiri::HTML5.fragment(format(formatter.text)).css('a.mention')).to be_empty
    end
  end

  it 'retains complete mentions, source order and Unicode offsets with inline context' do
    source = '<p>🍵 <b>@alice@remote.example</b> @alice @bob</p><p>@alice</p>word<br>@bob'
    accounts = []
    rewritten = formatter_for(source).rewrite_mentions do |_match, acct|
      accounts << acct
      "@#{acct == 'alice@remote.example' ? 'alice' : 'renamed_longer'}"
    end

    expect(accounts).to eq ['alice@remote.example', 'alice', 'bob', 'alice', 'bob']
    expect(rewritten).to eq '<p>🍵 <b>@alice</b> @renamed_longer @renamed_longer</p><p>@renamed_longer</p>word<br>@renamed_longer'
    expect(Nokogiri::HTML5.fragment(format('<p>🍵 <b>@alice</b></p>')).at_css('b a.mention').text).to eq '@alice'
  end

  it 'uses the same inline context for hashtags, autolinks and preview URL order' do
    formatter = formatter_for('<p>#top<b>ic</b> https://example.org/<b>secret</b> #whole</p><a href="https://explicit.example.org/">explicit</a> https://last.example.org/')
    document = Nokogiri::HTML5.fragment(format(formatter.text))

    expect(Extractor.extract_hashtags(formatter.entity_text)).to eq ['whole']
    expect(document.css('a.hashtag').map(&:text)).to eq ['#whole']
    expect(formatter.urls.map(&:to_s)).to eq ['https://explicit.example.org/', 'https://last.example.org/']
    expect(document.css('a').map { |node| node['href'] }).not_to include('https://example.org/')
  end

  it 'preserves leading preformatted newlines across repeated sanitization' do
    source = "<pre>\n\n\n\nx</pre>"
    expected = Nokogiri::HTML5.fragment(HtmlAwareFormatter.new(source, false).to_s).at_css('pre').text

    expect(Nokogiri::HTML5.fragment(format(source)).at_css('pre').text).to eq expected
  end
end
