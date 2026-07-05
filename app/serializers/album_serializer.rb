# Mirrors album.schema.ts (toAlbumDTO). `images` is the first 3 photo urls
# (photos association is ordered by position asc).
module AlbumSerializer
  module_function

  def call(album)
    return nil if album.nil?

    {
      "id" => album.id,
      "title" => album.title,
      "itemCount" => album.item_count,
      "images" => album.photos.first(3).map(&:url)
    }
  end
end
