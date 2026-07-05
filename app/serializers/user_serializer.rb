# Mirrors user.schema.ts (toUserFullDTO / toUserMinimalDTO).
module UserSerializer
  module_function

  def full(user)
    {
      "id" => user.id,
      "nickname" => user.nickname,
      "handle" => user.handle,
      "age" => user.age,
      "gender" => user.gender,
      "location" => user.location,
      "bio" => user.bio,
      "avatarUrl" => user.avatar_url,
      "followerCount" => user.follower_count,
      "followingCount" => user.following_count
    }
  end

  def minimal(user)
    {
      "id" => user.id,
      "handle" => user.handle,
      "nickname" => user.nickname,
      "avatarUrl" => user.avatar_url
    }
  end
end
