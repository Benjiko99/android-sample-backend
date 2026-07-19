class Post < ApplicationRecord
  include GeneratesStringId
  self.id_prefix = "p"

  belongs_to :author, class_name: "User", foreign_key: :author_id, inverse_of: :posts
  belongs_to :album, optional: true
  belongs_to :video, optional: true
  has_many :comments, dependent: :destroy
  has_many :post_likes, dependent: :destroy
  has_many :post_bookmarks, dependent: :destroy

  validates :title, length: { minimum: 1, maximum: 120 }
  validates :body, length: { minimum: 1, maximum: 5000 }
  validate :at_most_one_media_kind

  private

  # A post's media is an album *or* a video, never both — the clients render one
  # media block and have no layout for two. PostsService rejects the combination
  # up front; this is the invariant's backstop at the record level.
  def at_most_one_media_kind
    return if album_id.blank? || video_id.blank?

    errors.add(:video, "cannot be set on a post that already has photos")
  end
end
