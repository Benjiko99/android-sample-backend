# Mirrors video.schema.ts (toVideoDTO). Exposes the playable URL as `videoUrl`
# and a poster frame as `thumbnailUrl`, each with the pixel dimensions the client
# uses to size the slot before the bytes arrive.
module VideoSerializer
  module_function

  def call(video)
    return nil if video.nil?

    {
      "id" => video.id,
      "title" => video.title,
      # Clients type this as a plain integer, so a video whose duration was never
      # recorded reports 0 rather than breaking their deserialization.
      "durationSeconds" => video.duration_seconds.to_i,
      "videoUrl" => video.display_url,
      # Resolution is nullable, not zero-defaulted like the duration: a 0×0 frame
      # is a size the client might lay out or divide by, whereas null plainly says
      # "unknown, fall back". Absent for a clip whose dimensions we could not read.
      "width" => video.width,
      "height" => video.height,
      "thumbnailUrl" => video.thumbnail_display_url,
      "thumbnailWidth" => video.thumbnail_width,
      "thumbnailHeight" => video.thumbnail_height
    }
  end
end
