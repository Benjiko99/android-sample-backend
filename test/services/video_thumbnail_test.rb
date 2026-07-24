require "test_helper"

# #scaled_dimensions is pure — it fixes the one size every poster frame is emitted
# at without touching ffmpeg, so it is covered here directly. The extraction that
# shells out is exercised end-to-end by the posts integration test, and degrades
# to no thumbnail when ffmpeg is absent.
class VideoThumbnailTest < ActiveSupport::TestCase
  test "scales the longest edge down to the cap, keeping aspect ratio" do
    assert_equal [ 720, 405 ], VideoThumbnail.scaled_dimensions(1920, 1080)
    assert_equal [ 405, 720 ], VideoThumbnail.scaled_dimensions(1080, 1920)
  end

  test "a video already within the cap is left untouched, never upscaled" do
    assert_equal [ 320, 240 ], VideoThumbnail.scaled_dimensions(320, 240)
    assert_equal [ 720, 480 ], VideoThumbnail.scaled_dimensions(720, 480)
  end

  test "an extreme aspect ratio never rounds an edge below one pixel" do
    width, height = VideoThumbnail.scaled_dimensions(4000, 10)

    assert_equal 720, width
    assert_operator height, :>=, 1
  end

  test "no thumbnail is produced when the resolution is unknown" do
    # Without dimensions there is nothing to scale to, so #generate bails before
    # it ever reads the file — hence no upload is needed to exercise this.
    assert_nil VideoThumbnail.generate(nil, width: nil, height: nil, at_seconds: 0.0)
  end
end
