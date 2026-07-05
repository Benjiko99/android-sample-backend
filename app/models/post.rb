class Post < ApplicationRecord
  include GeneratesStringId
  self.id_prefix = "p"

  belongs_to :author, class_name: "User", foreign_key: :author_id, inverse_of: :posts
  belongs_to :album, optional: true
  belongs_to :video, optional: true
  has_many :comments, dependent: :destroy
  has_many :post_likes, dependent: :destroy
  has_many :post_bookmarks, dependent: :destroy
end
