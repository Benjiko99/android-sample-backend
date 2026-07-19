# Mirrors video.schema.ts (toVideoDTO). Exposes the playable URL as `videoUrl`.
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
      "videoUrl" => video.display_url
    }
  end
end
