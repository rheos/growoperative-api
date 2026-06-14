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
      get 'profile' => 'users#app_profile'

      # Job 49 — OAuth provider login. Thin proxy to foaf-auth's
      # /v1/oauth/* surface; the app talks only to railsbackend for
      # everything, so foaf-auth's endpoints get mirrored here.
      get  'oauth/providers',          to: 'o_auth_proxy#providers'
      post 'oauth/:provider/start',    to: 'o_auth_proxy#start',    constraints: { provider: /[a-z]+/ }
      post 'oauth/:provider/callback', to: 'o_auth_proxy#callback', constraints: { provider: /[a-z]+/ }
      post 'oauth/apple/native',       to: 'o_auth_proxy#apple_native'
      post 'oauth/google/native',      to: 'o_auth_proxy#google_native'
      get  'oauth/links',              to: 'o_auth_proxy#links_index'
      post 'oauth/links/complete',     to: 'o_auth_proxy#links_complete'
      delete 'oauth/links/:provider',  to: 'o_auth_proxy#links_destroy', constraints: { provider: /[a-z]+/ }

      # Password reset by email. Thin (unauthenticated) proxy to foaf-auth's
      # /v1/password_reset/* surface; PasswordResetsController skips authenticate!.
      post 'password_resets'         => 'password_resets#create'
      post 'password_resets/confirm' => 'password_resets#confirm'

      # Email verification. Thin proxy to foaf-auth's /v1/email_verification/*.
      # `create` is authenticated (targets the caller's pending/unverified
      # email via Bearer); `confirm` skips authenticate! (works from the link).
      post 'email_verifications'         => 'email_verifications#create'
      post 'email_verifications/confirm' => 'email_verifications#confirm'

      # Job 11: v1 onboarding contract (master plan §1 / §Atomic
      # accept/onboarding recovery). Idempotent on (invitation_code,
      # accepted user). Status endpoint is pollable for the saga's
      # session-restore "finish joining" repair path.
      post 'onboarding'        => 'onboarding#create'
      get  'onboarding/status' => 'onboarding#status'
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
          # v1 endpoint aliases (Job 10) targeted by FoafAuthClient.
          # Legacy `update_password` / `update_avatar` paths stay live for
          # the version-skew window; saga refactor (Job 13) flips callers.
          patch 'password' => 'users#update_password'
          patch 'avatar'   => 'users#update_avatar'
          get   'profile'  => 'users#profile'
          patch 'profile'  => 'users#update_profile'
          # Public handle availability check (no auth). Rate-limited per IP
          # in the controller; full rack-attack lands with auth.foaf.io
          # (Job 26 in Phase 3).
          get   'handle_available' => 'users#handle_available'
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
        put 'set_active'
        collection do
          patch 'user_info'
          # Create-form helpers: a server-minted suggestion to pre-fill the
          # custom code field, and a live availability check as the user edits.
          get 'suggest_code'
          get 'code_available'
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

      # Admin-only credit loop forensics (superuser-gated in controller).
      get 'admin/credit_loops'      => 'credit_loops#index'
      get 'admin/credit_loops/:id'  => 'credit_loops#show'

      # Admin invitations — currently just the seed-code primitive that mints
      # a new Subnet on redemption. Superuser-gated in the controller.
      post 'admin/invitations/seed' => 'admin/invitations#create_seed'
      get  'admin/invitations/seed' => 'admin/invitations#list_seed'

      # Superuser-only user administration. Rails is the policy/audit
      # boundary; auth.foaf.io owns identity search and password mutation.
      get  'admin/users'                         => 'admin/users#index'
      get  'admin/users/:foaf_id'                => 'admin/users#show'
      post 'admin/users/:foaf_id/reset_password' => 'admin/users#reset_password'

      get 'site_config' => 'site_configs#show'
      resources :subnets, only: [:index] do
        member do
          patch 'config' => 'subnets#update_config'
          get   'graph'  => 'subnets#graph'
        end
      end

      # Public intake for new-subnet requests (POST). Admin list/update
      # are superuser-gated in the controller.
      resources :subnet_applications, only: [:create, :index, :update]

      # Public handle lookup (master plan §Handle Lookup Contract). No
       # auth — returns the minimal identity summary used for trustline
       # setup, mentions, invitations, and cross-app identity lookup.
       # Rate-limited per IP in the controller. Constraint allows handles
       # with `.` and other URL-safe punctuation.
      get 'users/by_handle/:handle' => 'users#by_handle', constraints: { handle: /[^\/?#]+/ }

      post 'verify_invitation_code' => 'home#verify_invitation_code'
      get 'available_user_type' => 'home#available_user_type'
      get 'current_user_types' => 'users#current_user_types'
      get 'private/*file_path' => 'resources#index'
      resources :item_units, only: [:index]
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
