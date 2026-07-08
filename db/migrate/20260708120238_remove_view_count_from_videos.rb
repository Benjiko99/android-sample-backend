class RemoveViewCountFromVideos < ActiveRecord::Migration[8.0]
  def change
    remove_column :videos, :view_count, :integer, null: false, default: 0
  end
end
