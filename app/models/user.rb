class User < ApplicationRecord
  has_many :posts, foreign_key: :author_id, inverse_of: :author, dependent: :destroy
  has_many :albums, dependent: :destroy
  has_many :videos, dependent: :destroy
  has_many :comments, foreign_key: :author_id, inverse_of: :author, dependent: :destroy
  has_many :post_likes, dependent: :destroy
  has_many :post_bookmarks, dependent: :destroy
  has_many :comment_likes, dependent: :destroy

  # Editable via PATCH /api/users/:id. handle, location, and counters are not editable.
  validates :nickname, length: { minimum: 1, maximum: 50 }, allow_nil: true
  validates :age, numericality: { only_integer: true, greater_than_or_equal_to: 13,
                                  less_than_or_equal_to: 120 }, allow_nil: true
  validates :gender, inclusion: { in: %w[Man Woman] }, allow_nil: true
  validates :bio, length: { minimum: 1, maximum: 500 }, allow_nil: true
  validate :avatar_url_must_be_url

  private

  def avatar_url_must_be_url
    return if avatar_url.nil?

    uri = URI.parse(avatar_url)
    errors.add(:avatar_url, "Must be a valid URL") unless uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    errors.add(:avatar_url, "Must be a valid URL")
  end
end
