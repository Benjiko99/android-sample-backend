class Photo < ApplicationRecord
  include GeneratesStringId
  self.id_prefix = "ph"

  belongs_to :album, inverse_of: :photos
end
