require "test_helper"

class Api::CommentsTest < ActionDispatch::IntegrationTest
  setup { Reseed.call }

  test "lists comments newest-first with page meta" do
    get "/api/posts/p3/comments?limit=2", headers: headers
    assert_response :ok
    body = response.parsed_body
    assert_equal %w[c3p3 c2p3], body["data"].map { |c| c["id"] }
    assert_equal true, body["page"]["has_more"]
    assert_equal %w[id text createdAt likeCount isLiked author].sort, body["data"].first.keys.sort
  end

  test "creates a comment and trims text" do
    assert_difference -> { Comment.count } => 1 do
      post "/api/posts/p6/comments", params: { text: "  Nice!  " }, as: :json, headers: headers
    end
    assert_response :created
    comment = response.parsed_body["data"]
    assert_equal "Nice!", comment["text"]
    assert_equal false, comment["isLiked"]
    assert_equal "u1", comment["author"]["id"]
  end

  # The count is not carried back on the create — the client bumps its own copy, since it
  # did not fetch the comment it would need to show. The next read is where it comes from,
  # and it comes from the rows.
  test "a created comment shows up in the post's commentCount on the next read" do
    before = comment_count_of("p6")

    post "/api/posts/p6/comments", params: { text: "Nice!" }, as: :json, headers: headers
    assert_response :created
    assert_nil response.parsed_body["data"]["commentCount"]

    assert_equal before + 1, comment_count_of("p6")
  end

  # The number under a post is the number of comments it has, on every surface that draws it.
  test "commentCount counts the post's comment rows" do
    expected = Comment.group(:post_id).count

    get "/api/posts/p3", headers: headers
    assert_equal expected["p3"], response.parsed_body["data"]["commentCount"]

    get "/api/feed?limit=10", headers: headers
    counts = response.parsed_body["data"].to_h { |p| [ p["id"], p["commentCount"] ] }
    assert_equal expected, counts.select { |_, count| count.positive? }
  end

  # A post nobody has commented on reports 0, not nil — it is absent from the grouped
  # count, which is exactly where a Hash without a default would leak a null onto the wire.
  test "a post with no comments reports zero" do
    Comment.where(post_id: "p6").delete_all

    get "/api/posts/p6", headers: headers
    assert_equal 0, response.parsed_body["data"]["commentCount"]

    get "/api/feed?limit=10", headers: headers
    p6 = response.parsed_body["data"].find { |p| p["id"] == "p6" }
    assert_equal 0, p6["commentCount"]
  end

  test "creating on a missing post 404s" do
    post "/api/posts/nope/comments", params: { text: "hi" }, as: :json, headers: headers
    assert_response :not_found
  end

  test "rejects blank/whitespace text with 422" do
    post "/api/posts/p6/comments", params: { text: "   " }, as: :json, headers: headers
    assert_response :unprocessable_entity
    assert_equal "VALIDATION_ERROR", response.parsed_body["error"]["code"]
  end

  test "sets a comment like on and off and adjusts the counter" do
    put "/api/posts/p6/comments/c1p6/like", params: { liked: true }, as: :json, headers: headers
    assert_equal({ "isLiked" => true, "likeCount" => 12 }, response.parsed_body["data"])
    put "/api/posts/p6/comments/c1p6/like", params: { liked: false }, as: :json, headers: headers
    assert_equal({ "isLiked" => false, "likeCount" => 11 }, response.parsed_body["data"])
  end

  # Comment likes share LikeState with post likes, so they are idempotent for the same reason.
  test "liking a comment twice is a no-op the second time" do
    put "/api/posts/p6/comments/c1p6/like", params: { liked: true }, as: :json, headers: headers

    assert_no_difference -> { CommentLike.count } do
      put "/api/posts/p6/comments/c1p6/like", params: { liked: true }, as: :json, headers: headers
    end
    assert_equal({ "isLiked" => true, "likeCount" => 12 }, response.parsed_body["data"])
  end

  test "a comment like without a state is refused" do
    put "/api/posts/p6/comments/c1p6/like", params: {}, as: :json, headers: headers
    assert_response :unprocessable_entity
  end

  private

  def comment_count_of(post_id)
    get "/api/posts/#{post_id}", headers: headers
    response.parsed_body["data"]["commentCount"]
  end
end
