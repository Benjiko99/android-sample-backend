require "test_helper"

# The shape of a poster frame is ffmpeg's to decide, so unlike a pure helper it can
# only be pinned by running ffmpeg — these tests extract real frames from the two
# fixture clips and measure what came out. ffmpeg is the app's one system binary
# (it is in the Dockerfile and in CI); where it is missing, the module degrades to
# no thumbnail and there is nothing here to assert, so the tests skip.
class VideoThumbnailTest < ActiveSupport::TestCase
  include ActionDispatch::TestProcess::FixtureFile

  setup do
    skip("ffmpeg is not installed") unless ffmpeg?
  end

  # The bug this fixture exists for: it is stored 1440×810 with a 90° display
  # matrix — the shape a phone records portrait video in — so the container's own
  # width/height describe a landscape frame that is never displayed. Sizing the
  # still from those numbers squashed every such clip into a 16:9 still.
  test "a rotated portrait clip keeps its portrait shape" do
    thumbnail = generate("rotated_clip.mp4")

    assert_equal [ 405, 720 ], [ thumbnail.width, thumbnail.height ]
    assert_equal [ thumbnail.width, thumbnail.height ], measure(thumbnail.bytes),
      "the recorded dimensions should be the JPEG's own"
  end

  test "a clip already within the cap is left at its own size, never upscaled" do
    thumbnail = generate("small_clip.mp4")

    assert_equal [ 320, 240 ], [ thumbnail.width, thumbnail.height ]
  end

  test "the longest edge is capped at MAX_EDGE" do
    thumbnail = generate("rotated_clip.mp4")

    assert_equal VideoThumbnail::MAX_EDGE, [ thumbnail.width, thumbnail.height ].max
  end

  test "no thumbnail is produced from a file ffmpeg cannot read" do
    # The 40-byte stub fixture: a bare MP4 header with no decodable stream.
    assert_nil generate("clip.mp4")
  end

  # The frame is carried as bytes rather than an open file on purpose: it is attached
  # inside a transaction, and Active Storage does not read a blob until that commits,
  # by which point any handle opened here would be closed. See PostsService.
  test "a thumbnail carries bytes, so it outlives the file it was read from" do
    thumbnail = generate("small_clip.mp4")

    assert_not thumbnail.bytes.empty?, "a thumbnail should carry its JPEG"
    assert_not thumbnail.respond_to?(:io), "a thumbnail must not hand out a file handle"
  end

  private

  def generate(fixture)
    VideoThumbnail.generate(fixture_file_upload(fixture, "video/mp4"), at_seconds: 0.5)
  end

  # The pixel size of a JPEG held in memory, read back the way the module reads it.
  def measure(bytes)
    Tempfile.create(%w[measured .jpg], binmode: true) do |file|
      file.write(bytes)
      file.flush
      VideoThumbnail.dimensions_of(file.path)
    end
  end

  def ffmpeg?
    system("ffmpeg", "-version", out: File::NULL, err: File::NULL)
  end
end
