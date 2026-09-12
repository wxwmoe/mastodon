# frozen_string_literal: true

require 'crass'

class Sanitize
  module RichTextStyles
    SPACING_PROPERTIES = %w(margin padding).flat_map do |prefix|
      ['', '-top', '-right', '-bottom', '-left', '-block', '-inline', '-block-start', '-block-end', '-inline-start', '-inline-end'].map { |suffix| prefix + suffix }
    end.freeze
    PROPERTIES = (%w(color background-color border-color font-family font-style font-weight font-size line-height text-align text-decoration-line border-style border-width border-radius) + SPACING_PROPERTIES).freeze
    COLORS = %w(aqua black blue fuchsia gray green lime maroon navy olive purple red silver teal white yellow transparent currentcolor).freeze
    KEYWORDS = {
      'font-family' => %w(serif sans-serif monospace cursive fantasy system-ui),
      'font-style' => %w(normal italic oblique),
      'text-align' => %w(start end left right center justify),
      'border-style' => %w(none solid dashed dotted double),
    }.freeze

    def self.sanitize(style)
      Crass.parse_properties(style.to_s).filter_map do |declaration|
        next unless declaration[:node] == :property && !declaration[:important]

        name = declaration[:name].downcase
        next unless PROPERTIES.include?(name)

        tokens = declaration[:children].reject { |token| %i(whitespace comment).include?(token[:node]) }
        next unless valid_value?(name, tokens)

        value = tokens.map do |token|
          case token[:node]
          when :hash then "##{token[:value].downcase}"
          when :dimension then "#{token[:value]}#{token[:unit].downcase}"
          else token[:value].to_s.downcase
          end
        end.join(' ')
        "#{name}: #{value};"
      end.join(' ')
    end

    class << self
      private

      def valid_value?(name, tokens)
        return false if tokens.empty?

        first = tokens.first
        case name
        when 'color', 'background-color', 'border-color'
          tokens.size <= (name == 'border-color' ? 4 : 1) && tokens.all? { |token| color?(token) }
        when 'font-family', 'font-style', 'text-align', 'border-style'
          tokens.size <= (name == 'border-style' ? 4 : 1) && tokens.all? { |token| keyword?(token, KEYWORDS.fetch(name)) }
        when 'font-weight'
          tokens.one? && (keyword?(first, %w(normal bold)) || (first[:node] == :number && (100..900).cover?(first[:value]) && (first[:value] % 100).zero?))
        when 'font-size'
          tokens.one? && length?(first, px: 12..32, rem: 0.75..2)
        when 'line-height'
          tokens.one? && (keyword?(first, ['normal']) || (first[:node] == :number && (1..3).cover?(first[:value])))
        when 'text-decoration-line'
          return true if tokens.one? && keyword?(first, ['none'])

          tokens.size <= 3 &&
            tokens.all? { |token| keyword?(token, %w(underline overline line-through)) } &&
            tokens.map { |token| token[:value].downcase }.uniq.size == tokens.size
        when 'border-width', 'border-radius'
          tokens.size <= 4 && tokens.all? { |token| length?(token, px: 0..(name == 'border-width' ? 4 : 16)) }
        else
          maximum = if %w(margin padding).include?(name)
                      4
                    elsif name.end_with?('-block', '-inline')
                      2
                    else
                      1
                    end
          tokens.size <= maximum && tokens.all? { |token| length?(token, px: 0..32, rem: 0..2) || (name.start_with?('margin') && keyword?(token, ['auto'])) }
        end
      end

      def keyword?(token, values)
        token[:node] == :ident && values.include?(token[:value].downcase)
      end

      def color?(token)
        keyword?(token, COLORS) || (token[:node] == :hash && /\A(?:[a-f0-9]{3,4}|[a-f0-9]{6}|[a-f0-9]{8})\z/i.match?(token[:value]))
      end

      def length?(token, px:, rem: nil)
        return token[:value].zero? && px.cover?(0) if token[:node] == :number
        return false unless token[:node] == :dimension

        range = case token[:unit].downcase
                when 'px' then px
                when 'rem' then rem
                end
        range&.cover?(token[:value]) || false
      end
    end
  end
end
