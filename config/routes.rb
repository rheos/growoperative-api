Rails.application.routes.draw do
  get "/up", to: proc { [200, { "Content-Type" => "text/plain" }, ["OK"]] }
  
  root to: 'api/v1/home#root'

  devise_for :users,
             path: '',
             path_names: {
               sign_in: 'login',
               sign_out: 'logout'
             }
    scope module: 'api' do
    namespace :v1, defaults: { format: :json } do
      # mount_devise_token_auth_for 'User', at: 'auth'
      # devise_for :users
      get 'get_chain_limit' => 'global_settings#get_chain_limit'
      post 'set_chain_limit' => 'global_settings#set_chain_limit'
      get 'get_debug_api' => 'global_settings#get_debug_api'
      post 'set_debug_api' => 'global_settings#set_debug_api'
      post 'signup' => 'registrations#create'
      resource :sessions, only: %i[show create destroy]
      resources :users, only: [:index, :show] do 
        collection do
          get 'generate_invitation'
          get 'contact_list'
          post 'accept_invitation'
          patch 'update_password'
          patch 'update_avatar'
          patch 'edit_contact_label'
          post 'get_contact_label'
          post 'destroy_relationship'
          post 'update_relation'
          get 'category_sizes'
          post 'create_category_size'
          delete 'destroy_category_size'
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
          post 'requests/accept' => 'item_requests#bulk_accept'
          post 'unit_option_destroy'
        end
      end
      resources :user_category_prices, only: [:create]
      resources :user_relationship_prices,            only: [:index, :create]
      resources :user_relationship_request_prices,    only: [:create]
      resources :orders
      
      # Notifications
      resources :notifications, only: [:index] do
        collection do
          get  'unread_count'
          patch 'read_all'
        end
        member do
          patch 'read'
        end
      end

      # Mutual Credit / Trustlines System
      resources :trustlines do
        member do
          post 'payment'
          post 'record_debt'
          post 'record_receipt'
          get 'transactions'
        end
        collection do
          get 'summary'
          post 'find_path'
          post 'execute_path_payment'
        end
      end
      # Demo mode
      get  'demo/users' => 'demo#users'
      post 'demo/login' => 'demo#login'
      post 'demo/reset' => 'demo#reset'
      post 'demo/setup' => 'demo#setup'
      get  'demo/snapshots' => 'demo#snapshots'
      post 'demo/snapshot' => 'demo#save_snapshot'

      # Pending payments (app-level confirmation before trustline execution)
      resources :pending_payments, only: [:index, :create, :destroy] do
        member do
          put 'confirm'
          put 'reject'
          put 'mark_paid'
        end
      end

      # Debug query endpoints (no auth required)
      get 'debug/invariants' => 'debug#invariants'
      get 'debug/order/:id' => 'debug#order'
      get 'debug/requests' => 'debug#requests'
      get 'debug/user/:username' => 'debug#user'
      get 'debug/items/:username' => 'debug#items'
      post 'debug/create_request' => 'debug#create_request'
      post 'debug/accept_request/:id' => 'debug#accept_request'
      get 'debug/foaf/reconcile' => 'debug#foaf_reconcile'
      get 'debug/foaf/status' => 'debug#foaf_status'
      get 'debug/foaf/events/:trustline_id' => 'debug#foaf_events'

      # Authenticated FOAF reads scoped to current_user (replaces the
      # equivalent /v1/debug/foaf/* endpoints for end-user traffic).
      get 'foaf/trustlines'            => 'foaf#index'
      get 'foaf/trustlines/:id'        => 'foaf#show_trustline'
      get 'foaf/trustlines/:id/events' => 'foaf#trustline_events'

      get 'site_config' => 'site_configs#show'
      resources :subnets, only: [:index] do
        member do
          patch 'config' => 'subnets#update_config'
          get   'graph'  => 'subnets#graph'
        end
      end

      post 'verify_invitation_code' => 'home#verify_invitation_code'
      get 'available_user_type' => 'home#available_user_type'
      get 'current_user_types' => 'users#current_user_types'
      get 'private/*file_path' => 'resources#index'
      resources :item_units, only: [:index]
      resources :change_passwords, only: [:update]
    end
  end
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  quotes = [
    "Negative!  I am a meat popsicle!",
    "Not without a 27B/6!",
    "This is your receipt for your husband... and this is my receipt for your receipt.",
    "There is no spoon.",
    "Shall we play a game?",
    "I'm sorry, Dave. I'm afraid I can't do that.",
    "These aren't the droids you're looking for.",
    "This page will self-destruct in five seconds."
  ]

  match "/.env", to: proc { [404, {}, [quotes.sample]] }, via: :all
  match "/.env.*", to: proc { [404, {}, [quotes.sample]] }, via: :all
  match "/.git", to: proc { [404, {}, [quotes.sample]] }, via: :all
  match "/.git/*", to: proc { [404, {}, [quotes.sample]] }, via: :all
  
end
