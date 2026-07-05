# Mirrors user.service.ts. handle, location, and counters are not editable.
module UsersService
  EDITABLE_KEYS = %w[nickname age gender bio avatarUrl].freeze

  module_function

  def get_by_id(id)
    user = User.find_by(id: id)
    raise ApiError::NotFound, "User '#{id}' was not found" if user.nil?

    UserSerializer.full(user)
  end

  # attrs: the raw permitted body hash (camelCase keys). Only keys actually
  # present are applied — absent keys are left untouched, explicit nulls clear.
  def update_profile(id, current_user_id, attrs)
    raise ApiError::Forbidden, "You can only edit your own profile" if id != current_user_id

    user = User.find_by(id: id)
    raise ApiError::NotFound, "User '#{id}' was not found" if user.nil?

    EDITABLE_KEYS.each do |key|
      next unless attrs.key?(key)

      value = attrs[key]
      value = value.strip if value.is_a?(String) # mirror zod .trim()
      user[key.underscore] = value
    end

    user.save!
    UserSerializer.full(user)
  end
end
