require "test_helper"

# The ffprobe wrapper. #parse is pure and covers the readings we can get back;
# the one test that shells out asserts the failure path, so the suite behaves
# the same whether or not ffmpeg is installed on the machine running it.
class VideoMetadataTest < ActiveSupport::TestCase
  def parse(streams:, format:)
    VideoMetadata.parse({ "streams" => streams, "format" => format }.to_json)
  end

  test "reads duration and dimensions from a well-formed probe" do
    metadata = parse(streams: [ { "width" => 1920, "height" => 1080 } ], format: { "duration" => "12.480000" })

    assert_equal 12, metadata.duration_seconds
    assert_equal 1920, metadata.width
    assert_equal 1080, metadata.height
  end

  test "rounds a fractional duration to whole seconds" do
    assert_equal 12, parse(streams: [], format: { "duration" => "12.480000" }).duration_seconds
    assert_equal 13, parse(streams: [], format: { "duration" => "12.510000" }).duration_seconds
  end

  test "a stream that declares no duration reads as zero" do
    assert_equal 0, parse(streams: [], format: { "duration" => "N/A" }).duration_seconds
    assert_equal 0, parse(streams: [], format: {}).duration_seconds
  end

  test "a negative duration is clamped to zero" do
    assert_equal 0, parse(streams: [], format: { "duration" => "-5.000000" }).duration_seconds
  end

  test "missing or zero dimensions read as nil, never zero" do
    metadata = parse(streams: [ { "width" => 0, "height" => nil } ], format: {})

    assert_nil metadata.width
    assert_nil metadata.height
  end

  test "a nil probe collapses to empty metadata" do
    metadata = VideoMetadata.parse(nil)

    assert_equal 0, metadata.duration_seconds
    assert_nil metadata.width
    assert_nil metadata.height
  end

  test "invalid probe output collapses to empty metadata" do
    metadata = VideoMetadata.parse("not json")

    assert_equal 0, metadata.duration_seconds
    assert_nil metadata.width
    assert_nil metadata.height
  end

  # The fixture is a bare MP4 header with no playable stream, so ffprobe exits
  # non-zero on it — as does the absence of ffprobe itself.
  test "probing a file with no readable metadata returns nil" do
    assert_nil VideoMetadata.probe(file_fixture("clip.mp4").to_s)
  end
end
