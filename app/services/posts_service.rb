# Mirrors post.service.ts + post.repository.ts.
module PostsService
  module_function

  # GET /posts/:id — full post with embedded author.
  def get_by_id(id, viewer_id)
    post = Post.includes(:video, album: :photos, author: { avatar_attachment: :blob }).find_by(id: id)
    raise ApiError::NotFound, "Post '#{id}' was not found" if post.nil?

    liked = ViewerFlags.liked_post_ids(viewer_id, [post.id])
    bookmarked = ViewerFlags.bookmarked_post_ids(viewer_id, [post.id])
    following_author = ViewerFlags.following_user_ids(viewer_id, [post.author_id])

    PostSerializer.full(
      post,
      is_liked: liked.include?(post.id),
      is_bookmarked: bookmarked.include?(post.id),
      is_following_author: following_author.include?(post.author_id)
    )
  end

  # GET /users/:id/posts — profile tabs, keyset-paginated feed items.
  # type: "photo" (has album), "video" (has video), "text" (neither), or nil (all).
  def list_by_user(author_id, viewer_id, cursor_token:, limit_param:, type: nil)
    relation = Post.includes(:video, album: :photos).where(author_id: author_id)
    relation = apply_type_filter(relation, type)
    paginate_feed_items(relation, viewer_id, cursor_token:, limit_param:)
  end

  def toggle_like(post_id, viewer_id)
    post = Post.find_by(id: post_id)
    raise ApiError::NotFound, "Post '#{post_id}' was not found" if post.nil?

    LikeToggle.call(post, join_model: PostLike, viewer_id: viewer_id, foreign_key: :post_id)
  end

  def toggle_bookmark(post_id, viewer_id)
    post = Post.find_by(id: post_id)
    raise ApiError::NotFound, "Post '#{post_id}' was not found" if post.nil?

    existing = PostBookmark.find_by(user_id: viewer_id, post_id: post_id)
    if existing
      existing.destroy!
      { "isBookmarked" => false }
    else
      PostBookmark.create!(user_id: viewer_id, post_id: post_id)
      { "isBookmarked" => true }
    end
  end

  # Shared: paginate a post relation and serialize as feed items with viewer flags.
  def paginate_feed_items(relation, viewer_id, cursor_token:, limit_param:)
    page = Cursor.paginate(relation, cursor_token:, limit_param:)
    ids = page.items.map(&:id)
    liked = ViewerFlags.liked_post_ids(viewer_id, ids)
    bookmarked = ViewerFlags.bookmarked_post_ids(viewer_id, ids)

    items = page.items.map do |post|
      PostSerializer.feed_item(
        post,
        is_liked: liked.include?(post.id),
        is_bookmarked: bookmarked.include?(post.id)
      )
    end
    Cursor::Page.new(items, page.page)
  end

  def apply_type_filter(relation, type)
    case type
    when "photo" then relation.where.not(album_id: nil)
    when "video" then relation.where.not(video_id: nil)
    when "text"  then relation.where(album_id: nil, video_id: nil)
    else relation
    end
  end
end
