# Mirrors user.service.ts. handle, location, and counters are not editable.
module UsersService
  # Editable text fields. The avatar is an uploaded file, handled separately.
  EDITABLE_KEYS = %w[nickname age gender bio].freeze

  # Text fields that clear to null when an empty value is sent. nickname is
  # required, so a blank nickname stays blank and fails validation.
  NULLABLE_KEYS = %w[age gender bio].freeze

  module_function

  def get_by_id(id, viewer_id)
    user = User.find_by(id: id)
    raise ApiError::NotFound, "User '#{id}' was not found" if user.nil?

    is_following = ViewerFlags.following_user_ids(viewer_id, [ id ]).include?(id)
    UserSerializer.serialize(user, is_following: is_following)
  end

  # attrs: the raw permitted body hash. Only text keys actually present are
  # applied — absent keys are left untouched. An explicit null (JSON) or blank
  # value (multipart) clears a nullable field. A present :avatar file replaces
  # the stored avatar; its absence leaves the current one in place.
  def update_profile(id, current_user_id, attrs)
    raise ApiError::Forbidden, "You can only edit your own profile" if id != current_user_id

    user = User.find_by(id: id)
    raise ApiError::NotFound, "User '#{id}' was not found" if user.nil?

    EDITABLE_KEYS.each do |key|
      next unless attrs.key?(key)

      value = attrs[key]
      value = value.strip if value.is_a?(String) # mirror zod .trim()
      value = nil if value == "" && NULLABLE_KEYS.include?(key)
      user[key] = value
    end

    attach_avatar(user, attrs["avatar"]) if attrs["avatar"].present?

    user.save!
    # id == current_user_id was already enforced above, so a user can never be
    # following themselves here.
    UserSerializer.serialize(user, is_following: false)
  end

  # Toggles the current user following `target_id`, keeping the join row and
  # both users' counters consistent in one transaction (mirrors LikeToggle).
  def toggle_follow(target_id, viewer_id)
    raise ApiError::Forbidden, "You cannot follow yourself" if target_id == viewer_id

    target = User.find_by(id: target_id)
    raise ApiError::NotFound, "User '#{target_id}' was not found" if target.nil?

    follower = User.find_by(id: viewer_id)
    raise ApiError::NotFound, "User '#{viewer_id}' was not found" if follower.nil?

    existing = Follow.find_by(follower_id: viewer_id, followee_id: target_id)

    User.transaction do
      if existing
        existing.destroy!
        target.decrement!(:follower_count)
        follower.decrement!(:following_count)
      else
        Follow.create!(follower_id: viewer_id, followee_id: target_id)
        target.increment!(:follower_count)
        follower.increment!(:following_count)
      end
    end

    { "isFollowing" => existing.nil?, "followerCount" => target.follower_count }
  end

  # Validates the uploaded image before attaching. We check here rather than via a
  # model validation because attaching to an already-persisted, otherwise-unchanged
  # record saves the attachment immediately — a later save! validation would fire
  # too late to prevent it.
  def attach_avatar(user, file)
    UploadValidation.validate!(
      file,
      path: "avatar",
      content_types: User::AVATAR_CONTENT_TYPES,
      max_bytes: User::AVATAR_MAX_BYTES,
      kind: "Avatar",
      formats: "a JPEG, PNG, WebP, HEIC, or GIF image"
    )

    user.avatar.attach(file)
  end
end
