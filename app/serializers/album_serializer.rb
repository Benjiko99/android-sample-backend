# Mirrors album.schema.ts (toAlbumDTO). `images` is every photo url, in position
# order — clients page through the whole album, and `itemCount` is the count they
# label it with, so serving a subset would leave the two disagreeing.
module AlbumSerializer
  module_function

  def call(album)
    return nil if album.nil?

    {
      "id" => album.id,
      "title" => album.title,
      "itemCount" => album.item_count,
      "images" => album.photos.map(&:display_url)
    }
  end
end
