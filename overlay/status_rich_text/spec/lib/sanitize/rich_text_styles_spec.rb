# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/sanitize_ext/rich_text_styles'

RSpec.describe Sanitize::RichTextStyles do
  it 'keeps bounded static styling and canonicalizes CSS escapes' do
    source = 'c\6f lor: \72 ed; background-color: #AbCd; border-color: #123 #123456 #12345678 currentColor; font-family: monospace; font-style: italic; font-weight: 700; text-align: center; text-decoration-line: underline line-through; margin: 0 auto; padding-inline: 2rem 32px; border-style: solid dashed; border-width: 0 4px; border-radius: 16px;'.freeze
    expected = 'color: red; background-color: #abcd; border-color: #123 #123456 #12345678 currentcolor; font-family: monospace; font-style: italic; font-weight: 700; text-align: center; text-decoration-line: underline line-through; margin: 0 auto; padding-inline: 2rem 32px; border-style: solid dashed; border-width: 0 4px; border-radius: 16px;'

    expect(described_class.sanitize(source)).to eq expected
    expect(described_class.sanitize(expected)).to eq expected
    expect(described_class.sanitize('')).to eq ''
  end

  it 'accepts value boundaries and rejects values outside them' do
    {
      'font-size' => [%w(12px 32px 0.75rem 2rem), %w(0 11px 33px 0.74rem 2.01rem 2em 200%)],
      'line-height' => [%w(normal 1 3), %w(0.99 3.01 2px)],
      'font-weight' => [%w(normal bold 100 900), %w(0 99 950 1000)],
      'padding' => [%w(0 32px 2rem), %w(-1px 33px 2.01rem auto)],
      'border-width' => [%w(0 4px), %w(-1px 5px 1rem)],
      'border-radius' => [%w(0 16px), %w(-1px 17px 100%)],
    }.each do |property, (allowed, rejected)|
      aggregate_failures(property) do
        allowed.each { |value| expect(described_class.sanitize("#{property}: #{value}")).not_to be_empty }
        rejected.each { |value| expect(described_class.sanitize("#{property}: #{value}")).to eq '' }
      end
    end

    expect(described_class.sanitize('margin-inline-start: auto; padding-block-end: 2rem')).to eq 'margin-inline-start: auto; padding-block-end: 2rem;'
  end

  it 'drops invalid declarations without discarding adjacent safe declarations' do
    [
      'margin-left: -1px', 'margin: 0 1px 2px 3px 4px', 'padding-left: 1px 2px', 'padding-inline: 1px 2px 3px',
      'font-family: serif, monospace', 'font-family: "serif"', 'font-style: oblique 20deg',
      'text-decoration-line: none underline', 'text-decoration-line: underline underline',
      'color: #12345', 'color: #1234567', 'color: #ggg', 'color: rgb(0,0,0)',
      'color: blue !important', 'color: blue !\69mportant', 'color: blue { color: red }',
      'padding: 1e999px', 'padding: -1e999px', 'font-size: calc(16px + 1px)',
      'color: var(--color, red)', 'color: expression(alert(1))', 'color: u\72l(https://example.org/)',
      'background-color: image-set("https://example.org/" 1x)', 'background-color: url(data:image/png,test)',
      '--color: red', '-webkit-text-fill-color: red', 'position: fixed', 'z-index: 100', 'white-space: pre',
      'animation-name: global-spin', '@import "https://example.org/style.css"',
    ].each do |declaration|
      aggregate_failures(declaration) do
        expect(described_class.sanitize("color: red; #{declaration}; text-align: center")).to eq 'color: red; text-align: center;'
      end
    end
  end
end
