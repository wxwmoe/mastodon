# frozen_string_literal: true

module Wxw::StatusFormatSnapshotConcern
  def build_snapshot(**)
    super.tap do |snapshot|
      snapshot.status = self
      snapshot.wxw_content_type = wxw_content_type if local?
    end
  end
end
