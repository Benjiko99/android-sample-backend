class CreateFollows < ActiveRecord::Migration[8.0]
  def change
    create_table :follows, primary_key: [:follower_id, :followee_id] do |t|
      t.string :follower_id, null: false
      t.string :followee_id, null: false
    end
    add_index :follows, :followee_id

    add_foreign_key :follows, :users, column: :follower_id, on_delete: :cascade
    add_foreign_key :follows, :users, column: :followee_id, on_delete: :cascade
  end
end
