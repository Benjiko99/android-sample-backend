# Mirrors post.schema.ts.
#   full      -> toPostDTO       (GET /posts/:id) — embeds the full author
#   feed_item -> toPostFeedItemDTO (/feed, /users/:id/posts) — authorId reference
#
# is_liked / is_bookmarked are viewer-scoped booleans computed by the caller.
module PostSerializer
  module_function

  def full(post, is_liked:, is_bookmarked:, is_following_author:)
    base(post, is_liked:, is_bookmarked:).merge(
      "author" => UserSerializer.serialize(post.author, is_following: is_following_author)
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
      "url" => url(post),
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
