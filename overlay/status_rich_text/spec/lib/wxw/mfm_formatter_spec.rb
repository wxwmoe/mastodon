# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wxw::MfmFormatter do
  let(:fence) { '<pre><code class="language-ruby">puts 1&#10;</code></pre>' }

  def convert(html)
    described_class.new(html).to_s
  end

  it 'keeps ordinary content on the HTML path and leaves the input unchanged' do
    expect(convert('<p>hello</p>')).to be_nil
    expect(convert('<pre><code>puts 1</code></pre>')).to be_nil
    expect(convert('<pre><code class="language-&quot;evil">puts 1</code></pre>')).to be_nil
    expect(convert('<p><b>bold</b><i>italic</i><small>small</small><del>deleted</del><a href="https://example.org">link</a><code>code</code></p>')).to be_nil
    expect(convert('<pre><code>&lt;h1&gt;heading&lt;/h1&gt;&lt;details&gt;body&lt;/details&gt;</code></pre><p>&lt;ol&gt;list&lt;/ol&gt;</p>')).to be_nil
    source = "<p>hello</p>#{fence}<p>after</p>".freeze

    expect(convert(source)).to eq "<plain>hello</plain>\n\n```ruby\nputs 1\n\n```\n\n<plain>after</plain>"
    expect(source).to include 'class="language-ruby"'
  end

  it 'maps heading sizes without introducing animations' do
    (1..6).each do |level|
      expect(convert("<h#{level}>Heading #{level}</h#{level}>")).to include "<plain>Heading #{level}</plain>"
    end
    headings = (1..6).map { |level| "<h#{level}>Heading #{level}</h#{level}>" }.join
    output = convert(headings)

    expect(output).to include '$[x2 <b><plain>Heading 1</plain></b>]', '$[x2 <b><plain>Heading 2</plain></b>]'
    expect(output).to include '<b><plain>Heading 3</plain></b>', '<b><plain>Heading 4</plain></b>'
    expect(output).to include '<small><b><plain>Heading 5</plain></b></small>', '<small><b><plain>Heading 6</plain></b></small>'
    expect(output).to_not include '$[x3', '$[x4', 'tada'
  end

  it 'preserves paragraphs, lists, numbering, and quotes' do
    html = '<ol start="3"><li>first<ul><li>nested</li></ul></li><li>second</li></ol><blockquote><p>one</p><p>two</p></blockquote>'
    output = convert(html)

    expect(convert('<ul><li>item</li></ul>')).to eq '• <plain>item</plain>'
    expect(convert('<ol><li>item</li></ol>')).to eq '1. <plain>item</plain>'
    expect(output).to include '3. <plain>first</plain>', '  • <plain>nested</plain>', '4. <plain>second</plain>'
    expect(output).to include "> <plain>one</plain>\n> \n> <plain>two</plain>"
  end

  it 'converts structured quotes while leaving plain quotes on the HTML path' do
    expect(convert('<blockquote>one<br>two</blockquote>')).to be_nil
    expect(convert("<blockquote>\n<p>one<br>two</p>\n</blockquote>")).to be_nil
    expect(convert('<blockquote><p>one</p><p>two</p></blockquote>')).to eq "> <plain>one</plain>\n> \n> <plain>two</plain>"
    expect(convert('<blockquote><a href="https://example.org">link</a><b>bold</b></blockquote>')).to include '[<plain>link</plain>](<https://example.org>)', '<b><plain>bold</plain></b>'
    expect(convert('<blockquote>outer<blockquote>inner</blockquote></blockquote>')).to include '> > <plain>inner</plain>'
  end

  it 'maps inline semantics and supported static styles while discarding unsupported CSS' do
    html = '<p><em>emphasis</em><del>deleted</del><span style="color: red; background-color: #abc; margin: 12px; font-size: 24px;">styled</span></p>'
    output = convert(html)

    expect(output).to include '<i><plain>emphasis</plain></i>', '<s><plain>deleted</plain></s>'
    expect(output).to include '$[bg.color=aabbcc $[fg.color=ff0000 <plain>styled</plain>]]'
    expect(output).to_not include 'style=', 'margin', 'font-size', '<span'
  end

  it 'keeps summary visible and blurs the complete details body including code and brackets' do
    html = '<details><summary>Open</summary><p>array[0]</p><pre><code>a&#10;  b</code></pre></details>'
    output = convert(html)

    expect(output).to start_with "<plain>Open</plain>\n$[blur "
    expect(output).to include '<plain>array[0]</plain>', '$[font.monospace <plain>a</plain>'
    expect(output).to include '<plain>  b</plain>'
    expect(output).to_not include '```', '<details>', '<summary>'
    expect(convert('<details>body</details>')).to eq '$[blur <plain>body</plain>]'
    expect(convert('<summary>Open</summary>')).to eq '<plain>Open</plain>'
  end

  it 'centers prose and keeps block code outside inline-only wrappers' do
    output = convert('<div style="text-align: center; color: red;"><p>centered</p></div>')
    expect(output).to include "<center>\n$[fg.color=ff0000 <plain>centered</plain>]\n</center>"

    output = convert('<div style="text-align: center; color: red;">' + fence + '</div>')
    expect(output).to include "```ruby\nputs 1\n\n```"
    expect(output).to_not include '$[fg', '<center>'
    expect(convert('<p style="text-align: center; text-align: left;">left</p>' + fence)).to_not include '<center>'
    expect(convert('<div style="text-align: center;"></div>' + fence)).to_not include '<center>'
    expect(convert('<p style="text-align: center;">centered</p>')).to eq "<center>\n<plain>centered</plain>\n</center>"
  end

  it 'triggers only for static styles that are actually rendered' do
    {
      'color: red;' => '$[fg.color=ff0000 ',
      'background-color: #abc;' => '$[bg.color=aabbcc ',
      'font-family: monospace;' => '$[font.monospace ',
      'font-weight: bold;' => '<b>',
      'font-style: italic;' => '<i>',
      'text-decoration-line: line-through;' => '<s>',
      'border-style: solid; border-width: 1px;' => '$[border.style=solid,width=1 ',
    }.each do |style, prefix|
      expect(convert("<span style=\"#{style}\">styled</span>")).to start_with prefix
    end

    [
      '<span style="color: invalid; background-color: url(https://example.org);">plain</span>',
      '<span style="margin: 12px; font-size: 24px; border-width: 1px;">plain</span>',
      '<span style="color: red; color: currentcolor;">plain</span>',
      '<p style="text-align: center; text-align: left;">plain</p>',
      '<span style="color: red;"></span><div style="text-align: center;"></div>',
      '<code style="color: red;">plain</code><kbd style="color: red;">plain</kbd>',
      '<blockquote style="color: red;">plain</blockquote>',
      '<div style="color: red; text-align: center;"><pre><code>plain</code></pre></div>',
      '<b>' * 16 + '<span style="color: red; text-align: center;">deep</span>' + '</b>' * 16,
    ].each do |html|
      expect(convert(html)).to be_nil, html
    end
  end

  it 'preserves inline backticks and colliding block fences as literal monospace text' do
    %w(a`b a´b a&#10;b a&#13;b).each do |content|
      expect(convert("<code>#{content}</code>")).to start_with '$[font.monospace '
    end
    html = '<pre><code>before&#10;```&#10;**after**</code></pre>'
    output = convert(html)

    expect(output).to include '$[font.monospace <plain>before</plain>', '<plain>```</plain>', '<plain>**after**</plain>'
    expect(output).to_not start_with '```'
  end

  it 'protects literal MFM, plain closing tags, unlinked mentions, and search syntax' do
    html = '<p>hello Search</p><p>$[spin x] @unlinked #tag :undeclared:</p><p>&lt;/plain&gt;</p>'
    output = convert(html + fence)

    expect(output).to include '<plain>hello Search</plain>', '<plain>$[spin x] @unlinked #tag </plain>', '<plain>:undeclared:</plain>'
    expect(output).to include '<plain><</plain><plain>/plain></plain>'
  end

  it 'preserves explicit line breaks within inline presentation' do
    expect(convert('<p>before<b>line<br></b>after</p>' + fence)).to include "<plain>before</plain><b><plain>line</plain>\n</b><plain>after</plain>"
    expect(convert('<p><code>&#13;</code></p>' + fence)).to start_with "$[font.monospace \n]"
    expect(convert('<pre><code class="language-text">a&#13;b&#13;&#10;</code></pre>')).to eq "```text\na\nb\n\n```"
  end

  it 'preserves ordinary link labels and URL delimiters without creating mentions' do
    html = '<a href="https://example.org/a(b)?x=[y]">@home@away@lost</a>'
    expect(convert(html + fence)).to include '[<plain>@home@away@lost</plain>](<https://example.org/a(b)?x=[y]>)'
    expect(convert('<a href="gemini://example.org/page">Capsule</a>' + fence)).to include '<plain>Capsule</plain> (<plain>gemini://example.org/page</plain>)'
  end

  it 'keeps unsupported elements and complex ruby readable' do
    html = '<u>underlined</u><ruby>漢字<rt>かんじ</rt></ruby><ruby>A<rt>a</rt>B B<rt>bb</rt></ruby><small>small</small>'
    output = convert(html + fence)

    expect(output).to include '<plain>underlined</plain>', '$[ruby 漢字 かんじ]', '<plain>A</plain> (<plain>a</plain>)<plain>B B</plain> (<plain>bb</plain>)'
    expect(output).to include '<small><plain>small</plain></small>'
    expect(output).to_not include '<u>', '<ruby>', '<rt>'
  end

  it 'caps presentation nesting without dropping text or exposing literal wrappers' do
    html = '<b style="color: red; background-color: blue;">' * 30 + 'deep[]' + '</b>' * 30
    output = convert(html + fence)

    expect(output).to include '<plain>deep[]</plain>'
    expect(output.scan('$[fg').size).to be <= 5
    expect(output).to_not include "\0"
  end
end
