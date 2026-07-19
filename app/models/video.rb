class Video < ApplicationRecord
  include GeneratesStringId
  self.id_prefix = "v"

  # A video is one of two things: seed data pointing at an external `url`, or a
  # client upload whose bytes live in Active Storage. #display_url hides which.
  has_one_attached :file

  belongs_to :user
  has_many :posts, dependent: :nullify

  # Allowed uploads. Enforced by PostsService before attaching (mirrors Photo),
  # which is why there's no model-level validation. The size ceiling is far lower
  # than a phone will happily record, so the client checks it before spending the
  # upload — see CreatePostMaxVideoBytes.
  CONTENT_TYPES = %w[video/mp4 video/quicktime video/webm video/3gpp video/x-matroska video/mpeg].freeze
  MAX_BYTES = 25.megabytes

  # What clients are served: the proxied URL of the uploaded file, or the seeded
  # external URL. Same proxy-not-redirect choice as Photo#display_url.
  def display_url
    return self[:url] unless file.attached?

    Rails.application.routes.url_helpers.rails_storage_proxy_url(file)
  end
end
