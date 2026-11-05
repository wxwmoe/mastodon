# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/sanitize_ext/rich_text_styles'

RSpec.describe Sanitize::RichTextStyles do
  it 'keeps static styling and canonicalizes CSS escapes' do
    source = 'c\6f lor: \72 ed; background-color: #AbCd; border-color: #123 #123456 #12345678 currentColor; font-family: monospace; font-style: italic; font-weight: 700; text-align: center; text-decoration-line: underline line-through; margin: 0 auto; padding-inline: 2rem 32px; border-style: solid dashed; border-width: 0 4px; border-radius: 16px;'.freeze
    expected = 'color: red; background-color: #abcd; border-color: #123 #123456 #12345678 currentcolor; font-family: monospace; font-style: italic; font-weight: 700; text-align: center; text-decoration-line: underline line-through; margin: 0 auto; padding-inline: 2rem 32px; border-style: solid dashed; border-width: 0 4px; border-radius: 16px;'

    expect(described_class.sanitize(source)).to eq expected
    expect(described_class.sanitize(expected)).to eq expected
    expect(described_class.sanitize('')).to eq ''
  end

  it 'allows nonnegative layout values without arbitrary size limits' do
    {
      'font-size' => [%w(0 8px 100px 1000px 10rem 2em 200%), %w(-1px -1% 12 1vw)],
      'line-height' => [%w(normal 0 0.99 5 100px 2em 3rem 200%), %w(-1 -1px 1vh)],
      'font-weight' => [%w(normal bold 1 99 450 950 1000), %w(0 1001 1px)],
      'padding' => [%w(0 100px 10rem 3em 50%), %w(-1px -1% auto 2)],
      'margin' => [%w(0 auto 1000px 4em 10%), %w(-1px -1% 2)],
      'border-width' => [%w(0 100px 1rem 2em), %w(-1px 50% 2)],
      'border-radius' => [%w(0 100px 2rem 3em 100%), %w(-1px -1% 2)],
    }.each do |property, (allowed, rejected)|
      aggregate_failures(property) do
        allowed.each { |value| expect(described_class.sanitize("#{property}: #{value}")).not_to be_empty }
        rejected.each { |value| expect(described_class.sanitize("#{property}: #{value}")).to eq '' }
      end
    end

    expect(described_class.sanitize('margin-inline-start: auto; padding-block-end: 2rem')).to eq 'margin-inline-start: auto; padding-block-end: 2rem;'
  end

  it 'preserves RGB and HSL colors with numeric or percentage transparency' do
    colors = [
      'rgb(255, 0, 127)', 'rgba(255, 0, 127, 0.5)', 'rgb(100%, 0%, 50%, 50%)',
      'rgba(255 0 127)', 'rgb(255 0 127 / 50%)', 'rgb(100% 0 50% / 0.5)',
      'hsl(120, 100%, 50%)', 'hsla(120, 100%, 50%, 0.5)',
      'hsl(0.5turn 100% 50% / 25%)', 'hsla(200grad 100 50 / 0.5)',
      'hsl(3.14rad 100% 50%)', 'hsl(-90deg 100% 50%)',
      'rgb(-10 300 0 / 2)', '#1234', '#11223344', 'transparent',
    ]
    colors.each do |color|
      aggregate_failures(color) do
        source = "color: #{color}; background-color: #{color}; border-color: #{color} #fff;"
        expect(described_class.sanitize(source)).to eq source
        expect(described_class.sanitize(described_class.sanitize(source))).to eq source
      end
    end

    expect(described_class.sanitize('COLOR: R\\47 B(255,0,0); background-color: rgba(0/**/ 0 0 / 50%);')).to eq 'color: rgb(255, 0, 0); background-color: rgba(0 0 0 / 50%);'
  end

  it 'drops invalid declarations without discarding adjacent safe declarations' do
    [
      'margin-left: -1px', 'margin: 0 1px 2px 3px 4px', 'padding-left: 1px 2px', 'padding-inline: 1px 2px 3px',
      'font-family: serif, monospace', 'font-family: "serif"', 'font-style: oblique 20deg',
      'text-decoration-line: none underline', 'text-decoration-line: underline underline',
      'color: #12345', 'color: #1234567', 'color: #ggg',
      'color: rgb(0, 0)', 'color: rgb(0, 0, 0, 1, 2)', 'color: rgb(0, 0%, 0)',
      'color: rgb(0 0 0 0.5)', 'color: rgb(0+0+0)', 'color: rgb(0, 0, 0 / 0.5)',
      'color: rgba(0 0 0 /)', 'color: rgb(0 0 0 / 1px)',
      'color: hsl(0px 50% 50%)', 'color: hsl(0, 50, 50)', 'color: rgba(var(--x) 0 0)',
      'color: rgb(calc(1 + 2) 0 0)', 'color: rgb(1e999 0 0)', 'color: hsl(1e999deg 50% 50%)',
      'color: rgba(0 0 0 / 1e999)', 'color: hsl(0 1e999% 50%)',
      'color: blue !important', 'color: blue !\69mportant', 'color: blue { color: red }',
      'padding: 1e999px', 'padding: -1e999px', 'font-size: 1e999%', 'line-height: 1e999', 'font-size: calc(16px + 1px)',
      'color: var(--color, red)', 'color: expression(alert(1))', 'color: u\72l(https://example.org/)',
      'background-color: image-set("https://example.org/" 1x)', 'background-color: url(data:image/png,test)',
      '--color: red', '-webkit-text-fill-color: red', 'position: fixed', 'z-index: 100', 'white-space: pre',
      'animation-name: global-spin', '@import "https://example.org/style.css"',
    ].each do |declaration|
      aggregate_failures(declaration) do
        expect(described_class.sanitize("color: red; #{declaration}; text-align: center")).to eq 'color: red; text-align: center;'
      end
    end

    expect(described_class.sanitize('color: red; color: rgb(0 0 0')).to eq 'color: red;'
  end
end
