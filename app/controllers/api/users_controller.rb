module Api
  class UsersController < BaseController
    def show
      render_data(
        UsersService.get_by_id(params[:id]),
        headers: { "Cache-Control" => "max-age=60, stale-while-revalidate=300" }
      )
    end

    def update
      render_data(UsersService.update_profile(params[:id], current_user_id, profile_params))
    end

    private

    # Only these fields are editable. Keys absent from the body are left
    # untouched; explicit nulls clear the (nullable) field.
    def profile_params
      params.permit(:nickname, :age, :gender, :bio, :avatarUrl).to_h
    end
  end
end
