class Album < ApplicationRecord
  include GeneratesStringId
  self.id_prefix = "a"

  # Ceiling on a client-authored album, enforced by PostsService. Mirrors the
  # composer's own limit so the client can refuse before spending the upload.
  MAX_PHOTOS = 10

  belongs_to :user
  has_many :photos, -> { order(position: :asc) }, dependent: :destroy, inverse_of: :album
  has_many :posts, dependent: :nullify
end
