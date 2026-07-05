# Toggles a per-viewer like on a record that owns a `like_count`, keeping the
# join row and the counter consistent in one transaction. Shared by posts and
# comments (mirrors the toggleLike repositories in the source).
module LikeToggle
  module_function

  # record: the liked owner (has like_count); join_model: PostLike / CommentLike;
  # foreign_key: the join column pointing at the owner (:post_id / :comment_id).
  def call(record, join_model:, viewer_id:, foreign_key:)
    existing = join_model.find_by(user_id: viewer_id, foreign_key => record.id)

    record.class.transaction do
      if existing
        existing.destroy!
        record.decrement!(:like_count)
      else
        join_model.create!(:user_id => viewer_id, foreign_key => record.id)
        record.increment!(:like_count)
      end
      { "isLiked" => existing.nil?, "likeCount" => record.like_count }
    end
  end
end
