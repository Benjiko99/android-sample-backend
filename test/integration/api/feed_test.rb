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

  # Serializing an uploaded photo or video touches its attachment and blob, so a
  # missing eager-load turns into a query per media row. That is invisible to the
  # assertions above — the payload is identical either way — hence a query count.
  test "the feed does not issue per-attachment queries for uploaded media" do
    3.times do |i|
      post "/api/posts",
        params: { title: "Album #{i}", body: "Body",
                  images: Array.new(3) { fixture_file_upload("avatar.png", "image/png") } },
        headers: headers
    end
    post "/api/posts",
      params: { title: "Clip", body: "Body", video: fixture_file_upload("clip.mp4", "video/mp4") },
      headers: headers

    queries = 0
    counter = ->(_name, _start, _finish, _id, payload) do
      queries += 1 unless payload[:name] == "SCHEMA" || payload[:sql].start_with?("TRANSACTION")
    end

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      get "/api/feed", headers: headers
    end
    assert_response :ok

    # 10 posts, 9 uploaded photos and 1 uploaded video across them. Eager-loaded
    # this is a fixed handful of queries; unbatched it climbs past 20.
    assert_operator queries, :<, 20, "feed issued #{queries} queries — an eager-load is missing"
  end

  test "camelCase fields and viewer-scoped flags for u1" do
    get "/api/feed", headers: headers("u1")
    by_id = response.parsed_body["data"].index_by { |p| p["id"] }

    assert_equal true, by_id["p4"]["isLiked"]        # u1 liked p4
    assert_equal false, by_id["p1"]["isLiked"]       # u1 authored p1 — a self-like is refused
    assert_equal true, by_id["p2"]["isBookmarked"]   # u1 bookmarked p2
    assert_equal %w[id title body createdAt likeCount commentCount isLiked isBookmarked album video authorId].sort,
                 by_id["p1"].keys.sort
  end

  test "flags differ for a different viewer" do
    get "/api/feed", headers: headers("u2")
    by_id = response.parsed_body["data"].index_by { |p| p["id"] }
    assert_equal false, by_id["p4"]["isLiked"] # u1 liked p4, u2 did not
    assert_equal true, by_id["p1"]["isLiked"]  # but u2 did like p1
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

  test "include=author attaches users" do
    get "/api/feed?include=author", headers: headers
    included = response.parsed_body["included"]
    assert included.present?
    user = included["users"].first
    assert_equal USER_KEYS, user.keys.sort
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
