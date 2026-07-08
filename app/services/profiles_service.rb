# Mirrors profile.service.ts.
module ProfilesService
  module_function

  def get_stats(user_id)
    user = User.find_by(id: user_id)
    raise ApiError::NotFound, "User '#{user_id}' was not found" if user.nil?

    { "postsCount" => Post.where(author_id: user_id).count }
  end
end
