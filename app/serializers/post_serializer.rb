# Mirrors post.schema.ts. There is one post projection, deliberately: a post names its author
# with "authorId" and never embeds the user. The endpoints answering with a *single* post
# sideload that author under "included" the way a page of posts does, so a client reads one
# shape everywhere rather than telling two apart — the same argument UserSerializer makes for
# there being one user projection.
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

  def call(post, is_liked:, is_bookmarked:, comment_count:)
    {
      "id" => post.id,
      "url" => url(post),
      "title" => post.title,
      "body" => post.body,
      "createdAt" => post.created_at.iso8601,
      "authorId" => post.author_id,
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
