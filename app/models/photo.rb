class Photo < ApplicationRecord
  include GeneratesStringId
  include ServesAttachedFile
  self.id_prefix = "ph"

  # Seed rows carry an external `url`; client uploads carry these bytes.
  serves_attached :image

  belongs_to :album, inverse_of: :photos

  # Allowed uploads. Enforced by PostsService via UploadValidation before
  # attaching, which is why there's no model-level validation.
  CONTENT_TYPES = %w[image/jpeg image/png image/webp image/heic image/heif image/gif].freeze
  MAX_BYTES = 10.megabytes
end
