module Api
  class CommentsController < BaseController
    def index
      page = CommentsService.list(
        params[:post_id],
        current_user_id,
        cursor_token: params[:cursor],
        limit_param: params[:limit]
      )
      render_cursor(page)
    end

    def create
      render_created(CommentsService.create(params[:post_id], current_user_id, comment_text))
    end

    # POST /api/posts/:post_id/comments/:id/like
    def toggle_like
      render_data(CommentsService.toggle_like(params[:id], current_user_id))
    end

    private

    # Body: { "text": "..." }. Trimmed to match the source's zod .trim(). Missing/
    # blank text surfaces as a model validation error (422) from Comment.
    def comment_text
      value = params[:text]
      value.is_a?(String) ? value.strip : value
    end
  end
end
