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

  test "GET /api/users/:id/posts filters by type" do
    get "/api/users/u1/posts?type=photo", headers: headers
    assert_response :ok
    ids = response.parsed_body["data"].map { |p| p["id"] }
    assert_equal ["p1"], ids # only p1 has an album

    get "/api/users/u1/posts?type=text", headers: headers
    assert_equal ["p6"], response.parsed_body["data"].map { |p| p["id"] }
  end

  test "GET /api/users/:id/posts rejects an invalid type" do
    get "/api/users/u1/posts?type=weird", headers: headers
    assert_response :unprocessable_entity
    assert_equal "VALIDATION_ERROR", response.parsed_body["error"]["code"]
  end
end
