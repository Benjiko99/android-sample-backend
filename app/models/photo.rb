class Photo < ApplicationRecord
  include GeneratesStringId
  self.id_prefix = "ph"

  # A photo is one of two things: seed data pointing at an external `url`, or a
  # client upload whose bytes live in Active Storage. #display_url hides which.
  has_one_attached :image

  belongs_to :album, inverse_of: :photos

  # Allowed uploads. Enforced by PostsService before attaching (mirrors the avatar
  # rules on User), which is why there's no model-level validation.
  CONTENT_TYPES = %w[image/jpeg image/png image/webp image/heic image/heif image/gif].freeze
  MAX_BYTES = 10.megabytes

  # What clients are served: the proxied URL of the uploaded file, or the seeded
  # external URL. Proxying (rather than redirecting) streams the bytes through the
  # app in one hop, which is what the Android client's Coil expects — same choice
  # as UserSerializer#avatar_url.
  def display_url
    return self[:url] unless image.attached?

    Rails.application.routes.url_helpers.rails_storage_proxy_url(image)
  end
end
