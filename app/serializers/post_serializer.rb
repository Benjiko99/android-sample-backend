# Mirrors post.schema.ts.
#   full      -> toPostDTO       (GET /posts/:id) — embeds the full author
#   feed_item -> toPostFeedItemDTO (/feed, /users/:id/posts) — authorId reference
#
# is_liked / is_bookmarked are viewer-scoped booleans computed by the caller.
#
# comment_count is passed in for a different reason: it is not a column but a count of the
# post's comment rows, and a page of posts resolves it in one grouped query
# (CommentsService.counts_by_post) rather than one per post. Taking it as an argument is what
# keeps that batching possible — a serializer that reached for post.comments.count itself
# would be an N+1 nobody could see.
module PostSerializer
  module_function

  def full(post, is_liked:, is_bookmarked:, is_following_author:, comment_count:)
    base(post, is_liked:, is_bookmarked:, comment_count:).merge(
      "author" => UserSerializer.serialize(post.author, is_following: is_following_author)
    )
  end

  def feed_item(post, is_liked:, is_bookmarked:, comment_count:)
    base(post, is_liked:, is_bookmarked:, comment_count:).merge(
      "authorId" => post.author_id
    )
  end

  def base(post, is_liked:, is_bookmarked:, comment_count:)
    {
      "id" => post.id,
      "url" => url(post),
      "title" => post.title,
      "body" => post.body,
      "createdAt" => post.created_at.iso8601,
      "likeCount" => post.like_count,
      "commentCount" => comment_count,
      "isLiked" => is_liked,
      "isBookmarked" => is_bookmarked,
      "album" => AlbumSerializer.call(post.album),
      "video" => VideoSerializer.call(post.video)
    }
  end

  # The canonical shareable link for a post — what a client hands to a share sheet or
  # clipboard. The Android app used to build this itself by pasting an id onto a
  # hardcoded base; serving it means the deep-link shape is ours to change without
  # waiting on an app release.
  #
  # Built from the configured host rather than a route helper because nothing is
  # mounted at /p/:id yet — this is a link format, not a page the API serves.
  def url(post)
    ActionDispatch::Http::URL.url_for(
      Rails.application.routes.default_url_options.merge(path: "/p/#{post.id}")
    )
  end
end
