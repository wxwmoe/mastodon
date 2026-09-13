# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPub::NoteSerializer do
  subject(:note) { serialized_record_json(status, described_class, adapter: ActivityPub::Adapter) }

  let(:account) { Fabricate(:account) }
  let(:source) { "**Introduction**\n\n```ruby\nputs '<hello>'\n```\n\nAfterward" }
  let(:status) { Fabricate(:status, account: account, text: source, language: 'en', wxw_content_type: 'text/markdown') }
  let(:web) { serialized_record_json(status, REST::StatusSerializer, options: { scope: nil, scope_name: :current_user }) }

  it 'adds whole-post MFM beside the original Markdown and compatible HTML' do
    expect(note['source']).to eq('content' => source, 'mediaType' => 'text/markdown')
    expect(note['_misskey_content']).to include('<b><plain>Introduction</plain></b>', "```ruby\nputs '<hello>'\n\n```", '<plain>Afterward</plain>')
    expect(note['contentMap']).to eq('en' => note['content'])
    expect(note['@context'].last).to include('_misskey_content' => 'https://misskey-hub.net/ns#_misskey_content')
    code = Nokogiri::HTML5.fragment(note['content']).at_css('pre code')
    expect(code.attribute_nodes).to be_empty
    expect(code.text).to eq "puts '<hello>'\n"
    expect(code.parent['class']).to eq 'language-ruby'
    expect(note['content']).to_not include('shiki')
    expect(status.reload.text).to eq source

    activity = serialized_record_json(status, ActivityPub::CreateNoteSerializer, adapter: ActivityPub::Adapter)
    expect(activity['object']).to include(note.slice('content', 'contentMap', 'source', '_misskey_content'))
    expect(activity['@context'].last).to include('_misskey_content' => 'https://misskey-hub.net/ns#_misskey_content')

    expect(Nokogiri::HTML5.fragment(web['content']).at_css('pre code')['class']).to eq 'language-ruby'
    expect(web).to_not have_key('_misskey_content')
  end

  it 'preserves associated mentions and custom emoji without turning literal text into mentions' do
    local = Fabricate(:account, username: 'localmention')
    remote = Fabricate(:account, username: 'remotemention', domain: 'remote.example', uri: 'https://remote.example/users/mention', url: 'https://remote.example/@mention')
    emoji = Fabricate(:custom_emoji, shortcode: 'test_emoji')
    status.text = "@#{local.username} @#{remote.acct} :#{emoji.shortcode}: &#64;unlinked\n\n```ruby\nputs :test_emoji\n```"
    status.save!
    Fabricate(:mention, account: local, status: status)
    Fabricate(:mention, account: remote, status: status)

    expect(note['_misskey_content']).to include("@#{local.username}@#{Rails.configuration.x.local_domain}", "@#{remote.acct}", ':test_emoji:')
    expect(note['_misskey_content']).to match(%r{<plain>[^<]*@unlinked[^<]*</plain>})
    expect(note['tag'].select { |tag| tag['type'] == 'Mention' }.pluck('href')).to contain_exactly(ActivityPub::TagManager.instance.uri_for(local), remote.uri)
    expect(note['tag']).to include(a_hash_including('type' => 'Emoji', 'name' => ':test_emoji:'))
  end

  it 'removes the extension when an edit removes the last language marker' do
    expect(note).to have_key('_misskey_content')

    status.update!(text: "```\nplain block\n```")
    edited = serialized_record_json(status, described_class, adapter: ActivityPub::Adapter)
    expect(edited).to_not have_key('_misskey_content')
    expect(edited['source']).to eq('content' => status.text, 'mediaType' => 'text/markdown')
  end

  it 'omits the extension when conversion cannot represent the complete post' do
    allow_any_instance_of(Wxw::MfmFormatter).to receive(:to_s).and_return(nil)

    expect(note).to_not have_key('_misskey_content')
    expect(note['source']['content']).to eq source
    expect(Nokogiri::HTML5.fragment(note['content']).at_css('pre code').attribute_nodes).to be_empty
  end

  context 'with Markdown formatting and no code language' do
    let(:source) { "## Heading\n\n<details><summary>Hint</summary>Hidden</details>" }

    it 'adds MFM while preserving the original Markdown and HTML' do
      expect(note['_misskey_content']).to include('$[x2 <b><plain>Heading</plain></b>]', '<plain>Hint</plain>', '$[blur <plain>Hidden</plain>]')
      expect(note['source']).to eq('content' => source, 'mediaType' => 'text/markdown')
      expect(Nokogiri::HTML5.fragment(note['content']).css('h2, details, summary').map(&:name)).to eq %w(h2 details summary)
    end

    it 'removes the extension when an edit removes the remaining formatting triggers' do
      expect(note).to have_key('_misskey_content')

      status.update!(text: "**Ordinary emphasis**\n\n> Plain quote\n\n`plain code`")
      edited = serialized_record_json(status, described_class, adapter: ActivityPub::Adapter)
      expect(edited).to_not have_key('_misskey_content')
      expect(edited['source']).to eq('content' => status.text, 'mediaType' => 'text/markdown')
    end
  end

  context 'with Markdown highlighting and no other MFM triggers' do
    let(:source) { '==**Highlighted** [link](https://example.org/)==' }

    it 'adds MFM colors while preserving the original Markdown and HTML markup' do
      expect(note['_misskey_content']).to start_with '$[bg.color=ffff00 $[fg.color=000000 '
      expect(note['_misskey_content']).to include '<b><plain>Highlighted</plain></b>', '[<plain>link</plain>](<https://example.org/>)'
      expect(note['source']).to eq('content' => source, 'mediaType' => 'text/markdown')
      expect(Nokogiri::HTML5.fragment(note['content']).css('mark strong, mark a').map(&:text)).to eq %w(Highlighted link)
    end
  end

  context 'with HTML source' do
    let(:source) { '<h1>Heading</h1><pre><code class="language-ruby" lang="en" style="color: red;">puts 1</code></pre>' }
    let(:status) { Fabricate(:status, account: account, text: source, wxw_content_type: 'text/html') }

    it 'keeps local highlighting metadata while removing all federated code attributes' do
      expect(note).to_not have_key('source')
      expect(note).to_not have_key('_misskey_content')
      expect(Nokogiri::HTML5.fragment(note['content']).at_css('pre code').attribute_nodes).to be_empty
      expect(Nokogiri::HTML5.fragment(web['content']).at_css('pre code')['class']).to eq 'language-ruby'
    end
  end

  context 'with plain source' do
    let(:source) { "## Heading\n\n<details><summary>Hint</summary>Hidden</details>" }
    let(:status) { Fabricate(:status, account: account, text: source) }

    it 'leaves plain-text serialization unchanged' do
      expect(note).to_not have_key('source')
      expect(note).to_not have_key('_misskey_content')
      expect(note['content']).to eq web['content']
    end
  end

  context 'with remote source' do
    let(:account) { Fabricate(:account, domain: 'remote.example') }
    let(:source) { '<h1>Heading</h1><pre><code class="language-ruby">puts 1</code></pre>' }
    let(:status) { Fabricate(:status, account: account, text: source) }

    it 'keeps the existing remote formatting and does not synthesize source or MFM' do
      expect(note).to_not have_key('source')
      expect(note).to_not have_key('_misskey_content')
      expect(note['content']).to eq HtmlAwareFormatter.new(source, false).to_s
      expect(Nokogiri::HTML5.fragment(note['content']).at_css('pre code')['class']).to eq 'language-ruby'
    end
  end
end
