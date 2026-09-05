# Mirrors post.service.ts + post.repository.ts.
module PostsService
  # Everything a post's media needs to serialize without N+1 queries: the album's
  # photos and the video, each with its attachment and blob, since #display_url
  # touches the attachment on every one. Shared with FeedService so the feed and
  # the detail/profile paths can't drift apart.
  MEDIA_INCLUDES = {
    video: [ { file_attachment: :blob }, { thumbnail_attachment: :blob } ],
    album: { photos: { image_attachment: :blob } }
  }.freeze

  # The reasons a post may be reported for, mirroring the client's ReportReason enum.
  # Adding one means adding it there too — an unknown reason is refused, not stored.
  REPORT_REASONS = %w[spam harassment hate_speech misinformation violence other].freeze

  # The free-text field of a report is a sentence or two of context, not an essay.
  REPORT_DETAILS_MAX_LENGTH = 1000

  module_function

  # GET /posts/:id — the post, plus the one user it names as its author. Returns
  # [item, included] the way FeedService.list does, leaving the envelope to the controller.
  def get_by_id(id, viewer_id)
    post = Post.includes(MEDIA_INCLUDES).find_by(id: id)
    raise ApiError::NotFound, "Post '#{id}' was not found" if post.nil?

    liked = ViewerFlags.liked_post_ids(viewer_id, [ post.id ])
    bookmarked = ViewerFlags.bookmarked_post_ids(viewer_id, [ post.id ])

    item = PostSerializer.call(
      post,
      is_liked: liked.include?(post.id),
      is_bookmarked: bookmarked.include?(post.id),
      comment_count: post.comments.count
    )
    [ item, author_included([ item ], viewer_id) ]
  end

  # POST /posts — publishes a post authored by the viewer, answering [item, included] the
  # way #get_by_id does. Media is optional and exclusive: `images` become an Album, `video`
  # becomes a Video, and sending both is rejected.
  def create(author_id, title, body, images: [], video: nil)
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
      post.video = create_video(author, title, video) if video
      post.save!
    end

    # A freshly created post is never liked or bookmarked by the viewer — the viewer *is*
    # the author — and nobody has commented on a post that did not exist a moment ago.
    item = PostSerializer.call(
      post,
      is_liked: false,
      is_bookmarked: false,
      comment_count: 0
    )
    [ item, author_included([ item ], author_id) ]
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

  # GET /users/:id/posts — the profile's Posts tab, keyset-paginated.
  def list_by_user(author_id, viewer_id, cursor_token:, limit_param:)
    relation = Post.includes(MEDIA_INCLUDES).where(author_id: author_id)
    paginate_posts(relation, viewer_id, cursor_token:, limit_param:)
  end

  # GET /users/:id/likes — the profile's Likes tab. Public, unlike the Saved tab: what
  # someone endorsed is on show, so any caller may read anyone's. The viewer flags on the
  # items are still the *caller's* own, which is why viewer_id stays separate from user_id.
  def list_liked(user_id, viewer_id, cursor_token:, limit_param:)
    relation = Post.includes(MEDIA_INCLUDES).joins(:post_likes).where(post_likes: { user_id: user_id })
    paginate_posts(relation, viewer_id, cursor_token:, limit_param:)
  end

  # GET /users/:id/bookmarks — the profile's Saved tab. What a user saved is private,
  # so the only readable list is the caller's own; anyone else is refused before the
  # lookup, which also keeps an unknown id from distinguishing itself from a real one.
  #
  # The page is ordered by the *posts'* recency rather than when each was saved:
  # post_bookmarks carries no timestamp of its own, and reusing the shared (created_at, id)
  # keyset is worth more here than save-order would be.
  def list_bookmarked(user_id, viewer_id, cursor_token:, limit_param:)
    raise ApiError::Forbidden, "Bookmarks can only be read by the user who saved them" unless user_id == viewer_id

    relation = Post.includes(MEDIA_INCLUDES).joins(:post_bookmarks).where(post_bookmarks: { user_id: user_id })
    paginate_posts(relation, viewer_id, cursor_token:, limit_param:)
  end

  # PUT /posts/:id/like — body: { "liked": true|false }. The request names the state it
  # wants, so repeating it is harmless; see LikeState for why that matters.
  def set_like(post_id, viewer_id, liked:)
    post = Post.find_by(id: post_id)
    raise ApiError::NotFound, "Post '#{post_id}' was not found" if post.nil?

    LikeState.set(post, join_model: PostLike, viewer_id: viewer_id, foreign_key: :post_id, liked: liked)
  end

  # PUT /posts/:id/bookmark — body: { "bookmarked": true|false }. Idempotent for the same
  # reason #set_like is; there is no counter to keep in step, so it needs no transaction.
  def set_bookmark(post_id, viewer_id, bookmarked:)
    post = Post.find_by(id: post_id)
    raise ApiError::NotFound, "Post '#{post_id}' was not found" if post.nil?

    existing = PostBookmark.find_by(user_id: viewer_id, post_id: post_id)
    if bookmarked && existing.nil?
      PostBookmark.create!(user_id: viewer_id, post_id: post_id)
    elsif !bookmarked && existing
      existing.destroy!
    end

    { "isBookmarked" => bookmarked }
  end

  # POST /posts/:id/report — takes a report of someone's post and deliberately keeps none
  # of it. There is no moderation queue in this sample, so the endpoint exists to answer
  # the client honestly: the post has to exist and the reason has to be one we recognize,
  # and past those checks the report is logged and dropped. Anyone may report anything,
  # including their own post — a report is a message about a post, not a claim on it.
  def report(post_id, reporter_id, reason:, details: nil)
    post = Post.find_by(id: post_id)
    raise ApiError::NotFound, "Post '#{post_id}' was not found" if post.nil?

    validate_report!(reason, details)

    Rails.logger.info(
      "[report] post=#{post.id} reporter=#{reporter_id} reason=#{reason} " \
      "details=#{details.presence ? "#{details.to_s.length} chars" : "none"}"
    )
    nil
  end

  # A report's reason must be one of the offered ones — a client sending anything else has
  # drifted from this list, and a report we cannot name is worse than no report. The details
  # are optional; only their length is ours to police.
  def validate_report!(reason, details)
    unless REPORT_REASONS.include?(reason)
      expected = REPORT_REASONS.map { |r| "'#{r}'" }.join(" | ")
      raise ApiError::Validation.for(
        path: "reason", code: "invalid_enum_value",
        message: "Invalid option: expected #{expected}"
      )
    end

    return if details.to_s.length <= REPORT_DETAILS_MAX_LENGTH

    raise ApiError::Validation.for(
      path: "details", code: "too_long",
      message: "Details can be at most #{REPORT_DETAILS_MAX_LENGTH} characters"
    )
  end

  # Shared: paginate a post relation and serialize its rows with viewer flags.
  def paginate_posts(relation, viewer_id, cursor_token:, limit_param:)
    page = Cursor.paginate(relation, cursor_token:, limit_param:)
    ids = page.items.map(&:id)
    liked = ViewerFlags.liked_post_ids(viewer_id, ids)
    bookmarked = ViewerFlags.bookmarked_post_ids(viewer_id, ids)
    comment_counts = CommentsService.counts_by_post(ids)

    items = page.items.map do |post|
      PostSerializer.call(
        post,
        is_liked: liked.include?(post.id),
        is_bookmarked: bookmarked.include?(post.id),
        comment_count: comment_counts[post.id]
      )
    end
    Cursor::Page.new(items, page.page)
  end

  # Shared: user projections for the distinct authors of `items` — a whole page of them, or
  # the single item #get_by_id and #create answer with. Takes the serialized items rather
  # than the posts, so the one thing it reads is the "authorId" the client will resolve.
  # The feed offers these behind `include=author`; every other post endpoint always sends them.
  def author_included(items, viewer_id)
    author_ids = items.map { |item| item["authorId"] }.uniq
    users = author_ids.empty? ? [] : User.where(id: author_ids).with_attached_avatar
    following = ViewerFlags.following_user_ids(viewer_id, author_ids)

    { "users" => users.map { |u| UserSerializer.serialize(u, is_following: following.include?(u.id)) } }
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
  # Its duration and resolution are measured from the uploaded file rather than
  # reported by the client, so they describe the bytes we actually stored.
  # VideoMetadata is read before the attach, while the upload is still a tempfile
  # on disk; a poster frame is then extracted from the same tempfile.
  def create_video(author, title, file)
    metadata = VideoMetadata.extract(file)
    video = Video.create!(
      user: author,
      title: title,
      duration_seconds: metadata.duration_seconds,
      width: metadata.width,
      height: metadata.height
    )
    video.file.attach(file)
    attach_thumbnail(video, extract_thumbnail(file, metadata))

    video
  end

  # The poster frame for a clip, taken from its midpoint, or nil when none could be
  # produced (no ffmpeg, an unreadable stream). Only the midpoint is taken from the
  # metadata: the frame's size is ffmpeg's to settle, because the resolution read
  # here is the one *stored* in the container, which a rotated clip does not display
  # at. See VideoThumbnail::SCALE_FILTER.
  def extract_thumbnail(file, metadata)
    VideoThumbnail.generate(file, at_seconds: metadata.duration_seconds / 2.0)
  end

  # Attaches an already-extracted poster frame and records its dimensions. A
  # thumbnail is best-effort display metadata, so a video without one is left as it
  # is rather than failing the upload.
  def attach_thumbnail(video, thumbnail)
    return unless thumbnail

    # StringIO, not a file: this attach happens inside the transaction above, and
    # Active Storage only uploads the bytes once that commits — by which point any
    # file handle opened for the frame is long closed. See VideoThumbnail::Thumbnail.
    video.thumbnail.attach(
      io: StringIO.new(thumbnail.bytes),
      filename: "#{video.id}-thumbnail.jpg",
      content_type: "image/jpeg"
    )
    video.update!(thumbnail_width: thumbnail.width, thumbnail_height: thumbnail.height)
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
