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

  test "creates a comment, trims text, and bumps the post counter" do
    assert_difference -> { Comment.count } => 1, -> { Post.find("p6").comment_count } => 1 do
      post "/api/posts/p6/comments", params: { text: "  Nice!  " }, as: :json, headers: headers
    end
    assert_response :created
    comment = response.parsed_body["data"]
    assert_equal "Nice!", comment["text"]
    assert_equal false, comment["isLiked"]
    assert_equal "u1", comment["author"]["id"]
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

  test "toggles a comment like and adjusts the counter" do
    post "/api/posts/p6/comments/c1p6/like", headers: headers
    assert_equal({ "isLiked" => true, "likeCount" => 12 }, response.parsed_body["data"])
    post "/api/posts/p6/comments/c1p6/like", headers: headers
    assert_equal({ "isLiked" => false, "likeCount" => 11 }, response.parsed_body["data"])
  end
end
