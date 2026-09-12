# frozen_string_literal: true

require 'sanitize_ext/rich_text_styles'

module Wxw
  module MfmStyles
    COLORS = {
      'aqua' => '00ffff', 'black' => '000000', 'blue' => '0000ff', 'fuchsia' => 'ff00ff',
      'gray' => '808080', 'green' => '008000', 'lime' => '00ff00', 'maroon' => '800000',
      'navy' => '000080', 'olive' => '808000', 'purple' => '800080', 'red' => 'ff0000',
      'silver' => 'c0c0c0', 'teal' => '008080', 'white' => 'ffffff', 'yellow' => 'ffff00',
      'transparent' => '0000',
    }.freeze

    def self.wrap(content, style)
      return content if content.empty?

      properties = Sanitize::RichTextStyles.sanitize(style).split(';').to_h { |declaration| declaration.split(':', 2).map(&:strip) }
      content = "<b>#{content}</b>" if %w(bold 700 800 900).include?(properties['font-weight'])
      content = "<i>#{content}</i>" if %w(italic oblique).include?(properties['font-style'])
      content = "<s>#{content}</s>" if properties['text-decoration-line']&.split&.include?('line-through')

      family = properties['font-family']
      content = "$[font.#{family} #{content}]" if %w(serif monospace cursive fantasy).include?(family)
      foreground = color(properties['color'])
      background = color(properties['background-color'])
      content = "$[fg.color=#{foreground} #{content}]" if foreground
      content = "$[bg.color=#{background} #{content}]" if background

      border = border_args(properties)
      border.empty? ? content : "$[border.#{border.join(',')} #{content}]"
    end

    class << self
      private

      def color(value)
        return COLORS[value] unless value&.start_with?('#')

        hex = value.delete_prefix('#')
        case hex.length
        when 3 then hex.chars.map { |digit| digit * 2 }.join
        when 4, 6 then hex
        when 8
          return hex[0, 6] if hex.end_with?('ff')

          pairs = hex.scan(/../)
          pairs.map { |pair| pair[0] }.join if pairs.all? { |pair| pair[0] == pair[1] }
        end
      end

      def uniform(value)
        values = value&.split&.uniq
        values.first if values&.one?
      end

      def border_args(properties)
        style = uniform(properties['border-style'])
        width = uniform(properties['border-width'])
        return [] unless %w(solid dashed dotted double).include?(style) && width && width.to_f.positive?

        args = ["style=#{style}", "width=#{width.delete_suffix('px')}"]
        colors = properties['border-color']&.split&.map { |value| color(value) }&.uniq
        color = colors.first if colors&.one?
        radius = uniform(properties['border-radius'])
        args << "color=#{color}" if color
        args << "radius=#{radius.delete_suffix('px')}" if radius
        args
      end
    end
  end
end
