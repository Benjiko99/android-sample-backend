# Photos used to be seed-only, always carrying an external `url`. Uploaded photos
# store their bytes as an Active Storage attachment instead, so `url` is now the
# sample-data-only column and may be null (see Photo#display_url).
class AllowUploadedPhotos < ActiveRecord::Migration[8.0]
  def change
    change_column_null :photos, :url, true
  end
end
