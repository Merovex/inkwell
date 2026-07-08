Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Dynamic PWA files from app/views/pwa/* (manifest is linked in the layout).
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Inkwell — the admin backend. Everything the author uses to write, publish,
  # and moderate lives under /admin as Admin::*. The public Merovex Press site
  # will own the root URL space in a later pass.
  namespace :admin do
    # Passwordless (magic-link) authentication.
    resource :session, only: %i[new create destroy]
    # Redeems the emailed code — hit by the magic link and the manual entry form.
    get "session/verify" => "sessions#verify", as: :verify_session

    # First-run install setup (first user → domain admin); only when no users exist.
    resource :setup, only: %i[new create]
    # Open self-registration; only when the registration policy is :open.
    resource :signup, only: %i[new create]

    # Unpublished work: drafts + scheduled posts. Declared before resources :posts
    # so /admin/posts/drafts isn't swallowed by /admin/posts/:id. DELETE destroys
    # outright — unpublished work is discardable, no trash ceremony.
    scope module: :posts do
      resources :drafts, only: %i[index destroy], path: "posts/drafts"
    end

    # Blog posts — the first recordable on the Record/Recordable spine.
    # :id here is always the Record id (the stable identity), never a version id.
    resources :posts do
      scope module: :posts do
        # State transitions as resources (Fizzy style): POST does, DELETE undoes.
        resource :publish, only: %i[create destroy]
        resource :pin, only: %i[create destroy]
        # Version history: the feed, a specific tracked change, a frozen version.
        resources :events, only: :index
        resources :changes, only: :show
        resources :versions, only: :show
        # The comment composer on the post page (new swaps into the prompt's
        # turbo frame); member actions are shallow.
        resources :comments, only: %i[new create]
      end
    end

    # Unpublished forum work: drafts + scheduled messages. Declared before
    # resources :messages so /admin/forum/drafts isn't swallowed by /admin/forum/:id.
    scope module: :messages do
      resources :drafts, only: %i[index destroy], path: "forum/drafts", as: :message_drafts
    end

    # The message board — one board for the install, at /admin/forum: the messages
    # index IS the tool page. Messages mirror posts on the spine (:id is the
    # Record id), with the same transition/history/comment sub-resources.
    resources :messages, path: "forum" do
      scope module: :messages do
        resource :publish, only: %i[create destroy]
        resource :pin, only: %i[create destroy]
        resources :events, only: :index
        resources :changes, only: :show
        resources :versions, only: :show
        resources :comments, only: %i[new create]
      end
    end

    # Message-board categories — a plain lookup table with its own tiny CRUD
    # (no versioning ceremony), edited from the board's toolbar.
    resources :categories, except: :show

    # Comment member actions — shallow, since a comment's Record id is globally
    # unique (:id is always the Record id, same as everywhere else).
    resources :comments, only: %i[edit update destroy]

    # The chatroom — a single room for the whole install, so a singular
    # resource with no id. Lines are recordables; their member actions are
    # shallow on the Record id like everything else.
    resource :chatroom, only: :show
    resources :chat_lines, only: %i[create edit update destroy]

    # Boosts — tiny appreciations pinned to any record (:record_id is the
    # Record id, so one route serves posts, comments, and future recordables).
    # Nested create mirrors comments; destroy is shallow and only ever your own.
    resources :records, only: [] do
      scope module: :records do
        resources :boosts, only: :create
      end
    end
    resources :boosts, only: :destroy

    # Book series — recordables on the spine. A series' show/edit page lists
    # its books, drag-sortable; reorder PATCHes the Installment positions.
    resources :series do
      patch :reorder, on: :member
      get :search, on: :collection
      scope module: :series do
        resource :publish, only: %i[create destroy]
      end
    end

    # Books — recordables with a versioned cover (depiction). Series membership
    # is managed with the typeahead (Installments), not the book form.
    resources :books do
      get :search, on: :collection
      scope module: :books do
        resource :publish, only: %i[create destroy]
        resource :depiction, only: %i[create destroy]
        resources :events, only: :index
        resources :changes, only: :show
        resources :versions, only: :show
      end
    end

    # Series↔book membership, added/removed immediately from the typeahead on
    # either the book page (add a series) or the series page (add a book).
    resources :installments, only: %i[create destroy]

    # Store buy-links, added/removed live from a book or series page. Keyed by
    # the target Record, so one controller serves both.
    resources :distributors, only: %i[create destroy]

    # Personal settings — always Current.user, no id in the URL. The avatar is
    # its own resource so picking/dropping a picture can auto-submit.
    namespace :user do
      resource :settings, only: %i[show update]
      resource :avatar, only: %i[update destroy]
    end

    # Living styleguide for building/eyeballing standard elements + components.
    get "theme" => "static#theme", as: :theme
    # Composition demos: a list-view (perma-header + list) and an item-view (editable header).
    get "list-view" => "static#list_view", as: :list_view
    get "item-view" => "static#item_view", as: :item_view

    # Admin landing. Temporary: point the dashboard at the styleguide until
    # there's a real home for the backend.
    root "static#theme"
  end

  # Public blog. The index lists published posts only; :id on the article page
  # is the Record id (the stable public identity), matching the admin side.
  get "blog" => "blog#index", as: :blog
  get "blog/:id" => "blog#show", as: :blog_post

  # Public book catalog: published books, grouped by series.
  get "books" => "books#index", as: :books
  get "books/:id" => "books#show", as: :book

  # The public Merovex Press site. Static for now; the admin backend lives at
  # /admin.
  root "pages#home"
end
