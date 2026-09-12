# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PostStatusService do
  let(:warning) { '<b>literal</b> & **plain**' }
  let(:account) { Struct.new(:user, :silenced?).new(nil, false) }
  let(:quote) { Struct.new(:id, :private_visibility?).new(123, false) }

  it 'preserves promoted plain text and sensitivity in scheduled publication options' do
    service = prepare_post(text: '', spoiler_text: warning, sensitive: false, media_ids: ['42'], content_type: 'text/markdown')
    scheduled = service.send(:scheduled_options)

    expect(service.instance_variable_get(:@text)).to eq warning
    expect(scheduled).to include(text: warning, content_type: 'text/plain', sensitive: true, media_ids: ['42'])
    expect(scheduled).to_not have_key(:spoiler_text)
    expect(prepare_post(scheduled).instance_variable_get(:@text)).to eq warning
  end

  it 'retains a quoted content warning without promoting or converting it' do
    service = prepare_post(text: '', spoiler_text: warning, quoted_status: quote)

    expect(service.instance_variable_get(:@text)).to eq ''
    expect(service.send(:scheduled_options)).to include(text: '', spoiler_text: warning, quoted_status_id: quote.id)
  end

  it 'leaves ordinary bodies, content warnings, and scheduled sensitivity defaults unchanged' do
    text = '<p><strong>body</strong></p>'
    service = prepare_post(text: text, spoiler_text: warning)
    scheduled = service.send(:scheduled_options)

    expect(scheduled).to include(text: text, spoiler_text: warning)
    expect(scheduled).to_not have_key(:sensitive)
    expect(prepare_post(text: text, sensitive: false).send(:scheduled_options)).to include(sensitive: false)
  end

  %w(text/html text/markdown).each do |content_type|
    it "retains the body and content warning when editing #{content_type}" do
      status = prepare_update({ text: '', spoiler_text: warning }, content_type: content_type)

      expect(status.text).to eq ''
      expect(status.spoiler_text).to eq warning
      expect(status.wxw_content_type).to eq content_type
    end
  end

  it 'retains native content warning promotion while editing plain text' do
    status = prepare_update({ text: '', spoiler_text: warning }, content_type: 'text/plain')

    expect(status.text).to eq warning
    expect(status.wxw_content_type).to eq 'text/plain'
  end

  it 'retains the native quote guard while editing' do
    status = prepare_update({ text: '', spoiler_text: warning }, quote: quote, content_type: 'text/plain')

    expect(status.text).to eq ''
    expect(status.spoiler_text).to eq warning
  end

  it 'keeps an ordinary content warning literal while editing a nonblank body' do
    status = prepare_update({ text: '**plain body**', spoiler_text: warning })

    expect(status.text).to eq '**plain body**'
    expect(status.spoiler_text).to eq warning
  end

  # Exercise native normalization only; these checks do not publish or persist.
  def prepare_post(options)
    service = described_class.new
    { account: account, options: options, text: options[:text] || '', quoted_status: options[:quoted_status] }.each do |name, value|
      service.instance_variable_set("@#{name}", value)
    end
    service.send(:preprocess_attributes!)
    service
  end

  def prepare_update(options, quote: nil, content_type: 'text/markdown')
    status = Status.new(text: '', spoiler_text: '', sensitive: false, language: 'en', wxw_content_type: content_type)
    allow(status).to receive_messages(account: account, quote: quote)
    service = UpdateStatusService.new
    service.instance_variable_set(:@status, status)
    service.instance_variable_set(:@options, options)
    allow(service).to receive(:significant_changes?).and_return(false)

    expect { service.send(:update_immediate_attributes!) }.to raise_error(UpdateStatusService::NoChangesSubmittedError)
    status
  end
end
