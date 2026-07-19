# Mirrors feed.service.ts. Returns [page, included] — the controller assembles
# the compound document via render_cursor so the envelope lives in one place.
module FeedService
  module_function

  # include: "author" attaches minimal user projections for the page's authors.
  def list(viewer_id, cursor_token:, limit_param:, include: nil)
    page = PostsService.paginate_feed_items(
      Post.includes(PostsService::MEDIA_INCLUDES),
      viewer_id,
      cursor_token:,
      limit_param:
    )
    [ page, author_included(page, viewer_id, include) ]
  end

  # Minimal user projections for the distinct authors on the page, or nil unless requested.
  def author_included(page, viewer_id, include)
    return nil unless include == "author"

    author_ids = page.items.map { |item| item["authorId"] }.uniq
    users = author_ids.empty? ? [] : User.where(id: author_ids).with_attached_avatar
    following = ViewerFlags.following_user_ids(viewer_id, author_ids)
    { "users" => users.map { |u| UserSerializer.minimal(u, is_following: following.include?(u.id)) } }
  end
end
