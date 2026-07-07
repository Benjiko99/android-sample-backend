# Mirrors comment.service.ts + comment.repository.ts.
module CommentsService
  module_function

  # GET /posts/:id/comments — keyset-paginated, newest first.
  def list(post_id, viewer_id, cursor_token:, limit_param:)
    relation = Comment.includes(author: { avatar_attachment: :blob }).where(post_id: post_id)
    page = Cursor.paginate(relation, cursor_token:, limit_param:)

    ids = page.items.map(&:id)
    liked = ViewerFlags.liked_comment_ids(viewer_id, ids)

    items = page.items.map { |c| CommentSerializer.call(c, is_liked: liked.include?(c.id)) }
    Cursor::Page.new(items, page.page)
  end

  # POST /posts/:id/comments — creates a comment and bumps the post's counter.
  def create(post_id, author_id, text)
    post = Post.find_by(id: post_id)
    raise ApiError::NotFound, "Post '#{post_id}' was not found" if post.nil?

    comment = ActiveRecord::Base.transaction do
      c = Comment.create!(post_id: post_id, author_id: author_id, text: text)
      post.increment!(:comment_count)
      c
    end
    # A freshly created comment is never liked by its author.
    CommentSerializer.call(comment, is_liked: false)
  end

  def toggle_like(comment_id, viewer_id)
    comment = Comment.find_by(id: comment_id)
    raise ApiError::NotFound, "Comment '#{comment_id}' was not found" if comment.nil?

    LikeToggle.call(comment, join_model: CommentLike, viewer_id: viewer_id, foreign_key: :comment_id)
  end
end
