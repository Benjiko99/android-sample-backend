require "test_helper"

class Api::FeedTest < ActionDispatch::IntegrationTest
  setup { Reseed.call }

  test "returns feed items newest-first with page meta" do
    get "/api/feed", headers: headers
    assert_response :ok
    body = response.parsed_body

    assert_equal %w[p1 p2 p3 p4 p5 p6], body["data"].map { |p| p["id"] }
    item = body["data"].first
    assert_equal "u1", item["authorId"]
    assert_not item.key?("author"), "feed items use authorId, not an embedded author"
    assert_equal false, body["page"]["has_more"]
    assert_nil body["page"]["next_cursor"]
  end

  test "camelCase fields and viewer-scoped flags for u1" do
    get "/api/feed", headers: headers("u1")
    by_id = response.parsed_body["data"].index_by { |p| p["id"] }

    assert_equal true, by_id["p1"]["isLiked"]        # u1 liked p1
    assert_equal true, by_id["p2"]["isBookmarked"]   # u1 bookmarked p2
    assert_equal %w[id title body createdAt likeCount commentCount isLiked isBookmarked album video authorId].sort,
                 by_id["p1"].keys.sort
  end

  test "flags differ for a different viewer" do
    get "/api/feed", headers: headers("u2")
    by_id = response.parsed_body["data"].index_by { |p| p["id"] }
    assert_equal false, by_id["p1"]["isLiked"]
  end

  test "keyset pagination walks the whole feed without overlap" do
    get "/api/feed?limit=2", headers: headers
    first = response.parsed_body
    assert_equal %w[p1 p2], first["data"].map { |p| p["id"] }
    assert_equal true, first["page"]["has_more"]

    get "/api/feed?limit=2&cursor=#{first["page"]["next_cursor"]}", headers: headers
    second = response.parsed_body
    assert_equal %w[p3 p4], second["data"].map { |p| p["id"] }
  end

  test "include=author attaches minimal users" do
    get "/api/feed?include=author", headers: headers
    included = response.parsed_body["included"]
    assert included.present?
    user = included["users"].first
    assert_equal %w[id handle nickname avatarUrl].sort, user.keys.sort
  end

  test "omits included by default" do
    get "/api/feed", headers: headers
    assert_not response.parsed_body.key?("included")
  end

  test "rejects a malformed cursor with 400" do
    get "/api/feed?cursor=@@@bad", headers: headers
    assert_response :bad_request
    assert_equal "BAD_REQUEST", response.parsed_body["error"]["code"]
  end
end
