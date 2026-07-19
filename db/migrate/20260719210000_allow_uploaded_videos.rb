# Videos used to be seed-only, always carrying an external `url`. Uploaded videos
# store their bytes as an Active Storage attachment instead, so `url` is now the
# sample-data-only column and may be null (see Video#display_url) — the same shape
# the photos table took in AllowUploadedPhotos.
class AllowUploadedVideos < ActiveRecord::Migration[8.0]
  def change
    change_column_null :videos, :url, true
  end
end
