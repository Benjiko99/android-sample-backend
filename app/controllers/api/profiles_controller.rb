module Api
  class ProfilesController < BaseController
    def show
      render_data(ProfilesService.get_stats(params[:id]))
    end
  end
end
