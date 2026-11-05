# frozen_string_literal: true

namespace :settings do
  namespace :preferences do
    resources :emoji_favorites, path: 'emoji_packs/favorites', except: [:show, :destroy] do
      collection do
        get :choose
        post :apply
        post :batch
        post :refresh_icons
      end
    end
    resources :emoji_packs, only: :index do
      get :search, on: :collection
    end
    patch :emoji_packs, to: 'emoji_packs#update', as: :update_emoji_packs
  end
end

namespace :admin do
  resources :emoji_sections, path: 'emoji_packs/sections', except: [:show] do
    post :batch, on: :collection
  end
  resources :emoji_packs, only: [:index, :edit, :update] do
    collection do
      post :batch
      patch :group, action: :update_group, as: :update_group
      post :publish
      post :refresh
    end
  end
end
