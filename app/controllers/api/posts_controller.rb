module Api
  class PostsController < BaseController
    def show
      render_data(PostsService.get_by_id(params[:id], current_user_id))
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
  end
end
