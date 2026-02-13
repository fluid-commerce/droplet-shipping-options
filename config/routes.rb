Rails.application.routes.draw do
  root "home#index"

  get "up" => "rails/health#show", as: :rails_health_check

  devise_for :users

  post "webhook", to: "webhooks#create", as: :webhook

  namespace :callbacks do
    resources :shipping_options, only: %i[ index show create update destroy ]
    post "cart_customer_logged_in", to: "cart_callbacks#logged_in"
    post "update_cart_email", to: "cart_callbacks#update_email"
    post "verify_email_success", to: "cart_callbacks#email_verified"
  end

  namespace :api do
    resources :rates, only: %i[ index ] do
      collection do
        put :bulk_update
      end
    end
  end

  namespace :admin do
    get "dashboard", to: "dashboard#index"
    resource :droplet, only: %i[ create update ]
    resources :settings, only: %i[ index edit update ]
    resources :users
    resources :callbacks, only: %i[ index show edit update ] do
      post :sync, on: :collection
    end
  end

  resources :shipping_options, only: %i[ index new create edit update destroy ] do
    member do
      patch :disable
    end
    collection do
      get :shipping_methods
      get :sort_order
      patch :update_sort_order
    end
  end

  resources :rates, except: [ :show ], as: :rate_tables do
    collection do
      get :import
      post :process_import
      get :editor
    end
  end

  resource :exigo_setting, only: [:edit, :update] do
    post :test_connection, on: :collection
  end
end
