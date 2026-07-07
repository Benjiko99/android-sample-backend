class User < ApplicationRecord
  # The profile photo is an uploaded file, served back as an absolute URL by
  # UserSerializer (see #avatar handling in UsersService).
  has_one_attached :avatar

  has_many :posts, foreign_key: :author_id, inverse_of: :author, dependent: :destroy
  has_many :albums, dependent: :destroy
  has_many :videos, dependent: :destroy
  has_many :comments, foreign_key: :author_id, inverse_of: :author, dependent: :destroy
  has_many :post_likes, dependent: :destroy
  has_many :post_bookmarks, dependent: :destroy
  has_many :comment_likes, dependent: :destroy

  # Allowed avatar uploads. Enforced by UsersService before attaching (see
  # UsersService#attach_avatar), which is why there's no model-level validation.
  AVATAR_CONTENT_TYPES = %w[image/jpeg image/png image/webp image/heic image/heif image/gif].freeze
  AVATAR_MAX_BYTES = 10.megabytes

  # Editable via PATCH /api/users/:id. handle, location, and counters are not editable.
  validates :nickname, length: { minimum: 1, maximum: 50 }, allow_nil: true
  validates :age, numericality: { only_integer: true, greater_than_or_equal_to: 13,
                                  less_than_or_equal_to: 120 }, allow_nil: true
  validates :gender, inclusion: { in: %w[Man Woman] }, allow_nil: true
  validates :bio, length: { minimum: 1, maximum: 500 }, allow_nil: true
end
