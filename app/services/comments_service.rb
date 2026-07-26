# Mirrors comment.service.ts + comment.repository.ts.
module CommentsService
  module_function

  # GET /posts/:id/comments — keyset-paginated, newest first.
  def list(post_id, viewer_id, cursor_token:, limit_param:)
    relation = Comment.includes(author: { avatar_attachment: :blob }).where(post_id: post_id)
    page = Cursor.paginate(relation, cursor_token:, limit_param:)

    ids = page.items.map(&:id)
    liked = ViewerFlags.liked_comment_ids(viewer_id, ids)
    author_ids = page.items.map(&:author_id).uniq
    following = ViewerFlags.following_user_ids(viewer_id, author_ids)

    items = page.items.map do |c|
      CommentSerializer.call(
        c,
        is_liked: liked.include?(c.id),
        is_following_author: following.include?(c.author_id)
      )
    end
    Cursor::Page.new(items, page.page)
  end

  # The number of comments on each of `post_ids`, defaulting to 0 for a post with none.
  #
  # A post's commentCount is *derived* rather than stored. It used to be a posts.comment_count
  # column bumped by hand on every create — a second copy of a number the comments table
  # already held, and the copy drifted: seeded posts claimed counts that no comment row
  # backed. Counting the rows cannot drift, and this exists only to do it for a whole page in
  # one grouped query — the batching ViewerFlags does for the viewer's flags, for the same
  # N+1 reason. A single post just asks its association (`post.comments.count`).
  def counts_by_post(post_ids)
    counts = Hash.new(0)
    return counts if post_ids.empty?

    counts.merge!(Comment.where(post_id: post_ids).group(:post_id).count)
  end

  # POST /posts/:id/comments — creates a comment on an existing post. Nothing else is
  # written: the post's count is read from the comments, so the new row *is* the update.
  def create(post_id, author_id, text)
    post = Post.find_by(id: post_id)
    raise ApiError::NotFound, "Post '#{post_id}' was not found" if post.nil?

    comment = Comment.create!(post_id: post_id, author_id: author_id, text: text)
    # A freshly created comment is never liked by, or following, its own author.
    CommentSerializer.call(comment, is_liked: false, is_following_author: false)
  end

  # PUT /posts/:id/comments/:comment_id/like — body: { "liked": true|false }, idempotent
  # for the same reason PostsService#set_like is.
  def set_like(comment_id, viewer_id, liked:)
    comment = Comment.find_by(id: comment_id)
    raise ApiError::NotFound, "Comment '#{comment_id}' was not found" if comment.nil?

    LikeState.set(comment, join_model: CommentLike, viewer_id: viewer_id, foreign_key: :comment_id, liked: liked)
  end
end
