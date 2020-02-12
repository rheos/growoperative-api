Rails.application.routes.draw do
  devise_for :users,
             path: '',
             path_names: {
               sign_in: 'login',
               sign_out: 'logout',
               registration: 'signup'
             },
             controllers: {
               sessions: 'api/v1/sessions',
               registrations: 'api/v1/registrations'
             }
    scope module: 'api' do
    namespace :v1 , defaults: { format: :json } do
      # mount_devise_token_auth_for 'User', at: 'auth'
      # devise_for :users
      get 'get_chain_limit' => 'global_settings#get_chain_limit'
      post 'set_chain_limit' => 'global_settings#set_chain_limit'
      resources :users, only: [:index, :show] do 
        collection do
          get 'generate_invitation'
          get 'contact_list'
          post 'accept_invition'
          patch 'update_password'
          patch 'edit_contact_label'
          post 'get_contact_label'
        end
        member do 
          get 'get_invitation_limit'
          post 'set_invitation_limit'
          get 'get_nickname'
          put 'set_nickname'
          get 'item_list'
        end
      end
      resources :invitations, only: [:index, :update] do
        put "set_user_type"
        put 'set_note_label'
        collection do
          patch 'user_info'
        end
      end
      resources :categories, only: [:index]
      resources :grades, only: [:index]
      resources :item_names, only: [:index]
      resources :items, only: [:index, :create, :update, :destroy] do
        resources :item_requests, path: 'requests', only: [:index, :create]
        collection do
          get 'around'
          get 'reset'
          get 'my_items' => 'item_requests#my_items'
          get 'requested' => 'item_requests#requested'
          get 'reserved' => 'item_requests#reserved'
          get 'shipped' => 'item_requests#shipped'
          post 'requests/:id/accept' => 'item_requests#accept'
          post 'requests/:id/cancel' => 'item_requests#cancel'
          post 'requests/:id/ship' => 'item_requests#ship'
          post 'requests/:id/sign' => 'item_requests#sign'
          post 'requests/reserve' => 'item_requests#reserve'
        end
      end
      resources :user_category_prices, only: [:create]
      resources :user_relationship_prices,            only: [:index, :create]
      resources :user_relationship_request_prices,    only: [:create]
      resources :orders
      post 'verify_invitation_code' => 'home#verify_invitation_code'
      get 'available_user_type' => 'home#available_user_type'
      get 'current_user_types' => 'users#current_user_types'
      get 'private/*file_path' => 'resources#index'
    end
  end
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
end
