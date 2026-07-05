# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_07_05_190000) do
  create_table "albums", id: :string, force: :cascade do |t|
    t.string "user_id", null: false
    t.string "title", null: false
    t.integer "item_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_albums_on_user_id"
  end

  create_table "comment_likes", primary_key: ["user_id", "comment_id"], force: :cascade do |t|
    t.string "user_id", null: false
    t.string "comment_id", null: false
  end

  create_table "comments", id: :string, force: :cascade do |t|
    t.string "post_id", null: false
    t.string "author_id", null: false
    t.string "text", null: false
    t.integer "like_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["author_id"], name: "index_comments_on_author_id"
    t.index ["post_id", "created_at", "id"], name: "index_comments_on_post_id_and_created_at_and_id"
  end

  create_table "photos", id: :string, force: :cascade do |t|
    t.string "album_id", null: false
    t.string "url", null: false
    t.string "caption"
    t.integer "position", default: 0, null: false
    t.index ["album_id"], name: "index_photos_on_album_id"
  end

  create_table "post_bookmarks", primary_key: ["user_id", "post_id"], force: :cascade do |t|
    t.string "user_id", null: false
    t.string "post_id", null: false
  end

  create_table "post_likes", primary_key: ["user_id", "post_id"], force: :cascade do |t|
    t.string "user_id", null: false
    t.string "post_id", null: false
  end

  create_table "posts", id: :string, force: :cascade do |t|
    t.string "author_id", null: false
    t.string "title", null: false
    t.string "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "like_count", default: 0, null: false
    t.integer "comment_count", default: 0, null: false
    t.string "album_id"
    t.string "video_id"
    t.index ["album_id"], name: "index_posts_on_album_id"
    t.index ["author_id"], name: "index_posts_on_author_id"
    t.index ["created_at", "id"], name: "index_posts_on_created_at_and_id"
    t.index ["video_id"], name: "index_posts_on_video_id"
  end

  create_table "users", id: :string, force: :cascade do |t|
    t.string "nickname", null: false
    t.string "handle", null: false
    t.integer "age"
    t.string "gender"
    t.string "location"
    t.string "bio"
    t.string "avatar_url"
    t.integer "follower_count", default: 0, null: false
    t.integer "following_count", default: 0, null: false
    t.index ["handle"], name: "index_users_on_handle", unique: true
  end

  create_table "videos", id: :string, force: :cascade do |t|
    t.string "user_id", null: false
    t.string "title", null: false
    t.string "url", null: false
    t.string "thumbnail_url"
    t.integer "duration_seconds"
    t.integer "view_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_videos_on_user_id"
  end

  add_foreign_key "albums", "users"
  add_foreign_key "comment_likes", "comments", on_delete: :cascade
  add_foreign_key "comment_likes", "users"
  add_foreign_key "comments", "posts", on_delete: :cascade
  add_foreign_key "comments", "users", column: "author_id"
  add_foreign_key "photos", "albums", on_delete: :cascade
  add_foreign_key "post_bookmarks", "posts", on_delete: :cascade
  add_foreign_key "post_bookmarks", "users"
  add_foreign_key "post_likes", "posts", on_delete: :cascade
  add_foreign_key "post_likes", "users"
  add_foreign_key "posts", "albums"
  add_foreign_key "posts", "users", column: "author_id"
  add_foreign_key "posts", "videos"
  add_foreign_key "videos", "users"
end
