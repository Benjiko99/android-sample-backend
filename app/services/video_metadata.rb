require "open3"
require "json"

# What an uploaded video is, read off the file itself: how long it runs and how
# large its frame is. The client used to report the duration alongside the upload;
# the server now measures both, so the stored values always describe the stored
# bytes.
#
# ffprobe (shipped with ffmpeg, installed in the Docker image) reads the
# container's metadata for the first video stream and stops — it never decodes
# the stream — so this is a header read on a local tempfile rather than a pass
# over the file, and stays inline in the request.
#
# All of it is display metadata: a clip whose length or resolution we cannot read
# is still a clip worth publishing. Every failure — no ffprobe on PATH, an
# unparseable container, a stream that declares no duration — degrades to empty
# metadata rather than rejecting an upload that already passed content-type and
# size validation. Duration reads back as 0 (clients type it as a plain integer);
# an unknown width/height reads back as nil, since a 0×0 resolution would be a
# lie the client might divide by.
module VideoMetadata
  ARGUMENTS = %w[
    -v error -select_streams v:0
    -show_entries stream=width,height:format=duration
    -of json
  ].freeze

  # duration_seconds is always present (0 when unreadable); width/height are nil
  # when the container declares none.
  Metadata = Struct.new(:duration_seconds, :width, :height, keyword_init: true) do
    def self.empty
      new(duration_seconds: 0, width: nil, height: nil)
    end
  end

  module_function

  # Takes the uploaded file — before it is attached, while it is still a tempfile
  # on disk — and returns its Metadata.
  def extract(file)
    parse(probe(file.tempfile.path))
  end

  # ffprobe prints one JSON object: the first video stream's width/height and the
  # format's duration. Anything unreadable — a nil probe, invalid JSON, missing
  # keys — collapses to empty Metadata.
  def parse(output)
    return Metadata.empty if output.nil?

    data = JSON.parse(output)
    stream = data.fetch("streams", []).first || {}
    format = data.fetch("format", {})

    Metadata.new(
      duration_seconds: whole_seconds(format["duration"]),
      width: dimension(stream["width"]),
      height: dimension(stream["height"])
    )
  rescue JSON::ParserError
    Metadata.empty
  end

  # ffprobe prints the duration in seconds ("12.480000"), or omits it for a stream
  # that declares none. Anything unreadable reads as 0, and a nonsense negative is
  # clamped, so what we store is always whole non-negative seconds.
  def whole_seconds(value)
    seconds = Float(value.to_s, exception: false)
    seconds.nil? ? 0 : [ seconds.round, 0 ].max
  end

  # A pixel dimension is a positive integer or it is unknown (nil) — never zero.
  def dimension(value)
    pixels = Integer(value.to_s, exception: false)
    pixels&.positive? ? pixels : nil
  end

  # Runs ffprobe over the file and hands back its raw stdout, or nil when it could
  # not be run or could not read the file.
  def probe(path)
    stdout, stderr, status = Open3.capture3("ffprobe", *ARGUMENTS, path)
    return stdout if status.success?

    Rails.logger.warn("ffprobe could not read video metadata: #{stderr.strip}")
    nil
  rescue SystemCallError => e
    # Most likely Errno::ENOENT — ffmpeg is not installed on this machine.
    Rails.logger.warn("ffprobe is unavailable, storing empty video metadata: #{e.message}")
    nil
  end
end
