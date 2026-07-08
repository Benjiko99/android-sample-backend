# Mirrors user.schema.ts (toUserFullDTO / toUserMinimalDTO).
module UserSerializer
  module_function

  def full(user, is_following:)
    {
      "id" => user.id,
      "nickname" => user.nickname,
      "handle" => user.handle,
      "age" => user.age,
      "gender" => user.gender,
      "location" => user.location,
      "bio" => user.bio,
      "avatarUrl" => avatar_url(user),
      "followerCount" => user.follower_count,
      "followingCount" => user.following_count,
      "isFollowing" => is_following
    }
  end

  def minimal(user, is_following:)
    {
      "id" => user.id,
      "handle" => user.handle,
      "nickname" => user.nickname,
      "avatarUrl" => avatar_url(user),
      "isFollowing" => is_following
    }
  end

  # Absolute, proxied URL to the stored avatar, or nil when the user has none.
  # Proxying streams the bytes straight through the app (vs. a redirect), which
  # image loaders like the Android client's Coil handle without a second hop. The
  # host comes from the environment's configured default_url_options.
  def avatar_url(user)
    return nil unless user.avatar.attached?

    Rails.application.routes.url_helpers.rails_storage_proxy_url(user.avatar)
  end
end
