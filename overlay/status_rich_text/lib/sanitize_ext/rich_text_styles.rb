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

        "#{name}: #{serialize(tokens)};"
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
          tokens.one? && (keyword?(first, %w(normal bold)) || (numeric?(first, :number) && (1..1000).cover?(first[:value])))
        when 'font-size'
          tokens.one? && length?(first)
        when 'line-height'
          tokens.one? && (keyword?(first, ['normal']) || (numeric?(first, :number) && first[:value] >= 0) || length?(first))
        when 'text-decoration-line'
          return true if tokens.one? && keyword?(first, ['none'])

          tokens.size <= 3 &&
            tokens.all? { |token| keyword?(token, %w(underline overline line-through)) } &&
            tokens.map { |token| token[:value].downcase }.uniq.size == tokens.size
        when 'border-width', 'border-radius'
          tokens.size <= 4 && tokens.all? { |token| length?(token, percentage: name == 'border-radius') }
        else
          maximum = if %w(margin padding).include?(name)
                      4
                    elsif name.end_with?('-block', '-inline')
                      2
                    else
                      1
                    end
          tokens.size <= maximum && tokens.all? { |token| length?(token) || (name.start_with?('margin') && keyword?(token, ['auto'])) }
        end
      end

      def keyword?(token, values)
        token[:node] == :ident && values.include?(token[:value].downcase)
      end

      def color?(token)
        keyword?(token, COLORS) ||
          (token[:node] == :hash && /\A(?:[a-f0-9]{3,4}|[a-f0-9]{6}|[a-f0-9]{8})\z/i.match?(token[:value])) ||
          color_function?(token)
      end

      def color_function?(token)
        return false unless token[:node] == :function && %w(rgb rgba hsl hsla).include?(token[:name].downcase)
        return false unless token[:tokens].last[:node] == :')'

        args = token[:value].reject { |child| %i(whitespace comment).include?(child[:node]) }
        legacy = args.any? { |child| child[:node] == :comma }
        if legacy
          return false unless [5, 7].include?(args.size)
          return false unless args.each_with_index.all? { |child, index| index.even? || child[:node] == :comma }

          components = args.each_slice(2).map(&:first)
        else
          return false unless args.size == 3 || (args.size == 5 && args[3][:node] == :delim && args[3][:value] == '/')
          return false if token[:value].each_cons(2).any? { |left, right| numeric?(left, :number, :percentage, :dimension) && numeric?(right, :number, :percentage, :dimension) }

          components = args.first(3)
          components << args.last if args.size == 5
        end

        channels = components.first(3)
        return false if components.size == 4 && !numeric?(components.last, :number, :percentage)

        if token[:name].downcase.start_with?('rgb')
          channels.all? { |channel| numeric?(channel, :number, :percentage) } &&
            (!legacy || channels.map { |channel| channel[:node] }.uniq.one?)
        else
          hue = channels.first
          (numeric?(hue, :number) || (numeric?(hue, :dimension) && %w(deg grad rad turn).include?(hue[:unit].downcase))) &&
            channels.drop(1).all? { |channel| numeric?(channel, *(legacy ? [:percentage] : %i(number percentage))) }
        end
      end

      def length?(token, percentage: true)
        return false unless numeric?(token, :number, :dimension, :percentage) && token[:value] >= 0

        case token[:node]
        when :number then token[:value].zero?
        when :percentage then percentage
        when :dimension then %w(px em rem).include?(token[:unit].downcase)
        end
      end

      def numeric?(token, *types)
        # Crass clamps overflowing exponents, so validate the original number too.
        types.include?(token[:node]) && token[:repr].to_f.finite?
      end

      def serialize(tokens)
        tokens.filter_map do |token|
          case token[:node]
          when :whitespace, :comment then nil
          when :hash then "##{token[:value].downcase}"
          when :dimension then "#{token[:value]}#{token[:unit].downcase}"
          when :percentage then "#{token[:value]}%"
          when :function then "#{token[:name].downcase}(#{serialize(token[:value])})"
          when :comma then ','
          else token[:value].to_s.downcase
          end
        end.join(' ').gsub(' ,', ',')
      end
    end
  end
end
