class CreateSocialSchema < ActiveRecord::Migration[8.0]
  def change
    create_table :users, id: :string do |t|
      t.string  :nickname, null: false
      t.string  :handle, null: false
      t.integer :age
      t.string  :gender
      t.string  :location
      t.string  :bio
      t.string  :avatar_url
      t.integer :follower_count, null: false, default: 0
      t.integer :following_count, null: false, default: 0
    end
    add_index :users, :handle, unique: true

    create_table :albums, id: :string do |t|
      t.string   :user_id, null: false
      t.string   :title, null: false
      t.integer  :item_count, null: false, default: 0
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end
    add_index :albums, :user_id

    create_table :photos, id: :string do |t|
      t.string  :album_id, null: false
      t.string  :url, null: false
      t.string  :caption
      t.integer :position, null: false, default: 0
    end
    add_index :photos, :album_id

    create_table :videos, id: :string do |t|
      t.string   :user_id, null: false
      t.string   :title, null: false
      t.string   :url, null: false
      t.string   :thumbnail_url
      t.integer  :duration_seconds
      t.integer  :view_count, null: false, default: 0
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end
    add_index :videos, :user_id

    create_table :posts, id: :string do |t|
      t.string   :author_id, null: false
      t.string   :title, null: false
      t.string   :body, null: false
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.integer  :like_count, null: false, default: 0
      t.integer  :comment_count, null: false, default: 0
      t.string   :album_id
      t.string   :video_id
    end
    add_index :posts, [:created_at, :id]
    add_index :posts, :author_id
    add_index :posts, :album_id
    add_index :posts, :video_id

    create_table :comments, id: :string do |t|
      t.string   :post_id, null: false
      t.string   :author_id, null: false
      t.string   :text, null: false
      t.integer  :like_count, null: false, default: 0
      t.datetime :created_at, null: false
    end
    add_index :comments, [:post_id, :created_at, :id]
    add_index :comments, :author_id

    create_table :post_likes, primary_key: [:user_id, :post_id] do |t|
      t.string :user_id, null: false
      t.string :post_id, null: false
    end

    create_table :post_bookmarks, primary_key: [:user_id, :post_id] do |t|
      t.string :user_id, null: false
      t.string :post_id, null: false
    end

    create_table :comment_likes, primary_key: [:user_id, :comment_id] do |t|
      t.string :user_id, null: false
      t.string :comment_id, null: false
    end

    add_foreign_key :albums, :users, column: :user_id
    add_foreign_key :photos, :albums, column: :album_id, on_delete: :cascade
    add_foreign_key :videos, :users, column: :user_id
    add_foreign_key :posts, :users, column: :author_id
    add_foreign_key :posts, :albums, column: :album_id
    add_foreign_key :posts, :videos, column: :video_id
    add_foreign_key :comments, :posts, column: :post_id, on_delete: :cascade
    add_foreign_key :comments, :users, column: :author_id
    add_foreign_key :post_likes, :users, column: :user_id
    add_foreign_key :post_likes, :posts, column: :post_id, on_delete: :cascade
    add_foreign_key :post_bookmarks, :users, column: :user_id
    add_foreign_key :post_bookmarks, :posts, column: :post_id, on_delete: :cascade
    add_foreign_key :comment_likes, :users, column: :user_id
    add_foreign_key :comment_likes, :comments, column: :comment_id, on_delete: :cascade
  end
end
