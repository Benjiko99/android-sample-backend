require "open3"
require "tempfile"

# A poster frame for an uploaded video, pulled from the middle of the clip with
# ffmpeg. One frame is decoded and re-encoded as a single JPEG — not a pass over
# the whole file — so like VideoMetadata this stays inline in the request.
#
# The still is emitted at one size: scaled down so its longest edge is at most
# MAX_EDGE (never upscaled — a small video keeps its own size), and compressed a
# little (QUALITY) so it is cheap for the feed to load ahead of the video itself.
#
# It is optional in the same way the duration is: a video whose thumbnail cannot
# be produced — no ffmpeg on PATH, an unreadable stream, a resolution we never
# read — is still published, just without a poster frame. #generate returns nil
# in every one of those cases rather than raising.
module VideoThumbnail
  MAX_EDGE = 720          # longest side of the produced JPEG, in pixels
  QUALITY = 5             # ffmpeg -q:v: 2 (best) … 31 (worst); sharp but compressed

  # An open, rewound JPEG ready to attach, alongside its exact dimensions.
  Thumbnail = Struct.new(:io, :width, :height, keyword_init: true)

  module_function

  # Extracts the frame at `at_seconds` from the still-untached upload (a tempfile
  # on disk) and returns a Thumbnail, or nil if none could be produced. The
  # caller owns the returned io and must close it once attached.
  #
  # width/height are the source video's dimensions; without them the target size
  # is unknown, so there is nothing to scale to and no thumbnail is made.
  def generate(file, width:, height:, at_seconds:)
    return nil unless width.to_i.positive? && height.to_i.positive?

    target_width, target_height = scaled_dimensions(width, height)
    output = Tempfile.new(%w[video-thumbnail .jpg], binmode: true)

    unless run(file.tempfile.path, output.path, at_seconds:, width: target_width, height: target_height)
      output.close!
      return nil
    end

    output.rewind
    Thumbnail.new(io: output, width: target_width, height: target_height)
  end

  # Scales (width, height) down so the longest edge is at most MAX_EDGE, keeping
  # the aspect ratio; a video already within the cap is left untouched (we never
  # upscale a small clip into a larger, blurrier still). Never returns below 1px.
  def scaled_dimensions(width, height)
    longest = [ width, height ].max
    return [ width, height ] if longest <= MAX_EDGE

    ratio = MAX_EDGE.to_f / longest
    [ [ (width * ratio).round, 1 ].max, [ (height * ratio).round, 1 ].max ]
  end

  # Runs ffmpeg to write a single scaled JPEG to `output`, returning whether it
  # succeeded. Seeking before -i is ffmpeg's fast input seek — accurate enough for
  # a poster frame and cheap. Any failure is logged and reported as false.
  #
  # Each argument is passed positionally, so Open3 execs ffmpeg directly with no
  # shell in between — the scale filter's interpolated width/height are integers
  # from #scaled_dimensions and never reach a shell to be interpreted regardless.
  def run(input, output, at_seconds:, width:, height:)
    _stdout, stderr, status = Open3.capture3(
      "ffmpeg", "-y",
      "-ss", format("%.3f", at_seconds),
      "-i", input,
      "-frames:v", "1",
      "-vf", "scale=#{width}:#{height}",
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
end
