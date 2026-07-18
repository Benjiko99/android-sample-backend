module Api
  class PostsController < BaseController
    def show
      render_data(PostsService.get_by_id(params[:id], current_user_id))
    end

    def create
      render_created(PostsService.create(current_user_id, trimmed(:title), trimmed(:body)))
    end

    def toggle_like
      render_data(PostsService.toggle_like(params[:id], current_user_id))
    end

    def toggle_bookmark
      render_data(PostsService.toggle_bookmark(params[:id], current_user_id))
    end

    # GET /api/users/:id/posts
    def by_user
      page = PostsService.list_by_user(
        params[:id],
        current_user_id,
        cursor_token: params[:cursor],
        limit_param: params[:limit]
      )
      render_cursor(page)
    end

    private

    # Body: { "title": "...", "body": "..." }. Trimmed to match the source's zod .trim();
    # missing/blank values surface as a model validation error (422) from Post.
    def trimmed(key)
      value = params[key]
      value.is_a?(String) ? value.strip : value
    end
  end
end
