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
