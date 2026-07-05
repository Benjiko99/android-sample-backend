class Album < ApplicationRecord
  include GeneratesStringId
  self.id_prefix = "a"

  belongs_to :user
  has_many :photos, -> { order(position: :asc) }, dependent: :destroy, inverse_of: :album
  has_many :posts, dependent: :nullify
end
