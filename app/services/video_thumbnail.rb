require "open3"
require "json"
require "tempfile"

# A poster frame for an uploaded video, pulled from the middle of the clip with
# ffmpeg. One frame is decoded and re-encoded as a single JPEG — not a pass over
# the whole file — so like VideoMetadata this stays inline in the request.
#
# The still keeps the clip's own shape: it is scaled to fit inside a MAX_EDGE box
# (never upscaled — a small video keeps its own size), so a portrait clip yields a
# portrait frame, and compressed a little (QUALITY) so it is cheap for the feed to
# load ahead of the video itself.
#
# It is optional in the same way the duration is: a video whose thumbnail cannot
# be produced — no ffmpeg on PATH, an unreadable stream — is still published, just
# without a poster frame. #generate returns nil in every one of those cases rather
# than raising.
module VideoThumbnail
  MAX_EDGE = 720          # longest side of the produced JPEG, in pixels
  QUALITY = 5             # ffmpeg -q:v: 2 (best) … 31 (worst); sharp but compressed

  # Fits the decoded frame inside a MAX_EDGE box, keeping its aspect ratio, and
  # never enlarges one that already fits — min(…) caps the box at the frame's own
  # size, and `decrease` shrinks to fit rather than stretching to fill.
  #
  # The size is ffmpeg's to work out rather than ours, deliberately. The container's
  # width/height describe the frame *as stored*, before the rotation a phone records
  # portrait video with is applied; ffmpeg rotates on decode, so handing it two
  # explicit edges computed from those numbers squashed every rotated clip into a
  # landscape still. Asking for a box instead means the shape never has to be
  # predicted — it is measured off the result by #dimensions_of.
  SCALE_FILTER =
    "scale='min(#{MAX_EDGE},iw)':'min(#{MAX_EDGE},ih)':force_original_aspect_ratio=decrease".freeze

  # Reads the pixel size of the still we just wrote, the same way VideoMetadata
  # reads a video's: a header read, never a decode.
  PROBE_ARGUMENTS = %w[
    -v error -select_streams v:0
    -show_entries stream=width,height
    -of json
  ].freeze

  # The JPEG itself, alongside its exact dimensions.
  #
  # The frame is handed over as *bytes* rather than an open file, and deliberately:
  # Active Storage defers a blob's upload to an after_commit callback, so an
  # attachment made inside a transaction is read only once that transaction
  # commits — well after this module has returned and cleaned up. A file handle
  # cannot be given a lifetime that spans that without leaking it; a String can.
  # One capped, compressed frame is small enough to hold. (An open Tempfile here
  # is what made every video upload 500 with "IOError: closed stream".)
  Thumbnail = Struct.new(:bytes, :width, :height, keyword_init: true)

  module_function

  # Extracts the frame at `at_seconds` from the still-unattached upload (a tempfile
  # on disk) and returns a Thumbnail, or nil if none could be produced.
  def generate(file, at_seconds:)
    output = Tempfile.new(%w[video-thumbnail .jpg], binmode: true)

    begin
      return nil unless run(file.tempfile.path, output.path, at_seconds: at_seconds)

      # ffmpeg can exit cleanly having written nothing; an empty frame is no frame.
      bytes = File.binread(output.path)
      return nil if bytes.empty?

      width, height = dimensions_of(output.path)
      return nil unless width && height

      Thumbnail.new(bytes: bytes, width: width, height: height)
    ensure
      output.close!
    end
  end

  # Runs ffmpeg to write a single fitted JPEG to `output`, returning whether it
  # succeeded. Seeking before -i is ffmpeg's fast input seek — accurate enough for
  # a poster frame and cheap. Any failure is logged and reported as false.
  #
  # Each argument is passed positionally, so Open3 execs ffmpeg directly with no
  # shell in between — and SCALE_FILTER is a constant besides, so nothing a caller
  # supplies reaches the filter graph at all.
  def run(input, output, at_seconds:)
    _stdout, stderr, status = Open3.capture3(
      "ffmpeg", "-y",
      "-ss", format("%.3f", at_seconds),
      "-i", input,
      "-frames:v", "1",
      "-vf", SCALE_FILTER,
      "-q:v", QUALITY.to_s,
      output
    )
    return true if status.success?

    Rails.logger.warn("ffmpeg could not extract a video thumbnail: #{stderr.strip}")
    false
  rescue SystemCallError => e
    # Most likely Errno::ENOENT — ffmpeg is not installed on this machine.
    Rails.logger.warn("ffmpeg is unavailable, storing a video without a thumbnail: #{e.message}")
    false
  end

  # The still's real size as [width, height], measured off the JPEG rather than
  # predicted from the source — predicting it is precisely what used to be wrong.
  # Returns nil when it cannot be read, which costs the frame: the client lays the
  # poster out from these two numbers, so a thumbnail of unknown shape is worth
  # less than none at all.
  def dimensions_of(path)
    stdout, stderr, status = Open3.capture3("ffprobe", *PROBE_ARGUMENTS, path)
    unless status.success?
      Rails.logger.warn("ffprobe could not measure a video thumbnail: #{stderr.strip}")
      return nil
    end

    stream = JSON.parse(stdout).fetch("streams", []).first || {}
    width = Integer(stream["width"].to_s, exception: false)
    height = Integer(stream["height"].to_s, exception: false)
    return nil unless width&.positive? && height&.positive?

    [ width, height ]
  rescue JSON::ParserError, SystemCallError => e
    Rails.logger.warn("ffprobe could not measure a video thumbnail: #{e.message}")
    nil
  end
end
