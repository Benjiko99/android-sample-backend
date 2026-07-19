require "test_helper"

class Api::PostsTest < ActionDispatch::IntegrationTest
  setup { Reseed.call }

  test "GET /api/posts/:id returns a full post with embedded author" do
    get "/api/posts/p1", headers: headers
    assert_response :ok
    post = response.parsed_body["data"]

    assert_equal "p1", post["id"]
    assert_equal "u1", post["author"]["id"]
    assert_equal "Engine sketches", post["album"]["title"]
    assert_equal 3, post["album"]["images"].length
    assert_equal true, post["isLiked"]
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
                  video: fixture_file_upload("clip.mp4", "video/mp4"),
                  videoDurationSeconds: 42 },
        headers: headers
    end
    assert_response :created
    video = response.parsed_body["data"]["video"]

    assert_equal "A clip", video["title"]
    assert_equal 42, video["durationSeconds"]
    assert_match %r{\Ahttp://example\.com/.*active_storage}, video["videoUrl"]
    assert_nil response.parsed_body["data"]["album"]
  end

  test "an uploaded video survives a refetch and appears in the feed" do
    post "/api/posts",
      params: { title: "A clip", body: "Body",
                video: fixture_file_upload("clip.mp4", "video/mp4"),
                videoDurationSeconds: 7 },
      headers: headers
    id = response.parsed_body["data"]["id"]

    get "/api/posts/#{id}", headers: headers
    assert_response :ok
    assert_equal 7, response.parsed_body["data"]["video"]["durationSeconds"]

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

  test "a missing or negative video duration is stored as zero" do
    post "/api/posts",
      params: { title: "No duration", body: "Body",
                video: fixture_file_upload("clip.mp4", "video/mp4") },
      headers: headers
    assert_equal 0, response.parsed_body["data"]["video"]["durationSeconds"]

    post "/api/posts",
      params: { title: "Negative", body: "Body",
                video: fixture_file_upload("clip.mp4", "video/mp4"),
                videoDurationSeconds: -5 },
      headers: headers
    assert_equal 0, response.parsed_body["data"]["video"]["durationSeconds"]
  end

  test "a post cannot hold both an album and a video at the record level" do
    post = Post.new(author_id: "u1", title: "Both", body: "Body", album_id: "pa1", video_id: "pv3")

    assert_not post.valid?
    assert_includes post.errors.attribute_names, :video
  end

  test "like toggles on and off and adjusts the counter" do
    post "/api/posts/p2/like", headers: headers
    assert_response :ok
    assert_equal({ "isLiked" => true, "likeCount" => 343 }, response.parsed_body["data"])

    post "/api/posts/p2/like", headers: headers
    assert_equal({ "isLiked" => false, "likeCount" => 342 }, response.parsed_body["data"])
  end

  test "bookmark toggles on and off" do
    post "/api/posts/p3/bookmark", headers: headers
    assert_equal({ "isBookmarked" => true }, response.parsed_body["data"])
    post "/api/posts/p3/bookmark", headers: headers
    assert_equal({ "isBookmarked" => false }, response.parsed_body["data"])
  end

  test "GET /api/users/:id/posts returns the author's posts, newest first" do
    get "/api/users/u1/posts", headers: headers
    assert_response :ok
    assert_equal %w[p1 p6], response.parsed_body["data"].map { |p| p["id"] }
  end
end
