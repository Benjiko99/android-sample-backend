class PostLike < ApplicationRecord
  self.primary_key = [:user_id, :post_id]

  belongs_to :user
  belongs_to :post
end
