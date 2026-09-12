# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../app/lib/wxw/mfm_styles'

RSpec.describe Wxw::MfmStyles do
  it 'maps supported static declarations without changing content' do
    content = "<plain>literal $[bg.color=f00 ]</plain>\nsecond".freeze
    style = 'font-weight: 700; font-style: oblique; text-decoration-line: underline line-through; font-family: monospace; color: red; background-color: #ff0;'

    expect(described_class.wrap(content, style)).to eq "$[bg.color=ffff00 $[fg.color=ff0000 $[font.monospace <s><i><b>#{content}</b></i></s>]]]"
    expect(content).to eq "<plain>literal $[bg.color=f00 ]</plain>\nsecond"
  end

  it 'normalizes colors only when their values remain representable' do
    {
      '#AbC' => 'aabbcc', '#AbCd' => 'abcd', '#123456' => '123456',
      '#123456ff' => '123456', '#aabbccdd' => 'abcd', 'transparent' => '0000',
      'aqua' => '00ffff', 'silver' => 'c0c0c0',
    }.each do |source, expected|
      expect(described_class.wrap('text', "color: #{source}")).to eq "$[fg.color=#{expected} text]"
    end

    %w(currentColor #12345678).each do |source|
      expect(described_class.wrap('text', "color: #{source}")).to eq 'text'
    end
  end

  it 'keeps the last valid declaration and drops unsupported styling' do
    style = 'color: red; color: invalid; color: blue; font-weight: 600; font-style: normal; font-family: sans-serif; text-align: center; font-size: 32px; line-height: 3; padding: 16px; margin: auto; text-decoration-line: underline overline;'

    expect(described_class.wrap('text', style)).to eq '$[fg.color=0000ff text]'
    expect(described_class.wrap('', 'color: red; border-style: solid; border-width: 1px')).to eq ''
    expect(described_class.wrap('text', nil)).to eq 'text'
  end

  it 'maps uniform visible borders without inventing borders for unrelated declarations' do
    style = 'border-style: dashed dashed; border-width: 2px 2px; border-color: #aabbcc #abc; border-radius: 4px;'

    expect(described_class.wrap('text', style)).to eq '$[border.style=dashed,width=2,color=aabbcc,radius=4 text]'
    expect(described_class.wrap('text', 'border-style: solid; border-width: 1.5px; border-color: red; border-radius: 0')).to eq '$[border.style=solid,width=1.5,color=ff0000,radius=0 text]'

    ['border-radius: 4px', 'border-width: 2px', 'border-style: solid', 'border-style: none; border-width: 2px', 'border-style: solid; border-width: 0', 'border-style: solid dashed; border-width: 2px', 'border-style: solid; border-width: 1px 2px'].each do |source|
      expect(described_class.wrap('text', source)).to eq 'text'
    end
  end

  it 'rejects CSS values that could inject MFM arguments' do
    ['color: f00]', 'color: #123456;color: url(https://example.org)', 'font-family: monospace] $[spin', 'border-width: 1px,rotate=90', 'border-radius: 1e999px', 'color: red !important'].each do |source|
      expected = source.start_with?('color: #123456;') ? '$[fg.color=123456 text]' : 'text'
      expect(described_class.wrap('text', source)).to eq expected
    end
  end
end
