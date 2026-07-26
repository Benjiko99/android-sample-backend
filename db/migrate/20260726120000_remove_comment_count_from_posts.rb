class RemoveCommentCountFromPosts < ActiveRecord::Migration[8.0]
  def change
    remove_column :posts, :comment_count, :integer, null: false, default: 0
  end
end
