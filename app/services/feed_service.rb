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
    [ page, include == "author" ? PostsService.author_included(page, viewer_id) : nil ]
  end
end
