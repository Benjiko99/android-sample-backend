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
    assert_equal false, post["isLiked"], "u1 authored p1, so u1 cannot have liked it"
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
    post "/api/posts/p1/bookmark", headers: headers
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

  test "an author cannot like their own post" do
    assert_no_difference -> { PostLike.count } do
      post "/api/posts/p1/like", headers: headers("u1") # u1 authored p1
    end
    assert_response :forbidden
    assert_equal "FORBIDDEN", response.parsed_body["error"]["code"]

    get "/api/posts/p1", headers: headers("u1")
    assert_equal 128, response.parsed_body["data"]["likeCount"], "the counter must be untouched"
  end

  test "the self-like rule does not block liking someone else's post" do
    assert_difference -> { PostLike.count } => 1 do
      post "/api/posts/p2/like", headers: headers("u1") # u2 authored p2
    end
    assert_response :ok
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
