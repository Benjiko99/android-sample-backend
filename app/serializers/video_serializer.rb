# Mirrors video.schema.ts (toVideoDTO). Exposes `url` as `videoUrl`.
module VideoSerializer
  module_function

  def call(video)
    return nil if video.nil?

    {
      "id" => video.id,
      "title" => video.title,
      "durationSeconds" => video.duration_seconds,
      "videoUrl" => video.url
    }
  end
end
