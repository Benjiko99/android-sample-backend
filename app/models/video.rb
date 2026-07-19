class Video < ApplicationRecord
  include GeneratesStringId
  include ServesAttachedFile
  self.id_prefix = "v"

  # Seed rows carry an external `url`; client uploads carry these bytes.
  serves_attached :file

  belongs_to :user
  has_many :posts, dependent: :nullify

  # Allowed uploads. Enforced by PostsService via UploadValidation before
  # attaching, which is why there's no model-level validation. The size ceiling
  # is mirrored client-side as CreatePostMaxVideoBytes so an oversized clip is
  # refused before it is uploaded.
  CONTENT_TYPES = %w[video/mp4 video/quicktime video/webm video/3gpp video/x-matroska video/mpeg].freeze
  MAX_BYTES = 25.megabytes
end
