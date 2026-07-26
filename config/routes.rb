Rails.application.routes.draw do
  # Reveal health status on /up (Rails' own probe); the app's API probe is /api/health.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    get "health", to: "health#show"
    get "feed", to: "feed#index"

    resources :posts, only: [:show, :create, :destroy] do
      member do
        # PUT, not POST: these set a state rather than flipping one, so a retry is a no-op.
        put :like, to: "posts#set_like"
        put :bookmark, to: "posts#set_bookmark"
        post :report, to: "posts#report"
      end

      resources :comments, only: [:index, :create] do
        put :like, on: :member, to: "comments#set_like"
      end
    end

    resources :users, only: [:show, :update] do
      member do
        get :profile, to: "profiles#show"
        get :posts, to: "posts#by_user"
        get :bookmarks, to: "posts#bookmarked"
        get :likes, to: "posts#liked"
        post :follow, to: "users#toggle_follow"
      end
    end
  end
end
