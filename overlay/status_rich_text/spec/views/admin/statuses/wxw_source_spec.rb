# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'admin/statuses/_wxw_source.html.haml' do
  it 'shows saved HTML as escaped source without running it through the formatter' do
    source = "<p onclick=\"alert(1)\">Original &amp; text</p>\n</code></pre><script>alert(1)</script>"
    status = Fabricate.build(:status, text: source, wxw_content_type: 'text/html')

    render partial: 'admin/statuses/wxw_source', locals: { status: status }

    document = Nokogiri::HTML5.fragment(rendered)
    expect(document.at_css('pre code').text).to eq source
    expect(document.css('script, [onclick]')).to be_empty
  end

  it 'preserves Markdown syntax and whitespace' do
    source = "# Heading\n\n```ruby\n  puts '<tag>'\n```"
    status = Fabricate.build(:status, text: source, wxw_content_type: 'text/markdown')

    render partial: 'admin/statuses/wxw_source', locals: { status: status }

    expect(Nokogiri::HTML5.fragment(rendered).at_css('pre code').text).to eq source
  end

  it 'omits the source section for plain text' do
    render partial: 'admin/statuses/wxw_source', locals: { status: Fabricate.build(:status, text: 'Plain text') }

    expect(rendered.strip).to be_empty
  end
end
