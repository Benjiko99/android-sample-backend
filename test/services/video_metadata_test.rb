require "test_helper"

# The ffprobe wrapper. #parse is pure and covers every reading we can get back,
# rotation included, so the bulk of this runs whether or not ffmpeg is installed.
# Two tests shell out: one asserts the failure path (which is also what a machine
# with no ffprobe takes), and one pins the probe arguments themselves — that last
# needs a real ffprobe, so it skips without one.
class VideoMetadataTest < ActiveSupport::TestCase
  include ActionDispatch::TestProcess::FixtureFile

  def parse(streams:, format:)
    VideoMetadata.parse({ "streams" => streams, "format" => format }.to_json)
  end

  # A video stream carrying its rotation the way current ffprobe prints it.
  def side_data(width, height, rotation:)
    { "width" => width, "height" => height, "side_data_list" => [ { "rotation" => rotation } ] }
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

  # A phone records portrait video as a landscape frame plus a quarter-turn in the
  # display matrix. Reporting the stored pair described a frame no player ever shows.
  test "a quarter turn swaps the stored dimensions for the displayed ones" do
    turned = parse(streams: [ side_data(1440, 810, rotation: 90) ], format: {})

    assert_equal 810, turned.width
    assert_equal 1440, turned.height
  end

  test "a quarter turn either way swaps them" do
    [ 90, -90, 270, -270 ].each do |degrees|
      metadata = parse(streams: [ side_data(1440, 810, rotation: degrees) ], format: {})

      assert_equal [ 810, 1440 ], [ metadata.width, metadata.height ], "#{degrees}° should transpose"
    end
  end

  # Upside down is still the same shape, so the pair stands as read.
  test "a half turn and no turn leave the dimensions alone" do
    [ 0, 180, -180 ].each do |degrees|
      metadata = parse(streams: [ side_data(1440, 810, rotation: degrees) ], format: {})

      assert_equal [ 1440, 810 ], [ metadata.width, metadata.height ], "#{degrees}° should not transpose"
    end
  end

  # Older ffprobe builds print the rotation as a stream tag instead of side data.
  test "a rotation spelled as a stream tag is read too" do
    tagged = parse(
      streams: [ { "width" => 1440, "height" => 810, "tags" => { "rotate" => "90" } } ],
      format: {}
    )

    assert_equal 810, tagged.width
    assert_equal 1440, tagged.height
  end

  test "an unreadable rotation is no rotation" do
    metadata = parse(streams: [ side_data(1440, 810, rotation: "N/A") ], format: {})

    assert_equal [ 1440, 810 ], [ metadata.width, metadata.height ]
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

  # The pure tests above cannot catch a wrong -show_entries: asked for the wrong
  # entries, a real probe simply never mentions a rotation and everything reads as
  # upright. This one runs ffprobe to pin that ARGUMENTS fetches it at all.
  test "a real probe of a rotated clip reports its displayed resolution" do
    skip("ffmpeg is not installed") unless system("ffprobe", "-version", out: File::NULL, err: File::NULL)

    metadata = VideoMetadata.extract(fixture_file_upload("rotated_clip.mp4", "video/mp4"))

    assert_equal 810, metadata.width
    assert_equal 1440, metadata.height
  end
end
