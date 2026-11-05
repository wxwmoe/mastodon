# frozen_string_literal: true

module Wxw::ChineseSearch
  TOKENIZER = 'ik_max_word'
  CHAR_FILTER = { tsconvert: { type: 'stconvert', keep_both: false, delimiter: '#', convert_type: 't2s' } }.freeze
  CONTENT = { tokenizer: TOKENIZER, char_filter: %w(tsconvert) }.freeze
  TAG = { tokenizer: 'ik_smart', char_filter: %w(tsconvert) }.freeze
end
