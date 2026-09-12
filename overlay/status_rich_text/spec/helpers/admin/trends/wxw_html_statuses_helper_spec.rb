# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Trends::StatusesHelper do
  it 'previews the first rendered line of a local HTML post' do
    status = Fabricate.build(:status, text: '<p><strong>Bold</strong> &amp; plain</p><p>Next</p>', wxw_content_type: 'text/html')

    expect(helper.one_line_preview(status)).to eq 'Bold &amp; plain'
  end
end
