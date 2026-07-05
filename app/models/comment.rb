class Comment < ApplicationRecord
  include GeneratesStringId

  belongs_to :post
  belongs_to :author, class_name: "User", foreign_key: :author_id, inverse_of: :comments
  has_many :comment_likes, dependent: :destroy

  validates :text, length: { minimum: 1, maximum: 5000 }
end
