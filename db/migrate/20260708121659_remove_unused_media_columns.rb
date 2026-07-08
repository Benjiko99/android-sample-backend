# Both columns arrived with the TS→Rails port (MIGRATION_PLAN.md lists them as optional)
# and were never written or read: Reseed sets neither, no serializer emits them, and
# photos never reach the wire as objects at all — AlbumSerializer flattens an album's
# photos to a list of urls, so a caption had nowhere to go.
class RemoveUnusedMediaColumns < ActiveRecord::Migration[8.0]
  def change
    remove_column :videos, :thumbnail_url, :string
    remove_column :photos, :caption, :string
  end
end
