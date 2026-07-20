# Mirrors comment.schema.ts (toCommentDTO). is_liked is viewer-scoped.
module CommentSerializer
  module_function

  def call(comment, is_liked:, is_following_author:)
    {
      "id" => comment.id,
      "text" => comment.text,
      "createdAt" => comment.created_at.iso8601,
      "likeCount" => comment.like_count,
      "isLiked" => is_liked,
      "author" => UserSerializer.serialize(comment.author, is_following: is_following_author)
    }
  end
end
