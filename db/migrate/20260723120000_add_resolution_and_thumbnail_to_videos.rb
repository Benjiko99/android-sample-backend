# A video now carries its pixel resolution and a server-generated poster frame.
# `width`/`height` are the video's own dimensions, read off the file with ffprobe;
# `thumbnail_*` describe the extracted still. The thumbnail itself is either an
# Active Storage attachment (uploads) or an external `thumbnail_url` (seed data),
# the same split `file`/`url` already take — so `thumbnail_url` is nullable too.
#
# Every column is nullable: a clip whose resolution we cannot read, or for which
# no thumbnail could be produced, still publishes (see VideoMetadata / VideoThumbnail).
class AddResolutionAndThumbnailToVideos < ActiveRecord::Migration[8.0]
  def change
    change_table :videos, bulk: true do |t|
      t.integer :width
      t.integer :height
      t.string :thumbnail_url
      t.integer :thumbnail_width
      t.integer :thumbnail_height
    end
  end
end
