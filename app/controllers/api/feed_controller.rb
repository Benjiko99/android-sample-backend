module Api
  class FeedController < BaseController
    def index
      include = validate_enum!(params[:include], param: "include", allowed: %w[author])
      page, included = FeedService.list(
        current_user_id,
        cursor_token: params[:cursor],
        limit_param: params[:limit],
        include: include
      )
      render_cursor(page, included: included)
    end
  end
end
