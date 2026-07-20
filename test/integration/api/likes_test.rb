require "test_helper"

class Api::LikesTest < ActionDispatch::IntegrationTest
  setup { Reseed.call }

  test "returns the user's liked posts, newest first" do
    get "/api/users/u1/likes", headers: headers("u1")
    assert_response :ok

    # u1 liked p3 and p4; ordering follows the posts' own recency.
    assert_equal %w[p3 p4], response.parsed_body["data"].map { |p| p["id"] }
  end

  # The whole difference from the Saved tab: likes are an endorsement on show, so
  # anyone may read anyone's.
  test "likes are public — another user may read them" do
    get "/api/users/u1/likes", headers: headers("u2")
    assert_response :ok
    assert_equal %w[p3 p4], response.parsed_body["data"].map { |p| p["id"] }
  end

  test "a user with no likes gets an empty page" do
    get "/api/users/u5/likes", headers: headers("u5")
    assert_response :ok
    assert_equal [], response.parsed_body["data"]
  end

  test "always includes the minimal authors of the page" do
    get "/api/users/u1/likes", headers: headers("u1")
    included = response.parsed_body["included"]

    assert_equal %w[u3 u4], included["users"].map { |u| u["id"] }.sort
    assert_equal %w[id handle nickname avatarUrl isFollowing].sort, included["users"].first.keys.sort
  end

  # The list is whose likes are being read, but the flags on each item belong to the
  # caller — u2 reading u1's likes sees u2's own isLiked/isBookmarked.
  test "items carry the caller's viewer flags, not the listed user's" do
    get "/api/users/u1/likes", headers: headers("u2")
    by_id = response.parsed_body["data"].index_by { |p| p["id"] }

    assert_equal false, by_id["p3"]["isLiked"]    # u2 has liked nothing
    assert_equal false, by_id["p4"]["isBookmarked"]
  end

  test "liking a post adds it to the list and unliking removes it" do
    post "/api/posts/p2/like", headers: headers("u1")

    get "/api/users/u1/likes", headers: headers("u1")
    assert_equal %w[p2 p3 p4], response.parsed_body["data"].map { |p| p["id"] }

    post "/api/posts/p2/like", headers: headers("u1")

    get "/api/users/u1/likes", headers: headers("u1")
    assert_equal %w[p3 p4], response.parsed_body["data"].map { |p| p["id"] }
  end

  # A self-like is refused, so a user's own posts can never show up in their Likes tab.
  test "a user's own posts never appear among their likes" do
    get "/api/users/u1/likes", headers: headers("u1")
    author_ids = response.parsed_body["data"].map { |p| p["authorId"] }

    assert_not_includes author_ids, "u1"
  end

  test "keyset pagination walks the likes without overlap" do
    get "/api/users/u1/likes?limit=1", headers: headers("u1")
    first = response.parsed_body
    assert_equal %w[p3], first["data"].map { |p| p["id"] }
    assert_equal true, first["page"]["has_more"]

    get "/api/users/u1/likes?limit=1&cursor=#{first["page"]["next_cursor"]}", headers: headers("u1")
    assert_equal %w[p4], response.parsed_body["data"].map { |p| p["id"] }
  end

  test "rejects a malformed cursor with 400" do
    get "/api/users/u1/likes?cursor=@@@bad", headers: headers("u1")
    assert_response :bad_request
  end

  test "deleting a post removes it from the likes that held it" do
    delete "/api/posts/p3", headers: headers("u3")

    get "/api/users/u1/likes", headers: headers("u1")
    assert_equal %w[p4], response.parsed_body["data"].map { |p| p["id"] }
  end
end
