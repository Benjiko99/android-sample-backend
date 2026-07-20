require "test_helper"

class Api::BookmarksTest < ActionDispatch::IntegrationTest
  setup { Reseed.call }

  test "returns the caller's bookmarked posts, newest first" do
    get "/api/users/u1/bookmarks", headers: headers("u1")
    assert_response :ok
    body = response.parsed_body

    # u1 bookmarked p2 and p4; ordering follows the posts' own recency.
    assert_equal %w[p2 p4], body["data"].map { |p| p["id"] }
    assert_equal false, body["page"]["has_more"]
  end

  test "bookmarks are private — another user's are 403, not readable" do
    get "/api/users/u1/bookmarks", headers: headers("u2")
    assert_response :forbidden
    assert_equal "FORBIDDEN", response.parsed_body["error"]["code"]
  end

  # The 403 comes before any lookup, so an unknown id can't be used to probe which
  # users exist — a caller only ever learns about their own bookmarks.
  test "a caller may not read a nonexistent user's bookmarks either" do
    get "/api/users/nope/bookmarks", headers: headers("u1")
    assert_response :forbidden
  end

  test "a caller with no bookmarks gets an empty page" do
    get "/api/users/u3/bookmarks", headers: headers("u3")
    assert_response :ok
    assert_equal [], response.parsed_body["data"]
  end

  # Saved posts are by arbitrary authors, so — unlike the profile's own Posts tab —
  # the client cannot supply them and the authors always ride along.
  test "always includes the authors of the page" do
    get "/api/users/u1/bookmarks", headers: headers("u1")
    included = response.parsed_body["included"]

    assert_equal %w[u2 u4], included["users"].map { |u| u["id"] }.sort
    assert_equal USER_KEYS, included["users"].first.keys.sort
  end

  test "bookmarking a post adds it to the list and unbookmarking removes it" do
    post "/api/posts/p3/bookmark", headers: headers("u1")

    get "/api/users/u1/bookmarks", headers: headers("u1")
    assert_equal %w[p2 p3 p4], response.parsed_body["data"].map { |p| p["id"] }

    post "/api/posts/p3/bookmark", headers: headers("u1")

    get "/api/users/u1/bookmarks", headers: headers("u1")
    assert_equal %w[p2 p4], response.parsed_body["data"].map { |p| p["id"] }
  end

  test "items carry the caller's own viewer flags" do
    get "/api/users/u1/bookmarks", headers: headers("u1")
    by_id = response.parsed_body["data"].index_by { |p| p["id"] }

    assert_equal true, by_id["p2"]["isBookmarked"]
    assert_equal true, by_id["p4"]["isLiked"] # u1 liked p4
    assert_equal false, by_id["p2"]["isLiked"]
  end

  test "keyset pagination walks the bookmarks without overlap" do
    get "/api/users/u1/bookmarks?limit=1", headers: headers("u1")
    first = response.parsed_body
    assert_equal %w[p2], first["data"].map { |p| p["id"] }
    assert_equal true, first["page"]["has_more"]

    get "/api/users/u1/bookmarks?limit=1&cursor=#{first["page"]["next_cursor"]}", headers: headers("u1")
    assert_equal %w[p4], response.parsed_body["data"].map { |p| p["id"] }
  end

  test "rejects a malformed cursor with 400" do
    get "/api/users/u1/bookmarks?cursor=@@@bad", headers: headers("u1")
    assert_response :bad_request
  end

  test "deleting a post removes it from the bookmarks that held it" do
    delete "/api/posts/p2", headers: headers("u2")

    get "/api/users/u1/bookmarks", headers: headers("u1")
    assert_equal %w[p4], response.parsed_body["data"].map { |p| p["id"] }
  end
end
