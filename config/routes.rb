Rails.application.routes.draw do
  # User Authentication
  get "/login", to: "sessions#new"
  post "/login", to: "sessions#create"
  delete "/logout", to: "sessions#destroy"

  # Spotify OAuth routes
  # NOTE: /auth/spotify is handled by OmniAuth middleware, not a Rails route
  # Only the callback needs a Rails route
  get "/auth/spotify/callback", to: "auth#callback"
  get "/spotify_login", to: "auth#login", as: :spotify_login

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Main pages
  root "now_playing#index"

  # Now Playing
  get "now_playing", to: "now_playing#index", as: :now_playing

  # Browse
  get "browse", to: "browse#index", as: :browse

  # Artists
  resources :artists, only: [ :show ]

  # Albums
  resources :albums, only: [ :show ]

  # Requests
  resources :requests, only: [ :index, :new, :create ] do
    collection do
      get "confirmation"
    end
  end

  # Queue (view requests)
  get "queue", to: "requests#index", as: :queue

  # Setup routes (TODO: Add authentication later)
  resources :setup, only: [ :index ] do
    collection do
      get :spotify_auth
      get :test_connection
      post :refresh_tokens
      delete :clear_auth
    end
  end

  # Admin routes (Administrate + Custom)
  namespace :admin do
    # Administrate resources
    resources :users do
      member do
        patch :toggle_admin
        patch :unlock
      end
    end

    # Keep existing custom controllers for now
    resources :artists
    resources :albums
    resources :tracks
    resources :song_requests do
      member do
        patch :approve
        patch :reject
      end
      collection do
        delete :clear_queue
      end
    end

    # Use the custom dashboard
    root to: "dashboard#index"
  end
end
