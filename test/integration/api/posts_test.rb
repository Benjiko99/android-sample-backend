require "test_helper"

class Api::PostsTest < ActionDispatch::IntegrationTest
  setup { Reseed.call }

  # Active Storage defers a blob's *bytes* to an after_commit callback, so an attach
  # made inside PostsService's transaction is read only once that commits — after the
  # code that produced the frame has returned and cleaned up. Handing the frame over
  # as an open file therefore uploaded a closed stream and 500'd every video upload;
  # this pins that what is attached outlives the call that attached it.
  test "a thumbnail attached inside a transaction is uploaded when it commits" do
    video = Video.create!(user_id: "u1", title: "A clip", duration_seconds: 0)
    bytes = file_fixture("avatar.png").binread
    thumbnail = VideoThumbnail::Thumbnail.new(bytes: bytes, width: 640, height: 360)

    Post.transaction { PostsService.attach_thumbnail(video, thumbnail) }

    assert video.reload.thumbnail.attached?, "the poster frame should be attached"
    assert_equal bytes, video.thumbnail.blob.download, "the stored bytes should be the generated ones"
    assert_equal 640, video.thumbnail_width
    assert_equal 360, video.thumbnail_height
  end

  test "GET /api/posts/:id returns a full post with embedded author" do
    get "/api/posts/p1", headers: headers
    assert_response :ok
    post = response.parsed_body["data"]

    assert_equal "p1", post["id"]
    assert_equal "u1", post["author"]["id"]
    assert_equal "Engine sketches", post["album"]["title"]
    assert_equal 3, post["album"]["images"].length
    assert_equal false, post["isLiked"], "u1 authored p1, so u1 cannot have liked it"
  end

  test "every projection carries the post's shareable url" do
    get "/api/posts/p1", headers: headers
    assert_equal "http://example.com/p/p1", response.parsed_body["data"]["url"]

    get "/api/feed", headers: headers
    feed_item = response.parsed_body["data"].find { |p| p["id"] == "p1" }
    assert_equal "http://example.com/p/p1", feed_item["url"]

    post "/api/posts", params: { title: "T", body: "B" }, as: :json, headers: headers
    created = response.parsed_body["data"]
    assert_equal "http://example.com/p/#{created['id']}", created["url"]
  end

  test "GET /api/posts/:id 404s for a missing post" do
    get "/api/posts/nope", headers: headers
    assert_response :not_found
    assert_equal "NOT_FOUND", response.parsed_body["error"]["code"]
  end

  test "POST /api/posts creates a post authored by the caller and trims the text" do
    assert_difference -> { Post.count } => 1 do
      post "/api/posts",
        params: { title: "  Hello  ", body: "  World  " },
        as: :json,
        headers: headers("u2")
    end
    assert_response :created
    created = response.parsed_body["data"]

    assert_equal "Hello", created["title"]
    assert_equal "World", created["body"]
    assert_equal "u2", created["author"]["id"]
    assert_equal 0, created["likeCount"]
    assert_equal 0, created["commentCount"]
    assert_equal false, created["isLiked"]
    assert_equal false, created["isBookmarked"]
    assert_nil created["album"]
    assert_nil created["video"]
  end

  test "a created post appears at the top of the feed and on its author's profile" do
    post "/api/posts", params: { title: "Newest", body: "Body" }, as: :json, headers: headers
    id = response.parsed_body["data"]["id"]

    get "/api/feed", headers: headers
    assert_equal id, response.parsed_body["data"].first["id"]

    get "/api/users/u1/posts", headers: headers
    assert_equal id, response.parsed_body["data"].first["id"]
  end

  test "POST /api/posts rejects blank title or body with 422" do
    post "/api/posts", params: { title: "   ", body: "Body" }, as: :json, headers: headers
    assert_response :unprocessable_entity
    assert_equal "VALIDATION_ERROR", response.parsed_body["error"]["code"]
    assert_equal "title", response.parsed_body["error"]["details"].first["path"]

    post "/api/posts", params: { title: "Title", body: "" }, as: :json, headers: headers
    assert_response :unprocessable_entity
    assert_equal "body", response.parsed_body["error"]["details"].first["path"]
  end

  test "POST /api/posts 404s when the caller is not a known user" do
    post "/api/posts", params: { title: "T", body: "B" }, as: :json, headers: headers("ghost")
    assert_response :not_found
  end

  test "POST /api/posts attaches uploaded images as the post's album" do
    assert_difference -> { Album.count } => 1, -> { Photo.count } => 2 do
      post "/api/posts",
        params: { title: "Sketches", body: "Two of them",
                  images: [ fixture_file_upload("avatar.png", "image/png"),
                           fixture_file_upload("avatar.png", "image/png") ] },
        headers: headers
    end
    assert_response :created
    album = response.parsed_body["data"]["album"]

    assert_equal "Sketches", album["title"]
    assert_equal 2, album["itemCount"]
    assert_equal 2, album["images"].length
    album["images"].each { |url| assert_match %r{\Ahttp://example\.com/.*active_storage}, url }
  end

  test "an uploaded album survives a refetch and serves every image" do
    post "/api/posts",
      params: { title: "Sketches", body: "Body",
                images: Array.new(4) { fixture_file_upload("avatar.png", "image/png") } },
      headers: headers
    id = response.parsed_body["data"]["id"]

    get "/api/posts/#{id}", headers: headers
    assert_response :ok
    assert_equal 4, response.parsed_body["data"]["album"]["images"].length
  end

  test "POST /api/posts with no images creates no album" do
    assert_no_difference -> { Album.count } do
      post "/api/posts", params: { title: "Text only", body: "Body" }, headers: headers
    end
    assert_nil response.parsed_body["data"]["album"]
  end

  test "POST /api/posts rejects a non-image upload and stores nothing" do
    assert_no_difference [ -> { Post.count }, -> { Album.count }, -> { Photo.count } ] do
      post "/api/posts",
        params: { title: "Sketches", body: "Body",
                  images: [ fixture_file_upload("avatar.png", "image/png"),
                           fixture_file_upload("not_an_image.txt", "text/plain") ] },
        headers: headers
    end
    assert_response :unprocessable_entity

    detail = response.parsed_body["error"]["details"].first
    assert_equal "images.1", detail["path"]
    assert_equal "invalid_content_type", detail["code"]
  end

  test "POST /api/posts rejects more than the per-album image limit" do
    assert_no_difference -> { Photo.count } do
      post "/api/posts",
        params: { title: "Too many", body: "Body",
                  images: Array.new(Album::MAX_PHOTOS + 1) { fixture_file_upload("avatar.png", "image/png") } },
        headers: headers
    end
    assert_response :unprocessable_entity
    assert_equal "too_many", response.parsed_body["error"]["details"].first["code"]
  end

  test "a blank title with images uploads nothing" do
    assert_no_difference [ -> { Album.count }, -> { Photo.count } ] do
      post "/api/posts",
        params: { title: "   ", body: "Body",
                  images: [ fixture_file_upload("avatar.png", "image/png") ] },
        headers: headers
    end
    assert_response :unprocessable_entity
    assert_equal "title", response.parsed_body["error"]["details"].first["path"]
  end

  test "POST /api/posts attaches an uploaded video to the post" do
    assert_difference -> { Video.count } => 1 do
      post "/api/posts",
        params: { title: "A clip", body: "Recorded today",
                  video: fixture_file_upload("clip.mp4", "video/mp4") },
        headers: headers
    end
    assert_response :created
    video = response.parsed_body["data"]["video"]

    assert_equal "A clip", video["title"]
    assert_equal VideoMetadata.extract(fixture_file_upload("clip.mp4", "video/mp4")).duration_seconds, video["durationSeconds"]
    assert_match %r{\Ahttp://example\.com/.*active_storage}, video["videoUrl"]
    assert_nil response.parsed_body["data"]["album"]
  end

  # A sample video is external, so it carries a poster frame and resolution as
  # fixed sample values rather than measured ones.
  test "a seed video serves a thumbnail url and resolution" do
    get "/api/posts/p3", headers: headers
    assert_response :ok
    video = response.parsed_body["data"]["video"]

    assert_equal 1280, video["width"]
    assert_equal 720, video["height"]
    assert_match %r{\Ahttps://.*\.jpg\z}, video["thumbnailUrl"]
    assert_equal 640, video["thumbnailWidth"]
    assert_equal 360, video["thumbnailHeight"]
  end

  # The fixture is a bare MP4 header: its resolution cannot be read and no poster
  # frame can be extracted (nor can anything, without ffmpeg). Rather than fail
  # the upload, the video publishes with a null resolution and no thumbnail.
  test "a video whose resolution cannot be read has a null resolution and no thumbnail" do
    post "/api/posts",
      params: { title: "No resolution", body: "Body",
                video: fixture_file_upload("clip.mp4", "video/mp4") },
      headers: headers
    assert_response :created
    video = response.parsed_body["data"]["video"]

    assert_nil video["width"]
    assert_nil video["height"]
    assert_nil video["thumbnailUrl"]
    assert_nil video["thumbnailWidth"]
    assert_nil video["thumbnailHeight"]
  end

  test "an uploaded video survives a refetch and appears in the feed" do
    post "/api/posts",
      params: { title: "A clip", body: "Body",
                video: fixture_file_upload("clip.mp4", "video/mp4") },
      headers: headers
    id = response.parsed_body["data"]["id"]

    get "/api/posts/#{id}", headers: headers
    assert_response :ok
    assert_not_nil response.parsed_body["data"]["video"]["durationSeconds"]

    get "/api/feed", headers: headers
    assert_equal id, response.parsed_body["data"].first["id"]
    assert_not_nil response.parsed_body["data"].first["video"]["videoUrl"]
  end

  test "POST /api/posts rejects photos and a video together, storing neither" do
    assert_no_difference [ -> { Post.count }, -> { Album.count }, -> { Video.count } ] do
      post "/api/posts",
        params: { title: "Both", body: "Body",
                  images: [ fixture_file_upload("avatar.png", "image/png") ],
                  video: fixture_file_upload("clip.mp4", "video/mp4") },
        headers: headers
    end
    assert_response :unprocessable_entity

    detail = response.parsed_body["error"]["details"].first
    assert_equal "video", detail["path"]
    assert_equal "media_conflict", detail["code"]
  end

  test "POST /api/posts rejects a non-video upload in the video slot" do
    assert_no_difference [ -> { Post.count }, -> { Video.count } ] do
      post "/api/posts",
        params: { title: "Bad", body: "Body",
                  video: fixture_file_upload("avatar.png", "image/png") },
        headers: headers
    end
    assert_response :unprocessable_entity
    assert_equal "invalid_content_type", response.parsed_body["error"]["details"].first["code"]
  end

  # The duration is measured from the file now, so a client still sending the old
  # field gets no say in it — least of all one inflating the length it claims.
  test "a client-reported video duration is ignored" do
    post "/api/posts",
      params: { title: "A clip", body: "Body",
                video: fixture_file_upload("clip.mp4", "video/mp4"),
                videoDurationSeconds: 999 },
      headers: headers
    assert_response :created
    assert_equal 0, response.parsed_body["data"]["video"]["durationSeconds"]
  end

  # The fixture is a bare MP4 header with no playable stream: ffprobe reads no
  # duration from it (nor does anything, if ffmpeg isn't installed). The post is
  # still published — an unreadable length is not a reason to refuse an upload.
  test "a video whose duration cannot be read is stored as zero" do
    assert_difference -> { Video.count } => 1 do
      post "/api/posts",
        params: { title: "No duration", body: "Body",
                  video: fixture_file_upload("clip.mp4", "video/mp4") },
        headers: headers
    end
    assert_response :created
    assert_equal 0, response.parsed_body["data"]["video"]["durationSeconds"]
  end

  test "a post cannot hold both an album and a video at the record level" do
    post = Post.new(author_id: "u1", title: "Both", body: "Body", album_id: "pa1", video_id: "pv3")

    assert_not post.valid?
    assert_includes post.errors.attribute_names, :video
  end

  test "DELETE /api/posts/:id removes the caller's own post" do
    assert_difference -> { Post.count } => -1 do
      delete "/api/posts/p1", headers: headers("u1")
    end
    assert_response :no_content

    get "/api/posts/p1", headers: headers
    assert_response :not_found
  end

  test "a deleted post disappears from the feed and its author's profile" do
    delete "/api/posts/p1", headers: headers("u1")

    get "/api/feed", headers: headers
    assert_not_includes response.parsed_body["data"].map { |p| p["id"] }, "p1"

    get "/api/users/u1/posts", headers: headers
    assert_equal %w[p6], response.parsed_body["data"].map { |p| p["id"] }
  end

  test "DELETE /api/posts/:id 403s for a caller who is not the author" do
    assert_no_difference -> { Post.count } do
      delete "/api/posts/p1", headers: headers("u2")
    end
    assert_response :forbidden
    assert_equal "FORBIDDEN", response.parsed_body["error"]["code"]
  end

  test "DELETE /api/posts/:id 404s for a missing post" do
    delete "/api/posts/nope", headers: headers
    assert_response :not_found
  end

  test "deleting a post takes its comments, likes and bookmarks with it" do
    put "/api/posts/p1/bookmark", params: { bookmarked: true }, as: :json, headers: headers
    assert_operator Comment.where(post_id: "p1").count, :>, 0
    assert_operator PostLike.where(post_id: "p1").count, :>, 0

    delete "/api/posts/p1", headers: headers("u1")

    assert_equal 0, Comment.where(post_id: "p1").count
    assert_equal 0, PostLike.where(post_id: "p1").count
    assert_equal 0, PostBookmark.where(post_id: "p1").count
  end

  test "deleting a post destroys the album it was created with" do
    post "/api/posts",
      params: { title: "Sketches", body: "Body",
                images: [ fixture_file_upload("avatar.png", "image/png") ] },
      headers: headers
    id = response.parsed_body["data"]["id"]

    assert_difference -> { Album.count } => -1, -> { Photo.count } => -1 do
      delete "/api/posts/#{id}", headers: headers
    end
    assert_response :no_content
  end

  test "deleting a post destroys the video it was created with" do
    post "/api/posts",
      params: { title: "A clip", body: "Body", video: fixture_file_upload("clip.mp4", "video/mp4") },
      headers: headers
    id = response.parsed_body["data"]["id"]

    assert_difference -> { Video.count } => -1 do
      delete "/api/posts/#{id}", headers: headers
    end
  end

  test "deleting a post leaves media another post still holds" do
    shared = Post.find("p1").album_id
    assert_not_nil shared
    Post.create!(author_id: "u1", title: "Same album", body: "Body", album_id: shared)

    assert_no_difference -> { Album.count } do
      delete "/api/posts/p1", headers: headers("u1")
    end
  end

  test "an author can like their own post" do
    assert_difference -> { PostLike.count } => 1 do
      put "/api/posts/p1/like", params: { liked: true }, as: :json, headers: headers("u1") # u1 authored p1
    end
    assert_response :ok
    assert_equal({ "isLiked" => true, "likeCount" => 129 }, response.parsed_body["data"])

    put "/api/posts/p1/like", params: { liked: false }, as: :json, headers: headers("u1")
    assert_equal({ "isLiked" => false, "likeCount" => 128 }, response.parsed_body["data"])
  end

  test "like goes on and off and adjusts the counter" do
    put "/api/posts/p2/like", params: { liked: true }, as: :json, headers: headers
    assert_response :ok
    assert_equal({ "isLiked" => true, "likeCount" => 343 }, response.parsed_body["data"])

    put "/api/posts/p2/like", params: { liked: false }, as: :json, headers: headers
    assert_equal({ "isLiked" => false, "likeCount" => 342 }, response.parsed_body["data"])
  end

  # The whole point of setting a state rather than flipping one: a client that retries a
  # request it never saw the answer to, or fires a second tap before the first lands, must
  # not move the like twice.
  test "liking a post twice is a no-op the second time" do
    put "/api/posts/p2/like", params: { liked: true }, as: :json, headers: headers
    assert_equal({ "isLiked" => true, "likeCount" => 343 }, response.parsed_body["data"])

    assert_no_difference -> { PostLike.count } do
      put "/api/posts/p2/like", params: { liked: true }, as: :json, headers: headers
    end
    assert_equal({ "isLiked" => true, "likeCount" => 343 }, response.parsed_body["data"])
  end

  test "unliking a post that was never liked is a no-op" do
    assert_no_difference -> { PostLike.count } do
      put "/api/posts/p2/like", params: { liked: false }, as: :json, headers: headers
    end
    assert_response :ok
    assert_equal({ "isLiked" => false, "likeCount" => 342 }, response.parsed_body["data"])
  end

  test "bookmark goes on and off" do
    put "/api/posts/p3/bookmark", params: { bookmarked: true }, as: :json, headers: headers
    assert_equal({ "isBookmarked" => true }, response.parsed_body["data"])
    put "/api/posts/p3/bookmark", params: { bookmarked: false }, as: :json, headers: headers
    assert_equal({ "isBookmarked" => false }, response.parsed_body["data"])
  end

  test "bookmarking a post twice is a no-op the second time" do
    put "/api/posts/p3/bookmark", params: { bookmarked: true }, as: :json, headers: headers

    assert_no_difference -> { PostBookmark.count } do
      put "/api/posts/p3/bookmark", params: { bookmarked: true }, as: :json, headers: headers
    end
    assert_equal({ "isBookmarked" => true }, response.parsed_body["data"])
  end

  # Idempotency only holds while the state asked for is unambiguous, so anything that is
  # not a JSON boolean is refused rather than guessed at.
  test "a like without a state is refused" do
    put "/api/posts/p2/like", params: {}, as: :json, headers: headers
    assert_response :unprocessable_entity
    assert_equal "liked", response.parsed_body["error"]["details"].first["path"]
  end

  test "a like with a non-boolean state is refused" do
    put "/api/posts/p2/like", params: { liked: "true" }, as: :json, headers: headers
    assert_response :unprocessable_entity
  end

  test "a bookmark without a state is refused" do
    put "/api/posts/p3/bookmark", params: {}, as: :json, headers: headers
    assert_response :unprocessable_entity
    assert_equal "bookmarked", response.parsed_body["error"]["details"].first["path"]
  end

  test "PUT /api/posts/:id/like 404s for a missing post" do
    put "/api/posts/nope/like", params: { liked: true }, as: :json, headers: headers
    assert_response :not_found
  end

  # Reporting is accepted and checked, then dropped: there is no moderation queue behind
  # it, so the endpoint's whole contract is the validation and the 204.
  test "POST /api/posts/:id/report accepts a report and stores nothing" do
    assert_no_difference -> { Post.count } do
      post "/api/posts/p1/report",
        params: { reason: "spam", details: "  Posted this five times  " },
        as: :json,
        headers: headers("u2")
    end
    assert_response :no_content
    assert_predicate response.body, :empty?
  end

  test "POST /api/posts/:id/report accepts a report with no details" do
    post "/api/posts/p1/report", params: { reason: "other" }, as: :json, headers: headers("u2")
    assert_response :no_content
  end

  test "POST /api/posts/:id/report accepts every reason the client offers" do
    PostsService::REPORT_REASONS.each do |reason|
      post "/api/posts/p1/report", params: { reason: reason }, as: :json, headers: headers("u2")
      assert_response :no_content, "'#{reason}' should be a reportable reason"
    end
  end

  test "POST /api/posts/:id/report rejects an unknown reason with 422" do
    post "/api/posts/p1/report", params: { reason: "boring" }, as: :json, headers: headers("u2")
    assert_response :unprocessable_entity

    detail = response.parsed_body["error"]["details"].first
    assert_equal "reason", detail["path"]
    assert_equal "invalid_enum_value", detail["code"]
  end

  test "POST /api/posts/:id/report rejects a missing reason with 422" do
    post "/api/posts/p1/report", params: {}, as: :json, headers: headers("u2")
    assert_response :unprocessable_entity
    assert_equal "reason", response.parsed_body["error"]["details"].first["path"]
  end

  test "POST /api/posts/:id/report rejects over-long details with 422" do
    post "/api/posts/p1/report",
      params: { reason: "spam", details: "x" * (PostsService::REPORT_DETAILS_MAX_LENGTH + 1) },
      as: :json,
      headers: headers("u2")
    assert_response :unprocessable_entity

    detail = response.parsed_body["error"]["details"].first
    assert_equal "details", detail["path"]
    assert_equal "too_long", detail["code"]
  end

  test "POST /api/posts/:id/report 404s for a missing post" do
    post "/api/posts/nope/report", params: { reason: "spam" }, as: :json, headers: headers("u2")
    assert_response :not_found
    assert_equal "NOT_FOUND", response.parsed_body["error"]["code"]
  end

  test "GET /api/users/:id/posts returns the author's posts, newest first" do
    get "/api/users/u1/posts", headers: headers
    assert_response :ok
    assert_equal %w[p1 p6], response.parsed_body["data"].map { |p| p["id"] }
  end
end
