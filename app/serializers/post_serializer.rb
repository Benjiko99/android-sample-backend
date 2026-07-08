# Mirrors post.schema.ts.
#   full      -> toPostDTO       (GET /posts/:id) — embeds the full author
#   feed_item -> toPostFeedItemDTO (/feed, /users/:id/posts) — authorId reference
#
# is_liked / is_bookmarked are viewer-scoped booleans computed by the caller.
module PostSerializer
  module_function

  def full(post, is_liked:, is_bookmarked:, is_following_author:)
    base(post, is_liked:, is_bookmarked:).merge(
      "author" => UserSerializer.full(post.author, is_following: is_following_author)
    )
  end

  def feed_item(post, is_liked:, is_bookmarked:)
    base(post, is_liked:, is_bookmarked:).merge(
      "authorId" => post.author_id
    )
  end

  def base(post, is_liked:, is_bookmarked:)
    {
      "id" => post.id,
      "title" => post.title,
      "body" => post.body,
      "createdAt" => post.created_at.iso8601,
      "likeCount" => post.like_count,
      "commentCount" => post.comment_count,
      "isLiked" => is_liked,
      "isBookmarked" => is_bookmarked,
      "album" => AlbumSerializer.call(post.album),
      "video" => VideoSerializer.call(post.video)
    }
  end
end
