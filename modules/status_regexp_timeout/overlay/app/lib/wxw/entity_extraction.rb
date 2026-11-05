# frozen_string_literal: true

module Wxw::EntityExtraction
  def self.call(extractor, text, options)
    [
      -> { extractor.extract_urls_with_indices(text, options) },
      -> { extractor.extract_hashtags_with_indices(text, check_url_overlap: false) },
      -> { extractor.extract_mentions_or_lists_with_indices(text) },
      -> { extractor.extract_extra_uris_with_indices(text) },
    ].flat_map do |extract|
      extract.call
    rescue Regexp::TimeoutError
      []
    end
  end
end
