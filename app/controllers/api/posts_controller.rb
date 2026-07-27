module Api
  class PostsController < BaseController
    # GET /api/posts/:id — the post, with its author sideloaded beside it rather than
    # embedded in it. A single post answers in the shape a page of them does, so a client
    # has one post projection to read instead of two that differ only there.
    def show
      post, included = PostsService.get_by_id(params[:id], current_user_id)
      render_data(post, included: included)
    end

    # POST /api/posts — answers with the published post, sideloaded the way #show is.
    def create
      post, included = PostsService.create(
        current_user_id,
        trimmed(:title),
        trimmed(:body),
        images: uploaded_images,
        video: uploaded_video
      )
      render_created(post, included: included)
    end

    def destroy
      PostsService.delete(params[:id], current_user_id)
      head :no_content
    end

    def set_like
      render_data(PostsService.set_like(params[:id], current_user_id, liked: boolean_param!(:liked)))
    end

    def set_bookmark
      render_data(
        PostsService.set_bookmark(params[:id], current_user_id, bookmarked: boolean_param!(:bookmarked))
      )
    end

    # POST /api/posts/:id/report — body: { "reason": "spam", "details"?: "..." }. Nothing is
    # stored, so there is nothing to render either; a report is acknowledged the way a
    # deletion is, with an empty 204.
    def report
      PostsService.report(
        params[:id],
        current_user_id,
        reason: params[:reason],
        details: trimmed(:details)
      )
      head :no_content
    end

    # GET /api/users/:id/posts — the profile's Posts tab. Every post here is the profile's
    # own, so the one sideloaded author is always the same user; it rides along anyway, so
    # that all three profile lists answer in one shape and a client can render a page from
    # the page alone.
    def by_user
      page = PostsService.list_by_user(
        params[:id],
        current_user_id,
        cursor_token: params[:cursor],
        limit_param: params[:limit]
      )
      render_cursor(page, included: PostsService.author_included(page.items, current_user_id))
    end

    # GET /api/users/:id/likes — the profile's Likes tab. Public: anyone may read anyone's,
    # which is the whole difference from #bookmarked below.
    def liked
      page = PostsService.list_liked(
        params[:id],
        current_user_id,
        cursor_token: params[:cursor],
        limit_param: params[:limit]
      )
      render_cursor(page, included: PostsService.author_included(page.items, current_user_id))
    end

    # GET /api/users/:id/bookmarks — the profile's Saved tab. Bookmarks are private,
    # so this only ever answers for the caller's own id (403 otherwise).
    def bookmarked
      page = PostsService.list_bookmarked(
        params[:id],
        current_user_id,
        cursor_token: params[:cursor],
        limit_param: params[:limit]
      )
      render_cursor(page, included: PostsService.author_included(page.items, current_user_id))
    end

    private

    # Body: { "title": "...", "body": "..." }. Trimmed to match the source's zod .trim();
    # missing/blank values surface as a model validation error (422) from Post.
    def trimmed(key)
      value = params[key]
      value.is_a?(String) ? value.strip : value
    end

    # The `images[]` parts of a multipart create. A JSON request carries none; the
    # respond_to? guard drops anything that isn't an uploaded file, so a client
    # sending `images=["hi"]` gets an empty album rather than a 500.
    def uploaded_images
      Array(params[:images]).select { |value| value.respond_to?(:tempfile) }
    end

    # The single `video` part of a multipart create, guarded the same way.
    def uploaded_video
      video = params[:video]
      video if video.respond_to?(:tempfile)
    end
  end
end
