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
# The resolution reported is the one the clip is *displayed* at, not the one it is
# stored at. A phone records portrait video as a landscape frame plus a quarter-turn
# in the container's display matrix, which every player applies on decode; ffprobe's
# stream width/height describe the frame before that turn. So a rotation of a quarter
# circle swaps the pair, and what we store is what the client must lay out — the same
# shape VideoThumbnail's poster frame comes back in.
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
    -show_entries stream=width,height:stream_tags=rotate:stream_side_data=rotation:format=duration
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

  # ffprobe prints one JSON object: the first video stream's width/height and how it
  # is rotated, plus the format's duration. Anything unreadable — a nil probe,
  # invalid JSON, missing keys — collapses to empty Metadata.
  def parse(output)
    return Metadata.empty if output.nil?

    data = JSON.parse(output)
    stream = data.fetch("streams", []).first || {}
    format = data.fetch("format", {})

    width = dimension(stream["width"])
    height = dimension(stream["height"])
    width, height = height, width if quarter_turn?(stream)

    Metadata.new(duration_seconds: whole_seconds(format["duration"]), width: width, height: height)
  rescue JSON::ParserError
    Metadata.empty
  end

  # Whether the stream is turned onto its side, and so displayed with its stored
  # width and height the other way round. Only a quarter turn transposes the frame:
  # a clip rotated 180° is upside down at the same resolution.
  def quarter_turn?(stream)
    (rotation(stream).abs % 180) == 90
  end

  # The clip's rotation in whole degrees, 0 when it declares none.
  #
  # Two spellings, because ffprobe has used both: the display matrix as stream side
  # data (what current ffmpeg prints, and what a phone actually writes), and an older
  # `rotate` tag. Reading each costs one key lookup, and on a build that reports only
  # the tag every portrait clip would otherwise go back to measuring as landscape.
  def rotation(stream)
    side_data = stream.fetch("side_data_list", []).find { |entry| entry.key?("rotation") }
    degrees = side_data ? side_data["rotation"] : stream.dig("tags", "rotate")

    Float(degrees.to_s, exception: false)&.round || 0
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
