require "test_helper"

# The ffprobe wrapper. #parse is pure and covers the readings we can get back;
# the one test that shells out asserts the failure path, so the suite behaves
# the same whether or not ffmpeg is installed on the machine running it.
class VideoDurationTest < ActiveSupport::TestCase
  test "rounds a fractional duration to whole seconds" do
    assert_equal 12, VideoDuration.parse("12.480000\n")
    assert_equal 13, VideoDuration.parse("12.510000\n")
  end

  test "a stream that declares no duration reads as zero" do
    assert_equal 0, VideoDuration.parse("N/A\n")
    assert_equal 0, VideoDuration.parse("")
  end

  test "a failed probe reads as zero" do
    assert_equal 0, VideoDuration.parse(nil)
  end

  test "a negative duration is clamped to zero" do
    assert_equal 0, VideoDuration.parse("-5.000000")
  end

  # The fixture is a bare MP4 header with no playable stream, so ffprobe exits
  # non-zero on it — as does the absence of ffprobe itself.
  test "probing a file with no readable duration returns nil" do
    assert_nil VideoDuration.probe(file_fixture("clip.mp4").to_s)
  end
end
