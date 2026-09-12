# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'HTML statuses' do
  include_context 'with API authentication', oauth_scopes: 'read:statuses write:statuses'

  it 'preserves static styles and details through posting, federation, editing, history, and redrafting' do
    original = '<div style="text-align: center;"><h1 style="color: red;">Original</h1></div><p><abbr title="Hypertext Markup Language">HTML</abbr> H<sub>2</sub>O</p>' \
               '<details><summary>More</summary><p style="padding: 4px;">Original body</p></details>'
    edited = '<h5 style="font-weight: 700;">Updated</h5><blockquote>Changed x<sup>2</sup> <code>code</code></blockquote>' \
             '<details><summary>Changed</summary><dl><dt>Term</dt><dd style="background-color: #ffeecc;">Definition</dd></dl></details>'

    post '/api/v1/statuses', headers: headers, params: { status: original, content_type: 'text/html' }

    expect(response).to have_http_status(200)
    expect(response.parsed_body[:content]).to eq original
    expect(response.parsed_body).to_not have_key(:content_type)
    status = user.account.statuses.find(response.parsed_body[:id])
    expect(status.text).to eq original
    expect(status.wxw_content_type).to eq 'text/html'
    expect(serialized_record_json(status, ActivityPub::NoteSerializer, adapter: ActivityPub::Adapter)['content']).to eq original
    expect(serialized_record_json(status, ActivityPub::NoteSerializer, adapter: ActivityPub::Adapter)).to_not have_key('source')

    get "/api/v1/statuses/#{status.id}/source", headers: headers

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to include(text: original, content_type: 'text/html')

    put "/api/v1/statuses/#{status.id}", headers: headers, params: { status: edited }

    expect(response).to have_http_status(200)
    expect(status.reload.text).to eq edited
    expect(response.parsed_body[:content]).to eq edited
    expect(serialized_record_json(status, ActivityPub::NoteSerializer, adapter: ActivityPub::Adapter)['content']).to eq edited
    expect(status.edits.ordered.pluck(:text)).to eq [original, edited]
    expect(status.edits.ordered.map(&:wxw_content_type)).to eq ['text/html', 'text/html']

    get "/api/v1/statuses/#{status.id}/history", headers: headers

    expect(response).to have_http_status(200)
    expect(response.parsed_body.pluck(:content)).to eq [original, edited]

    delete "/api/v1/statuses/#{status.id}", headers: headers

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to include(text: edited, content_type: 'text/html')
  end

  it 'keeps ordinary Markdown syntax as plain text' do
    post '/api/v1/statuses', headers: headers, params: { status: '**Bold** and *italic*' }

    expect(response).to have_http_status(200)
    expect(response.parsed_body[:content]).to eq '<p>**Bold** and *italic*</p>'
    status = user.account.statuses.find(response.parsed_body[:id])
    expect(status.text).to eq '**Bold** and *italic*'
    expect(serialized_record_json(status, ActivityPub::NoteSerializer, adapter: ActivityPub::Adapter)).to_not have_key('source')
  end

  it 'federates the original Markdown source beside rendered HTML for quotes and polls through edits' do
    quoted = Fabricate(:status, account: user.account)
    original = "**中文**\nnext  \n![alt](https://example.org/image.png)"
    edited = "##### Updated\n\n```ruby\nline 1\nline 2\n```"
    variants = {
      'Note' => { quoted_status_id: quoted.id },
      'Question' => { poll: { options: %w(First Second), expires_in: 3600 } },
    }

    variants.each do |type, options|
      post '/api/v1/statuses', headers: headers, params: { status: original, content_type: 'text/markdown' }.merge(options)

      expect(response).to have_http_status(200)
      status = user.account.statuses.find(response.parsed_body[:id])
      note = serialized_record_json(status, ActivityPub::NoteSerializer, adapter: ActivityPub::Adapter)
      expect(note['type']).to eq type
      expect(note['source']).to eq('content' => original, 'mediaType' => 'text/markdown')
      expect(note['content']).to eq response.parsed_body[:content]
      expect(Nokogiri::HTML5.fragment(note['content']).at_css('strong').text).to eq '中文'
      expect(note['quote']).to eq ActivityPub::TagManager.instance.uri_for(quoted) if type == 'Note'
      expect(status.text).to eq original
      expect(response.parsed_body).to_not have_key(:source)
      activity = serialized_record_json(status, ActivityPub::CreateNoteSerializer, adapter: ActivityPub::Adapter)
      expect(activity.dig('object', 'source')).to eq note['source']
      expect(activity.dig('object', 'content')).to eq note['content']

      put "/api/v1/statuses/#{status.id}", headers: headers, params: options.merge(status: edited)

      expect(response).to have_http_status(200)
      note = serialized_record_json(status.reload, ActivityPub::NoteSerializer, adapter: ActivityPub::Adapter)
      expect(note['type']).to eq type
      expect(note['source']).to eq('content' => edited, 'mediaType' => 'text/markdown')
      expect(note['content']).to eq response.parsed_body[:content]
      expect(Nokogiri::HTML5.fragment(note['content']).at_css('pre code').text).to eq "line 1\nline 2\n"
      expect(Nokogiri::HTML5.fragment(note['content']).at_css('pre code')['class']).to eq 'language-ruby'
      expect(status.text).to eq edited
      activity = serialized_record_json(status, ActivityPub::UpdateNoteSerializer, adapter: ActivityPub::Adapter)
      expect(activity.dig('object', 'source')).to eq note['source']
      expect(activity.dig('object', 'content')).to eq note['content']
    end
  end

  %w(plain markdown html).each do |format|
    it "stores and links the canonical account when a #{format} mention resolves through a WebFinger alias" do
      recipient = Fabricate(:account, username: 'canonical', domain: 'remote.example', protocol: :activitypub, uri: 'https://remote.example/users/canonical', url: 'https://remote.example/@canonical')
      allow_any_instance_of(ResolveAccountService).to receive(:call).with('alias@alias.example').and_return(recipient)
      source = { 'plain' => '@alias@alias.example hello', 'markdown' => '**@alias@alias.example** hello', 'html' => '<b>@alias@alias.example</b> hello' }.fetch(format)
      normalized = source.sub('@alias@alias.example', '@canonical@remote.example')

      post '/api/v1/statuses', headers: headers, params: { status: source, content_type: "text/#{format}" }

      expect(response).to have_http_status(200)
      status = user.account.statuses.find(response.parsed_body[:id])
      expect(status.text).to eq normalized
      expect(status.active_mentions.pluck(:account_id)).to eq [recipient.id]
      expect(Nokogiri::HTML5.fragment(response.parsed_body[:content]).at_css('a.mention')['href']).to eq recipient.url

      put "/api/v1/statuses/#{status.id}", headers: headers, params: { status: "#{source} updated" }

      expect(response).to have_http_status(200)
      expect(status.reload.text).to eq "#{normalized} updated"

      get "/api/v1/statuses/#{status.id}/source", headers: headers

      expect(response.parsed_body).to include(text: "#{normalized} updated", content_type: "text/#{format}")
    end
  end

  it 'changes only the format when an edit omits the source' do
    source = '**Bold**'
    media = Fabricate(:media_attachment, account: user.account)
    post '/api/v1/statuses', headers: headers, params: { status: source, content_type: 'text/markdown', spoiler_text: 'Warning', sensitive: true, media_ids: [media.id] }
    status = user.account.statuses.find(response.parsed_body[:id])

    put "/api/v1/statuses/#{status.id}", headers: headers, params: { content_type: 'text/plain' }

    expect(response).to have_http_status(200)
    expect(status.reload.text).to eq source
    expect(status.wxw_content_type).to eq 'text/plain'
    expect(status.spoiler_text).to eq 'Warning'
    expect(status.sensitive).to be true
    expect(status.media_attachments.pluck(:id)).to eq [media.id]
    expect(status.edited_at).to be_present
    expect(response.parsed_body[:content]).to eq '<p>**Bold**</p>'
    expect(status.edits.ordered.map(&:wxw_content_type)).to eq %w(text/markdown text/plain)
    expect(status.edits.ordered.pluck(:text)).to eq [source, source]
  end

  %w(text/html text/markdown).each do |content_type|
    it "keeps an unchanged media-only #{content_type} edit out of history" do
      media = Fabricate(:media_attachment, account: user.account)
      post '/api/v1/statuses', headers: headers, params: { status: '', content_type: content_type, media_ids: [media.id] }

      expect(response).to have_http_status(200)
      status = user.account.statuses.find(response.parsed_body[:id])
      expect(status.wxw_content_type).to eq content_type

      [{ content_type: content_type }, {}].each do |format_options|
        expect do
          put "/api/v1/statuses/#{status.id}", headers: headers, params: { status: '', media_ids: [media.id], language: status.language }.merge(format_options)
        end.to_not change { status.edits.count }

        expect(response).to have_http_status(200)
        expect(status.reload.text).to eq ''
        expect(status.wxw_content_type).to eq content_type
        expect(status.edited_at).to be_nil
      end

      get "/api/v1/statuses/#{status.id}/source", headers: headers

      expect(response.parsed_body).to include(text: '', spoiler_text: '', content_type: content_type)
    end

    it "preserves stored #{content_type} when editing media and a literal content warning" do
      media = Fabricate(:media_attachment, account: user.account)
      replacement = Fabricate(:media_attachment, account: user.account)
      warning = '<b>literal</b> & **plain**'
      post '/api/v1/statuses', headers: headers, params: { status: '', content_type: content_type, media_ids: [media.id] }

      expect(response).to have_http_status(200)
      status = user.account.statuses.find(response.parsed_body[:id])
      user.settings['wxw_default_post_format'] = 'plain'
      user.save!

      put "/api/v1/statuses/#{status.id}", headers: headers, params: { status: '', spoiler_text: warning, media_ids: [media.id], content_type: content_type }

      expect(response).to have_http_status(200)
      expect(status.reload.text).to eq ''
      expect(status.spoiler_text).to eq warning
      expect(status.wxw_content_type).to eq content_type
      expect(status.sensitive).to be true
      expect(status.edits.ordered.pluck(:text, :spoiler_text)).to eq [['', ''], ['', warning]]

      put "/api/v1/statuses/#{status.id}", headers: headers, params: { status: '', spoiler_text: warning, media_ids: [replacement.id] }

      expect(response).to have_http_status(200)
      expect(status.reload.text).to eq ''
      expect(status.spoiler_text).to eq warning
      expect(status.wxw_content_type).to eq content_type
      expect(status.ordered_media_attachments.map(&:id)).to eq [replacement.id]
      expect(response.parsed_body[:media_attachments].pluck(:id)).to eq [replacement.id.to_s]
      expect(status.edits.ordered.map(&:wxw_content_type)).to eq [content_type] * 3
      expect(status.edits.ordered.pluck(:text)).to eq ['', '', '']

      get "/api/v1/statuses/#{status.id}/source", headers: headers

      expect(response.parsed_body).to include(text: '', spoiler_text: warning, content_type: content_type)
    end

    it "changes an empty #{content_type} body only when a new format is explicitly selected" do
      media = Fabricate(:media_attachment, account: user.account)
      post '/api/v1/statuses', headers: headers, params: { status: '', content_type: content_type, media_ids: [media.id] }

      expect(response).to have_http_status(200)
      status = user.account.statuses.find(response.parsed_body[:id])

      put "/api/v1/statuses/#{status.id}", headers: headers, params: { status: '', content_type: 'text/plain', media_ids: [media.id] }

      expect(response).to have_http_status(200)
      expect(status.reload.text).to eq ''
      expect(status.wxw_content_type).to eq 'text/plain'
      expect(status.edits.ordered.map(&:wxw_content_type)).to eq [content_type, 'text/plain']
      expect(status.edits.ordered.pluck(:text)).to eq ['', '']
    end
  end

  it 'preserves Markdown source and snapshots its format through edits and redrafting' do
    original = "# Original\n\n<abbr title=\"Hypertext Markup Language\">HTML</abbr> H<sub>2</sub>O"
    edited = "##### Updated\n\nx<sup>2</sup>"
    original_html = '<h1>Original</h1><p><abbr title="Hypertext Markup Language">HTML</abbr> H<sub>2</sub>O</p>'
    edited_html = '<h5>Updated</h5><p>x<sup>2</sup></p>'

    post '/api/v1/statuses', headers: headers, params: { status: original, content_type: 'text/markdown' }

    expect(response).to have_http_status(200)
    status = user.account.statuses.find(response.parsed_body[:id])
    expect(status.text).to eq original
    expect(status.wxw_content_type).to eq 'text/markdown'
    expect(response.parsed_body[:content]).to eq original_html
    expect(serialized_record_json(status, ActivityPub::NoteSerializer, adapter: ActivityPub::Adapter)['content']).to eq original_html

    get "/api/v1/statuses/#{status.id}/source", headers: headers

    expect(response.parsed_body).to include(text: original, content_type: 'text/markdown')

    user.settings['wxw_default_post_format'] = 'html'
    user.save!
    put "/api/v1/statuses/#{status.id}", headers: headers, params: { status: edited }

    expect(response).to have_http_status(200)
    expect(status.reload.text).to eq edited
    expect(status.wxw_content_type).to eq 'text/markdown'
    expect(response.parsed_body[:content]).to eq edited_html
    expect(serialized_record_json(status, ActivityPub::NoteSerializer, adapter: ActivityPub::Adapter)['content']).to eq edited_html

    expect do
      put "/api/v1/statuses/#{status.id}", headers: headers, params: { status: edited, content_type: 'text/plain' }
    end.to change { status.edits.count }.by(1)

    expect(response).to have_http_status(200)
    expect(status.reload.text).to eq edited
    expect(status.wxw_content_type).to eq 'text/plain'
    expect(response.parsed_body[:content]).to eq TextFormatter.new(edited).to_s
    expect(status.edits.ordered.pluck(:text)).to eq [original, edited, edited]
    expect(status.edits.ordered.map(&:wxw_content_type)).to eq ['text/markdown', 'text/markdown', 'text/plain']

    get "/api/v1/statuses/#{status.id}/history", headers: headers

    expect(response).to have_http_status(200)
    expect(response.parsed_body.pluck(:content)).to eq [original_html, edited_html, TextFormatter.new(edited).to_s]

    put "/api/v1/statuses/#{status.id}", headers: headers, params: { status: edited, content_type: 'text/markdown' }

    expect(response).to have_http_status(200)

    delete "/api/v1/statuses/#{status.id}", headers: headers

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to include(text: edited, content_type: 'text/markdown')
  end

  it 'uses the account Markdown default and retains the format even for unformatted source' do
    user.settings['wxw_default_post_format'] = 'markdown'
    user.save!

    post '/api/v1/statuses', headers: headers, params: { status: '**Bold** and *italic*' }

    expect(response).to have_http_status(200)
    status = user.account.statuses.find(response.parsed_body[:id])
    expect(status.text).to eq '**Bold** and *italic*'
    expect(status.wxw_content_type).to eq 'text/markdown'
    expect(response.parsed_body[:content]).to include '<strong>Bold</strong> and <em>italic</em>'

    post '/api/v1/statuses', headers: headers, params: { status: "ordinary\n\ntext" }

    expect(response).to have_http_status(200)
    status = user.account.statuses.find(response.parsed_body[:id])
    expect(status.text).to eq "ordinary\n\ntext"
    expect(status.wxw_content_type).to eq 'text/markdown'
  end

  it 'honors explicit formats over the account default through posting and editing' do
    user.settings['wxw_default_post_format'] = 'markdown'
    user.save!
    source = '<b>literal</b> & **plain**'
    escaped = '<p>&lt;b&gt;literal&lt;/b&gt; &amp; **plain**</p>'

    post '/api/v1/statuses', headers: headers, params: { status: source, content_type: 'text/plain' }

    expect(response).to have_http_status(200)
    status = user.account.statuses.find(response.parsed_body[:id])
    expect(status.text).to eq source
    expect(status.wxw_content_type).to eq 'text/plain'
    expect(response.parsed_body[:content]).to eq escaped

    put "/api/v1/statuses/#{status.id}", headers: headers, params: { status: '**plain** <b>HTML</b>', content_type: 'text/plain' }

    expect(response).to have_http_status(200)
    expect(status.reload.text).to eq '**plain** <b>HTML</b>'
    expect(response.parsed_body[:content]).to eq '<p>**plain** &lt;b&gt;HTML&lt;/b&gt;</p>'
    expect(status.wxw_content_type).to eq 'text/plain'

    put "/api/v1/statuses/#{status.id}", headers: headers, params: { status: '**Rich**', content_type: 'text/markdown' }

    expect(response).to have_http_status(200)
    expect(status.reload.text).to eq '**Rich**'
    expect(status.wxw_content_type).to eq 'text/markdown'
    expect(response.parsed_body[:content]).to include '<strong>Rich</strong>'
    expect(status.edits.ordered.pluck(:text)).to eq [source, '**plain** <b>HTML</b>', '**Rich**']
    expect(status.edits.ordered.map(&:wxw_content_type)).to eq ['text/plain', 'text/plain', 'text/markdown']
  end

  it 'keeps Markdown direct messages addressed to complete underscored usernames' do
    other = Fabricate(:user, account: Fabricate(:account, username: 'foo')).account
    emoji = Fabricate(:custom_emoji, shortcode: 'blob_cat_hug')

    %w(foo_bar_baz _foo_ foo__bar__baz).each do |username|
      intended = Fabricate(:user, account: Fabricate(:account, username: username)).account
      source = "**Private** @#{username} :blob_cat_hug: #hello_world_again"

      post '/api/v1/statuses', headers: headers, params: { status: source, content_type: 'text/markdown', visibility: 'direct' }

      expect(response).to have_http_status(200)
      status = user.account.statuses.find(response.parsed_body[:id])
      expect(status.active_mentions.pluck(:account_id)).to contain_exactly(intended.id)
      expect(StatusPolicy.new(intended, status).show?).to be true
      expect(StatusPolicy.new(other, status).show?).to be false
      expect(status.emojis).to contain_exactly(emoji)
      expect(status.tags.pluck(:name)).to contain_exactly('hello_world_again')
    end
  end

  it 'escapes HTML under the plain default and allows an explicit HTML override' do
    user.settings['wxw_default_post_format'] = 'plain'
    user.save!

    post '/api/v1/statuses', headers: headers, params: { status: '<b>literal</b>' }

    expect(response).to have_http_status(200)
    expect(user.account.statuses.find(response.parsed_body[:id]).text).to eq '<b>literal</b>'
    expect(response.parsed_body[:content]).to eq '<p>&lt;b&gt;literal&lt;/b&gt;</p>'

    post '/api/v1/statuses', headers: headers, params: { status: '<b>bold</b>', content_type: 'text/html' }

    expect(response).to have_http_status(200)
    expect(user.account.statuses.find(response.parsed_body[:id]).text).to eq '<b>bold</b>'
    expect(response.parsed_body[:content]).to eq '<b>bold</b>'
  end

  it 'rejects invalid explicit formats without posting' do
    ['markdown', 'text/xml', '', nil, { value: 'text/plain' }].each do |content_type|
      expect do
        post '/api/v1/statuses', headers: headers, params: { status: 'text', content_type: content_type }, as: :json
      end.to_not change(Status, :count)

      expect(response).to have_http_status(422)
    end
  end

  it 'schedules Markdown source with its resolved format and excludes nonliteral entities when published' do
    user.settings['wxw_default_post_format'] = 'markdown'
    user.save!
    skipped = Fabricate(:account, username: 'markdownskip')
    partial = Fabricate(:account, username: 'markdown')
    source = "**Future**\n\n```\n@markdownskip #CodeTag\n```\n\n&#64;markdownskip @markdown<!-- gap -->skip #Enc&#111;ded #Split<font>Tag</font>"

    post '/api/v1/statuses', headers: headers, params: { status: source, scheduled_at: 1.hour.from_now.iso8601 }

    expect(response).to have_http_status(200)
    scheduled = ScheduledStatus.find(response.parsed_body[:id])
    expect(scheduled.params).to include('text' => source, 'content_type' => 'text/markdown')

    user.settings['wxw_default_post_format'] = 'plain'
    user.save!

    PublishScheduledStatusWorker.new.perform(scheduled.id)

    status = user.account.statuses.first
    expect(status.text).to eq source
    expect(status.wxw_content_type).to eq 'text/markdown'
    expect(status.active_mentions.pluck(:account_id)).to_not include(skipped.id, partial.id)
    expect(status.active_mentions).to be_empty
    expect(status.tags).to be_empty
    html = serialized_record_json(status, ActivityPub::NoteSerializer, adapter: ActivityPub::Adapter)['content']
    expect(Nokogiri::HTML5.fragment(html).at_css('strong').text).to eq 'Future'
    expect(Nokogiri::HTML5.fragment(html).at_css('code').text).to eq "@markdownskip #CodeTag\n"
  end

  it 'stores plain text without wrappers and preserves escaped HTML literals through edits and federation' do
    sources = ["plain &amp; text\nnext", '<p>&lt;b&gt;literal&lt;/b&gt; &amp; &amp;lt;b&amp;gt;</p>', 'plain again']

    post '/api/v1/statuses', headers: headers, params: { status: sources.first }

    expect(response).to have_http_status(200)
    status = user.account.statuses.find(response.parsed_body[:id])

    sources.each_with_index do |source, index|
      put "/api/v1/statuses/#{status.id}", headers: headers, params: { status: source } unless index.zero?

      expect(response).to have_http_status(200)
      expect(status.reload.text).to eq source
      expected_html = TextFormatter.new(source).to_s
      expect(response.parsed_body[:content]).to eq expected_html
      expect(serialized_record_json(status, ActivityPub::NoteSerializer, adapter: ActivityPub::Adapter)['content']).to eq expected_html

      get "/api/v1/statuses/#{status.id}/source", headers: headers

      expect(response.parsed_body).to include(text: source, content_type: 'text/plain')
    end

    expect(status.edits.ordered.pluck(:text)).to eq sources
  end

  it 'emits ActivityPub HTML that the shared Mastodon sanitizer preserves' do
    source = '<p><b>b</b><strong>strong</strong><i>i</i><em>em</em><u>u</u><s>s</s><del>del</del><br><span>span</span><code>code</code></p>' \
             '<pre>pre</pre><blockquote>quote</blockquote><ul><li>item</li></ul><ol start="2"><li value="3">item</li></ol>' \
             '<p><ruby>word<rp>(</rp><rt>reading</rt><rp>)</rp></ruby><a href="https://example.org/">link</a></p>' \
             '<h1>one</h1><h2>two</h2><h3>three</h3><h4>four</h4><h5>five</h5><h6>six</h6><p><abbr title="Hypertext Markup Language">HTML</abbr> H<sub>2</sub>O x<sup>2</sup></p>' \
             '<p><small>small</small><wbr><time datetime="2026-09-12">time</time><mark>mark</mark><kbd>kbd</kbd><ins>ins</ins></p><hr>' \
             '<hgroup><h2>group</h2><p>subtitle</p></hgroup><header>header</header><footer>footer</footer>' \
             '<dl><dt>term</dt><dd>definition</dd></dl><details><summary>summary</summary><p>detail</p></details>' \
             '<div style="text-align: center;">centered</div>'

    post '/api/v1/statuses', headers: headers, params: { status: source, content_type: 'text/html' }

    expect(response).to have_http_status(200)
    status = user.account.statuses.find(response.parsed_body[:id])
    note = serialized_record_json(status, ActivityPub::NoteSerializer, adapter: ActivityPub::Adapter)
    document = Nokogiri::HTML5.fragment(note['content'])

    expect(note['content']).to eq response.parsed_body[:content]
    expect(HtmlAwareFormatter.new(note['content'], false).to_s).to eq note['content']
    expect(document.css('*').map(&:name).uniq).to match_array(Sanitize::Config::MASTODON_STRICT[:elements])
    expect(document.at_css('div')['style']).to eq 'text-align: center;'
    expect(document.at_css('div').text).to eq 'centered'
    expect(status.reload.text).to eq source
  end

  it 'filters executable markup, unsafe inline styles, and unsafe link protocols' do
    source = '<p style="position:fixed" onclick="alert(1)"><strong>Safe</strong><script>alert(2)</script><style>p{display:none}</style>' \
             '<img src="x" onerror="alert(3)"><a href="javascript:alert(4)">unsafe link</a></p>'

    post '/api/v1/statuses', headers: headers, params: { status: source, content_type: 'text/html' }

    expect(response).to have_http_status(200)
    html = response.parsed_body[:content]
    document = Nokogiri::HTML5.fragment(html)

    expect(document.css('script, style, img, [style], [onclick], [onerror], a[href^="javascript:"]')).to be_empty
    expect(document.at_css('strong').text).to eq 'Safe'
    expect(HtmlAwareFormatter.new(html, false).to_s).to eq html
    status = user.account.statuses.find(response.parsed_body[:id])
    expect(status.text).to eq source

    edited = '<a href="javascript:alert(1)">&lt;b&gt;literal&lt;/b&gt; &amp;</a>'
    put "/api/v1/statuses/#{status.id}", headers: headers, params: { status: edited }

    expect(response).to have_http_status(200)
    expect(status.reload.text).to eq edited
    expect(response.parsed_body[:content]).to eq Sanitize.fragment(edited, Sanitize::Config::MASTODON_STRICT)
    expect(Nokogiri::HTML5.fragment(response.parsed_body[:content]).text).to eq '<b>literal</b> &'
    expect(status.edits.ordered.last.text).to eq edited
  end

  it 'links prose entities without mentioning or tagging code and HTML attributes' do
    mentioned = Fabricate(:account, username: 'htmlprose')
    skipped = Fabricate(:account, username: 'htmlskip')
    source = '<p>@htmlprose #PublicTag https://example.org/prose</p>' \
             '<pre>@htmlskip #PreTag https://example.org/pre</pre>' \
             '<code>@htmlskip #CodeTag https://example.org/code</code>' \
             '<a href="https://example.org/?user=@htmlskip#AttrTag" title="@htmlskip #AttrTag">link</a>'

    post '/api/v1/statuses', headers: headers, params: { status: source, content_type: 'text/html' }

    expect(response).to have_http_status(200)
    status = user.account.statuses.find(response.parsed_body[:id])
    document = Nokogiri::HTML5.fragment(response.parsed_body[:content])

    expect(status.text).to eq source
    expect(status.active_mentions.pluck(:account_id)).to contain_exactly(mentioned.id)
    expect(status.active_mentions.pluck(:account_id)).to_not include(skipped.id)
    expect(status.tags.pluck(:name)).to contain_exactly('publictag')
    expect(document.css('pre a, code a, a a')).to be_empty
    expect(document.at_css('pre').text).to eq '@htmlskip #PreTag https://example.org/pre'
    expect(document.at_css('code').text).to eq '@htmlskip #CodeTag https://example.org/code'
    expect(document.css('p a').map { |link| link['href'] }).to include('https://example.org/prose')

    put "/api/v1/statuses/#{status.id}", headers: headers, params: { status: '<code>@htmlprose @htmlskip #PublicTag #CodeTag</code>' }

    expect(response).to have_http_status(200)
    expect(status.reload.active_mentions).to be_empty
    expect(status.tags).to be_empty
    expect(Nokogiri::HTML5.fragment(response.parsed_body[:content]).css('code a')).to be_empty
  end

  it 'retains native mention, hashtag, and link handling for plain-text posts' do
    mentioned = Fabricate(:account, username: 'plainprose')
    source = '@plainprose #PlainTag https://example.org/plain'

    post '/api/v1/statuses', headers: headers, params: { status: source }

    expect(response).to have_http_status(200)
    status = user.account.statuses.find(response.parsed_body[:id])

    expect(status.text).to eq source
    expect(status.active_mentions.pluck(:account_id)).to contain_exactly(mentioned.id)
    expect(status.tags.pluck(:name)).to contain_exactly('plaintag')
    expect(response.parsed_body[:content]).to eq TextFormatter.new(source, preloaded_accounts: [mentioned]).to_s
  end

  it 'stores scheduled HTML source and sanitizes it when published' do
    source = '<p style="color:RED;position:fixed"><strong>Future</strong><script>hidden</script></p>'
    sanitized = '<p style="color: red;"><strong>Future</strong></p>'

    post '/api/v1/statuses', headers: headers, params: { status: source, content_type: 'text/html', scheduled_at: 1.hour.from_now.iso8601 }

    expect(response).to have_http_status(200)
    expect(response.parsed_body[:params]).to include(text: source, content_type: 'text/html')
    scheduled_id = response.parsed_body[:id]

    PublishScheduledStatusWorker.new.perform(scheduled_id)

    expect(ScheduledStatus.find_by(id: scheduled_id)).to be_nil
    status = user.account.statuses.first
    expect(status.text).to eq source
    expect(status.wxw_content_type).to eq 'text/html'
    expect(serialized_record_json(status, ActivityPub::NoteSerializer, adapter: ActivityPub::Adapter)['content']).to eq sanitized
  end

  it 'keeps received remote HTML on the original sanitization path' do
    source = '<h3>Remote</h3><p onclick="alert(1)">@unlinked #Unlinked <abbr title="Hypertext Markup Language">HTML</abbr> x<sup>2</sup><script>hidden</script></p>' \
             '<details style="color:RED;position:fixed"><summary>More</summary><p><time datetime="2026-09-12">today</time> body</p></details>'
    status = Fabricate(:status, account: Fabricate(:account, domain: 'remote.example'), text: source)

    get "/api/v1/statuses/#{status.id}", headers: headers

    expect(response).to have_http_status(200)
    expect(status.reload.text).to eq source
    expect(response.parsed_body[:content]).to eq HtmlAwareFormatter.new(source, false).to_s
    expect(serialized_record_json(status, ActivityPub::NoteSerializer, adapter: ActivityPub::Adapter)).to_not have_key('source')
    document = Nokogiri::HTML5.fragment(response.parsed_body[:content])
    expect(document.css('h3, abbr, sup').map(&:text)).to eq %w(Remote HTML 2)
    expect(document.at_css('details')['style']).to eq 'color: red;'
    expect(document.at_css('details p').text).to eq 'today body'
    expect(document.at_css('time')['datetime']).to eq '2026-09-12'
  end

  it 'rejects an empty rendered body using the original presence validation' do
    post '/api/v1/statuses', headers: headers, params: { status: '<p><img src="https://example.org/image.png"></p>', content_type: 'text/html' }

    expect(response).to have_http_status(422)

    media = Fabricate(:media_attachment, account: user.account)
    post '/api/v1/statuses', headers: headers, params: { status: '<p></p>', content_type: 'text/html', media_ids: [media.id] }

    expect(response).to have_http_status(200)
    expect(user.account.statuses.find(response.parsed_body[:id]).text).to eq '<p></p>'
  end

  it 'rewrites IDN mentions in prose while preserving HTML code and attributes' do
    mentioned = Fabricate(:account, username: 'sneak', domain: 'xn--hresiar-mxa.ch', protocol: :activitypub, uri: 'https://example.org/users/sneak', url: 'https://example.org/@sneak')
    source = '<code>@sneak@hæresiar.ch</code><p>@sneak@hæresiar.ch</p><code>@sneak@hæresiar.ch</code><a href="https://example.org/?user=@sneak@hæresiar.ch">link</a>'

    post '/api/v1/statuses', headers: headers, params: { status: source, content_type: 'text/html' }

    expect(response).to have_http_status(200)
    status = user.account.statuses.find(response.parsed_body[:id])
    document = Nokogiri::HTML5.fragment(response.parsed_body[:content])
    expect(status.active_mentions.pluck(:account_id)).to contain_exactly(mentioned.id)
    expect(status.text).to eq source.sub('<p>@sneak@hæresiar.ch</p>', '<p>@sneak@xn--hresiar-mxa.ch</p>')
    expect(document.at_css('p a.mention')).to be_present
    expect(Nokogiri::HTML5.fragment(status.text).at_css('code').text).to eq '@sneak@hæresiar.ch'
    expect(Nokogiri::HTML5.fragment(status.text).css('a').last['href']).to eq 'https://example.org/?user=@sneak@hæresiar.ch'
  end

  it 'preserves encoded Markdown mentions as ordinary text alongside code' do
    mentioned = Fabricate(:account, username: 'sneak', domain: 'xn--hresiar-mxa.ch', protocol: :activitypub, uri: 'https://example.org/users/sneak', url: 'https://example.org/@sneak')
    skipped = Fabricate(:account, username: 'markdownskip')
    source = "`@markdownskip #CodeTag @sneak@hæresiar.ch`\n\n&#64;sneak@hæresiar.ch #PublicTag\n\n```\n@markdownskip #CodeTag @sneak@hæresiar.ch\n```"

    post '/api/v1/statuses', headers: headers, params: { status: source, content_type: 'text/markdown' }

    expect(response).to have_http_status(200)
    status = user.account.statuses.find(response.parsed_body[:id])
    document = Nokogiri::HTML5.fragment(response.parsed_body[:content])
    expect(status.text).to eq source
    expect(status.active_mentions.pluck(:account_id)).to_not include(mentioned.id, skipped.id)
    expect(status.active_mentions).to be_empty
    expect(status.tags.pluck(:name)).to contain_exactly('publictag')
    expect(document.css('a.mention:not(.hashtag)')).to be_empty
    expect(document.css('code a, pre a')).to be_empty
    expect(document.at_css('code').text).to eq '@markdownskip #CodeTag @sneak@hæresiar.ch'
  end

  %w(text/html text/markdown).each do |content_type|
    it "only saves and federates literal entities in mixed #{content_type} source" do
      mentioned = Fabricate(:account, username: 'literal')
      Fabricate(:account, username: 'encoded')
      Fabricate(:account, username: 'split')
      Fabricate(:account, username: 'spl')
      source = '<b>@literal</b> &#64;encoded @spl<!-- gap -->it #Whole #Enc&#111;ded #Spl<!-- gap -->it ' \
               'https://safe.example.org/ https://enc&#111;ded.example.org/ https://spl<!-- gap -->it.example.org/'

      post '/api/v1/statuses', headers: headers, params: { status: source, content_type: content_type }

      expect(response).to have_http_status(200)
      status = user.account.statuses.find(response.parsed_body[:id])
      document = Nokogiri::HTML5.fragment(response.parsed_body[:content])
      expect(status.text).to eq source
      expect(status.active_mentions.pluck(:account_id)).to contain_exactly(mentioned.id)
      expect(status.tags.pluck(:name)).to contain_exactly('whole')
      expect(document.css('a.mention:not(.hashtag)').map(&:text)).to eq ['@literal']
      expect(document.css('a.hashtag').map(&:text)).to eq ['#Whole']
      expect(document.css('a:not(.mention)').map { |link| link['href'] }).to eq ['https://safe.example.org/']
      expect(Wxw::HtmlFormatter.for_status(status).urls.map(&:to_s)).to eq ['https://safe.example.org/']

      note = serialized_record_json(status, ActivityPub::NoteSerializer, adapter: ActivityPub::Adapter)
      expect(note['content']).to eq response.parsed_body[:content]
      expect(note['tag'].select { |tag| tag['type'] == 'Mention' }.pluck('href')).to eq [ActivityPub::TagManager.instance.uri_for(mentioned)]
      expect(note['tag'].select { |tag| tag['type'] == 'Hashtag' }.pluck('name')).to eq ['#whole']

      get "/api/v1/statuses/#{status.id}/source", headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to include(text: source, content_type: content_type)
    end

    it "silences previous mentions when #{content_type} is edited to encoded text" do
      mentioned = Fabricate(:account, username: 'literal')
      post '/api/v1/statuses', headers: headers, params: { status: '@literal #Whole https://safe.example.org/', content_type: content_type }

      expect(response).to have_http_status(200)
      status = user.account.statuses.find(response.parsed_body[:id])
      expect(status.active_mentions.pluck(:account_id)).to contain_exactly(mentioned.id)
      edited = '&#64;literal #Wh&#111;le https://safe&#46;example.org/'

      put "/api/v1/statuses/#{status.id}", headers: headers, params: { status: edited }

      expect(response).to have_http_status(200)
      expect(status.reload.text).to eq edited
      expect(status.active_mentions).to be_empty
      expect(status.mentions.pluck(:account_id, :silent)).to contain_exactly([mentioned.id, true])
      expect(status.tags).to be_empty
      expect(Nokogiri::HTML5.fragment(response.parsed_body[:content]).css('a')).to be_empty
      expect(Wxw::HtmlFormatter.for_status(status).urls).to be_empty

      get "/api/v1/statuses/#{status.id}/source", headers: headers

      expect(response.parsed_body).to include(text: edited, content_type: content_type)
    end
  end

  it 'accepts explicit HTML beyond the character limit while retaining the plain-text API limit' do
    stub_const 'StatusLengthValidator::MAX_CHARS', 100

    post '/api/v1/statuses', headers: headers, params: { status: "<p>#{'&amp;' * 100}</p>", content_type: 'text/html' }

    expect(response).to have_http_status(200)
    expect(Nokogiri::HTML5.fragment(response.parsed_body[:content]).text).to eq '&' * 100

    post '/api/v1/statuses', headers: headers, params: { status: "<p>#{'&amp;' * 101}</p>", content_type: 'text/html' }

    expect(response).to have_http_status(200)

    post '/api/v1/statuses', headers: headers, params: { status: '&' * 101 }

    expect(response).to have_http_status(422)
  end
end
