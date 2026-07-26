# Dropping a column from a table other tables cascade off is not a schema-only change on
# SQLite. There is no in-place DROP COLUMN here: Rails rebuilds `posts` by copying it to a new
# table and dropping the old one, and SQLite's DROP TABLE performs an implicit DELETE FROM
# that fires every ON DELETE CASCADE pointing at it — comments, post_likes and post_bookmarks
# all follow the old table out. It happened: the first run of this migration emptied those
# three tables in production, and they were restored by reseeding.
#
# PRAGMA foreign_keys is a silent no-op inside a transaction, so the pragma alone does not
# help — disable_ddl_transaction! has to come with it. Any future migration altering a table
# with children cascading off it needs the same pair, which is also why this is up/down
# rather than change: a raw execute cannot be reversed automatically.
class RemoveCommentCountFromPosts < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    without_foreign_keys { remove_column :posts, :comment_count }
  end

  def down
    without_foreign_keys { add_column :posts, :comment_count, :integer, null: false, default: 0 }
  end

  private

  def without_foreign_keys
    connection.execute("PRAGMA foreign_keys = OFF")
    yield
  ensure
    connection.execute("PRAGMA foreign_keys = ON")
  end
end
