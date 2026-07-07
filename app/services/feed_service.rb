# Mirrors feed.service.ts. Returns [page, included] — the controller assembles
# the compound document via render_cursor so the envelope lives in one place.
module FeedService
  module_function

  # include: "author" attaches minimal user projections for the page's authors.
  def list(viewer_id, cursor_token:, limit_param:, include: nil)
    page = PostsService.paginate_feed_items(
      Post.includes(:video, album: :photos),
      viewer_id,
      cursor_token:,
      limit_param:
    )
    [page, author_included(page, include)]
  end

  # Minimal user projections for the distinct authors on the page, or nil unless requested.
  def author_included(page, include)
    return nil unless include == "author"

    author_ids = page.items.map { |item| item["authorId"] }.uniq
    users = author_ids.empty? ? [] : User.where(id: author_ids).with_attached_avatar
    { "users" => users.map { |u| UserSerializer.minimal(u) } }
  end
end
