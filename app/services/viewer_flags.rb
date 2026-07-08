# Batch lookups for viewer-scoped social state (isLiked / isBookmarked).
# Mirrors Prisma's `likes: { where: { userId } }` per-viewer includes, but
# resolved once per page to avoid N+1 queries.
module ViewerFlags
  module_function

  def liked_post_ids(viewer_id, post_ids)
    flag_ids(PostLike, viewer_id, :post_id, post_ids)
  end

  def bookmarked_post_ids(viewer_id, post_ids)
    flag_ids(PostBookmark, viewer_id, :post_id, post_ids)
  end

  def liked_comment_ids(viewer_id, comment_ids)
    flag_ids(CommentLike, viewer_id, :comment_id, comment_ids)
  end

  # The subset of `user_ids` the viewer follows. Follow's columns aren't
  # shaped like the other join tables' (follower_id/followee_id, not
  # user_id), so it doesn't go through #flag_ids.
  def following_user_ids(viewer_id, user_ids)
    return Set.new if user_ids.empty?

    Follow.where(follower_id: viewer_id, followee_id: user_ids).pluck(:followee_id).to_set
  end

  # The subset of `ids` the viewer has flagged, as a Set for O(1) membership.
  def flag_ids(join_model, viewer_id, foreign_key, ids)
    return Set.new if ids.empty?

    join_model.where(user_id: viewer_id, foreign_key => ids).pluck(foreign_key).to_set
  end
end
