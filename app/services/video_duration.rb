require "open3"

# How long an uploaded video runs, read off the file itself. The client used to
# report this alongside the upload; the server now measures it, so the stored
# length always describes the stored bytes.
#
# ffprobe (shipped with ffmpeg, installed in the Docker image) reads the
# container's metadata and stops — it never decodes the stream — so this is a
# header read on a local tempfile rather than a pass over the file, and stays
# inline in the request.
#
# Duration is display metadata: a clip whose length we cannot read is still a
# clip worth publishing. Every failure — no ffprobe on PATH, an unparseable
# container, a stream that declares no duration — degrades to 0 rather than
# rejecting an upload that already passed content-type and size validation.
module VideoDuration
  ARGUMENTS = %w[
    -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1
  ].freeze

  module_function

  # Takes the uploaded file — before it is attached, while it is still a tempfile
  # on disk — and returns whole seconds, never negative.
  def seconds(file)
    parse(probe(file.tempfile.path))
  end

  # ffprobe prints the duration in seconds ("12.480000"), or "N/A" for a stream
  # that declares none. Anything unreadable reads as 0, and a nonsense negative
  # is clamped, so what we store is always whole non-negative seconds.
  def parse(output)
    duration = Float(output.to_s.strip, exception: false)
    duration.nil? ? 0 : [ duration.round, 0 ].max
  end

  # Runs ffprobe over the file and hands back its raw stdout, or nil when it
  # could not be run or could not read the file.
  def probe(path)
    stdout, stderr, status = Open3.capture3("ffprobe", *ARGUMENTS, path)
    return stdout if status.success?

    Rails.logger.warn("ffprobe could not read a video duration: #{stderr.strip}")
    nil
  rescue SystemCallError => e
    # Most likely Errno::ENOENT — ffmpeg is not installed on this machine.
    Rails.logger.warn("ffprobe is unavailable, storing a zero video duration: #{e.message}")
    nil
  end
end
