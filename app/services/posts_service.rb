# Mirrors post.service.ts + post.repository.ts.
module PostsService
  # Everything a post's media needs to serialize without N+1 queries: the album's
  # photos and the video, each with its attachment and blob, since #display_url
  # touches the attachment on every one. Shared with FeedService so the feed and
  # the detail/profile paths can't drift apart.
  MEDIA_INCLUDES = {
    video: { file_attachment: :blob },
    album: { photos: { image_attachment: :blob } }
  }.freeze

  module_function

  # GET /posts/:id — full post with embedded author.
  def get_by_id(id, viewer_id)
    post = Post.includes(MEDIA_INCLUDES.merge(author: { avatar_attachment: :blob })).find_by(id: id)
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

  # POST /posts — publishes a post authored by the viewer. Media is optional and
  # exclusive: `images` become an Album, `video` becomes a Video, and sending both
  # is rejected. `video_duration_seconds` comes from the client because extracting
  # it server-side would mean shipping ffmpeg in the image for one metadata field.
  def create(author_id, title, body, images: [], video: nil, video_duration_seconds: nil)
    author = User.find_by(id: author_id)
    raise ApiError::NotFound, "User '#{author_id}' was not found" if author.nil?

    # The text and every uploaded file are checked before anything is written.
    # Attaching persists a blob immediately, so validating late would leave
    # uploaded bytes orphaned behind a post that then failed to save.
    post = Post.new(author_id: author_id, title: title, body: body)
    post.validate!
    validate_media!(images, video)

    Post.transaction do
      post.album = create_album(author, title, images) if images.any?
      post.video = create_video(author, title, video, video_duration_seconds) if video
      post.save!
    end

    # A freshly created post is never liked or bookmarked by, nor is its author followed
    # by, the viewer — the viewer *is* the author.
    PostSerializer.full(post, is_liked: false, is_bookmarked: false, is_following_author: false)
  end

  # DELETE /posts/:id — removes the viewer's own post. Only the author may delete;
  # anyone else gets a 403 rather than a 404, since the post plainly exists.
  def delete(post_id, viewer_id)
    post = Post.find_by(id: post_id)
    raise ApiError::NotFound, "Post '#{post_id}' was not found" if post.nil?
    raise ApiError::Forbidden, "A post can only be deleted by its author" unless post.author_id == viewer_id

    # Comments, likes and bookmarks travel with the post through its dependent: :destroy
    # associations. Its media does not: an Album/Video is a user-owned record a post
    # merely points at (hence dependent: :nullify on their side), so it is destroyed
    # only once no post still holds it — which for composer-authored media, created for
    # this one post by #create, is immediately.
    album = post.album
    video = post.video

    Post.transaction do
      post.destroy!
      album.destroy! if album && album.posts.empty?
      video.destroy! if video && video.posts.empty?
    end
  end

  # GET /users/:id/posts — the profile's Posts tab, keyset-paginated feed items.
  def list_by_user(author_id, viewer_id, cursor_token:, limit_param:)
    relation = Post.includes(MEDIA_INCLUDES).where(author_id: author_id)
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

  # An authored video is titled after its post, for the same reason an album is.
  # Duration is clamped to a non-negative integer: it is display metadata the
  # client reports about its own file, so it is sanitized rather than trusted.
  def create_video(author, title, file, duration_seconds)
    video = Video.create!(
      user: author,
      title: title,
      duration_seconds: [ duration_seconds.to_i, 0 ].max
    )
    video.file.attach(file)

    video
  end

  # Media is exclusive, and every uploaded file is checked before anything is
  # written. Each file goes through the shared UploadValidation rule; only the
  # limits, the error path, and the prose differ per kind.
  def validate_media!(images, video)
    if images.any? && video
      raise ApiError::Validation.for(
        path: "video", code: "media_conflict",
        message: "A post can have photos or a video, not both"
      )
    end

    if images.length > Album::MAX_PHOTOS
      raise ApiError::Validation.for(
        path: "images", code: "too_many",
        message: "A post can have at most #{Album::MAX_PHOTOS} images"
      )
    end

    images.each_with_index do |file, index|
      UploadValidation.validate!(
        file,
        path: "images.#{index}",
        content_types: Photo::CONTENT_TYPES,
        max_bytes: Photo::MAX_BYTES,
        kind: "Image",
        formats: "a JPEG, PNG, WebP, HEIC, or GIF"
      )
    end

    return unless video

    UploadValidation.validate!(
      video,
      path: "video",
      content_types: Video::CONTENT_TYPES,
      max_bytes: Video::MAX_BYTES,
      kind: "Video",
      formats: "an MP4, MOV, WebM, 3GP, MKV, or MPEG file"
    )
  end
end
