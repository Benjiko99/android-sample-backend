# Mirrors post.service.ts + post.repository.ts.
module PostsService
  module_function

  # GET /posts/:id — full post with embedded author.
  def get_by_id(id, viewer_id)
    post = Post.includes(
      :video,
      album: { photos: { image_attachment: :blob } },
      author: { avatar_attachment: :blob }
    ).find_by(id: id)
    raise ApiError::NotFound, "Post '#{id}' was not found" if post.nil?

    liked = ViewerFlags.liked_post_ids(viewer_id, [ post.id ])
    bookmarked = ViewerFlags.bookmarked_post_ids(viewer_id, [ post.id ])
    following_author = ViewerFlags.following_user_ids(viewer_id, [ post.author_id ])

    PostSerializer.full(
      post,
      is_liked: liked.include?(post.id),
      is_bookmarked: bookmarked.include?(post.id),
      is_following_author: following_author.include?(post.author_id)
    )
  end

  # POST /posts — publishes a post authored by the viewer. `images` are optional
  # multipart uploads; when present they become an Album attached to the post.
  # Video is still not authorable from the client.
  def create(author_id, title, body, images: [])
    author = User.find_by(id: author_id)
    raise ApiError::NotFound, "User '#{author_id}' was not found" if author.nil?

    # Both the text and every image are checked before anything is written.
    # Attaching persists a blob immediately, so validating late would leave
    # uploaded bytes orphaned behind a post that then failed to save.
    post = Post.new(author_id: author_id, title: title, body: body)
    post.validate!
    validate_images!(images)

    Post.transaction do
      post.album = create_album(author, title, images) if images.any?
      post.save!
    end

    # A freshly created post is never liked or bookmarked by, nor is its author followed
    # by, the viewer — the viewer *is* the author.
    PostSerializer.full(post, is_liked: false, is_bookmarked: false, is_following_author: false)
  end

  # GET /users/:id/posts — the profile's Posts tab, keyset-paginated feed items.
  def list_by_user(author_id, viewer_id, cursor_token:, limit_param:)
    relation = Post.includes(:video, album: { photos: { image_attachment: :blob } })
                   .where(author_id: author_id)
    paginate_feed_items(relation, viewer_id, cursor_token:, limit_param:)
  end

  def toggle_like(post_id, viewer_id)
    post = Post.find_by(id: post_id)
    raise ApiError::NotFound, "Post '#{post_id}' was not found" if post.nil?

    LikeToggle.call(post, join_model: PostLike, viewer_id: viewer_id, foreign_key: :post_id)
  end

  def toggle_bookmark(post_id, viewer_id)
    post = Post.find_by(id: post_id)
    raise ApiError::NotFound, "Post '#{post_id}' was not found" if post.nil?

    existing = PostBookmark.find_by(user_id: viewer_id, post_id: post_id)
    if existing
      existing.destroy!
      { "isBookmarked" => false }
    else
      PostBookmark.create!(user_id: viewer_id, post_id: post_id)
      { "isBookmarked" => true }
    end
  end

  # Shared: paginate a post relation and serialize as feed items with viewer flags.
  def paginate_feed_items(relation, viewer_id, cursor_token:, limit_param:)
    page = Cursor.paginate(relation, cursor_token:, limit_param:)
    ids = page.items.map(&:id)
    liked = ViewerFlags.liked_post_ids(viewer_id, ids)
    bookmarked = ViewerFlags.bookmarked_post_ids(viewer_id, ids)

    items = page.items.map do |post|
      PostSerializer.feed_item(
        post,
        is_liked: liked.include?(post.id),
        is_bookmarked: bookmarked.include?(post.id)
      )
    end
    Cursor::Page.new(items, page.page)
  end

  # An authored album is titled after its post — it exists to carry the post's
  # photos, not as a collection the user curates separately.
  def create_album(author, title, images)
    album = Album.create!(user: author, title: title, item_count: images.length)

    images.each_with_index do |file, position|
      album.photos.create!(position: position).image.attach(file)
    end

    album
  end

  def validate_images!(images)
    return if images.empty?

    if images.length > Album::MAX_PHOTOS
      raise_image_error("images", "too_many", "A post can have at most #{Album::MAX_PHOTOS} images")
    end

    images.each_with_index { |file, index| validate_image!(file, index) }
  end

  # Content type is sniffed from the bytes (Marcel), not trusted from the
  # client-declared type — same rule as UsersService#attach_avatar.
  def validate_image!(file, index)
    path = "images.#{index}"

    content_type = Marcel::MimeType.for(
      file.tempfile, name: file.original_filename, declared_type: file.content_type
    )

    unless Photo::CONTENT_TYPES.include?(content_type)
      raise_image_error(path, "invalid_content_type", "Image must be a JPEG, PNG, WebP, HEIC, or GIF")
    end

    return unless file.size > Photo::MAX_BYTES

    max_mb = Photo::MAX_BYTES / 1.megabyte
    raise_image_error(path, "too_large", "Image must be at most #{max_mb} MB")
  end

  def raise_image_error(path, code, message)
    raise ApiError::Validation.new("Validation failed", details: [
      { "path" => path, "code" => code, "message" => message }
    ])
  end
end
