# frozen_string_literal: true

class Sanitize
  module CodeLanguage
    def self.sanitize(node)
      language = if node.name == 'code' && node.parent&.name == 'pre'
                   node['class']&.split(/[\t\n\f\r ]/)&.find { |value| /\Alanguage-[A-Za-z0-9][A-Za-z0-9_+.#-]{0,63}\z/.match?(value) }
                 end

      if language
        node['class'] = language
      else
        node.remove_attribute('class')
      end
    end
  end
end
