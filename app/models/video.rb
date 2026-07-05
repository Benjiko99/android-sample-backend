class Video < ApplicationRecord
  include GeneratesStringId
  self.id_prefix = "v"

  belongs_to :user
  has_many :posts, dependent: :nullify
end
