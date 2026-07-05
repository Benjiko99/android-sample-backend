# Mirrors profile.service.ts. albumsCount / videosCount count only items NOT
# linked to any post (profile-tab content).
module ProfilesService
  module_function

  def get_stats(user_id)
    user = User.find_by(id: user_id)
    raise ApiError::NotFound, "User '#{user_id}' was not found" if user.nil?

    {
      "postsCount" => Post.where(author_id: user_id).count,
      "albumsCount" => Album.where(user_id: user_id).where.missing(:posts).count,
      "videosCount" => Video.where(user_id: user_id).where.missing(:posts).count
    }
  end
end
