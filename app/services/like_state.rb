# Puts a per-viewer like on a record that owns a `like_count` into a requested state,
# keeping the join row and the counter consistent in one transaction. Shared by posts
# and comments.
#
# Setting rather than toggling is what makes the endpoints idempotent: a client that
# retries after a timeout, or fires a second tap before the first answers, repeats a
# state instead of repeating a flip. Asking for the state a record is already in is a
# no-op that answers the same body as the request that put it there.
module LikeState
  module_function

  # record: the liked owner (has like_count); join_model: PostLike / CommentLike;
  # foreign_key: the join column pointing at the owner (:post_id / :comment_id).
  def set(record, join_model:, viewer_id:, foreign_key:, liked:)
    record.class.transaction do
      existing = join_model.find_by(user_id: viewer_id, foreign_key => record.id)

      if liked && existing.nil?
        join_model.create!(:user_id => viewer_id, foreign_key => record.id)
        record.increment!(:like_count)
      elsif !liked && existing
        existing.destroy!
        record.decrement!(:like_count)
      end

      { "isLiked" => liked, "likeCount" => record.like_count }
    end
  end
end
