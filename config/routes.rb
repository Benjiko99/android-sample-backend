Rails.application.routes.draw do
  # Reveal health status on /up (Rails' own probe); the app's API probe is /api/health.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    get "health", to: "health#show"
    get "feed", to: "feed#index"

    resources :posts, only: :show do
      member do
        post :like, to: "posts#toggle_like"
        post :bookmark, to: "posts#toggle_bookmark"
      end

      resources :comments, only: [:index, :create] do
        post :like, on: :member, to: "comments#toggle_like"
      end
    end

    resources :users, only: [:show, :update] do
      member do
        get :profile, to: "profiles#show"
        get :posts, to: "posts#by_user"
        post :follow, to: "users#toggle_follow"
      end
    end
  end
end
