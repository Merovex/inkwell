Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Dynamic PWA files from app/views/pwa/* (manifest is linked in the layout).
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Authentication + the signed-in user's own account live at the top level, not
  # under /admin: signing in and managing yourself aren't domain-admin actions.
  # Passwordless (magic-link) authentication.
  resource :session, only: %i[new create destroy]
  # Redeems the emailed code — hit by the magic link and the manual entry form.
  get "session/verify" => "sessions#verify", as: :verify_session
  # First-run install setup (first user → domain admin); only when no users exist.
  resource :setup, only: %i[new create]
  # Open self-registration; only when the registration policy is :open.
  resource :signup, only: %i[new create]
  # Personal settings — always Current.user, no id in the URL. The avatar is its
  # own resource so picking/dropping a picture can auto-submit.
  namespace :user do
    resource :settings, only: %i[show update]
    resource :avatar, only: %i[update destroy]
  end

  # Inkwell — the admin backend. Everything the author uses to write, publish,
  # and moderate lives under /admin as Admin::*, gated to domain admins
  # (Admin::BaseController). The public Merovex Press site will own the root URL
  # space in a later pass.
  namespace :admin do
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
        # Email the post to subscribers. create sends (now or scheduled);
        # destroy cancels a scheduled send before it goes out.
        resource :broadcast, only: %i[create destroy]
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

    # System settings — the singleton Setting.current (no id), domain-admin only.
    # Distinct from the personal user settings below; this shapes the whole
    # install (the public Merovex Press identity).
    resource :settings, only: %i[show update]

    # Newsletter roster — domain-admin only. Read + CSV export + manual
    # unsubscribe; subscribers themselves opt in from the public site.
    resources :subscribers, only: :index do
      patch :unsubscribe, on: :member
    end

    # Broadcasts dashboard — domain-admin only. Read-only send analytics;
    # sending happens from the post page.
    resources :broadcasts, only: :index

    # Contact-form submissions (Missives) — domain-admin only. Read the feed +
    # its Trash tab; destroy purges one outright. There's no create/edit — they
    # arrive from the public /contact form and are confirmed by double opt-in.
    resources :missives, only: %i[index destroy]

    # Public-site traffic dashboard (Ahoy) — domain-admin only.
    resource :analytics, only: :show

    # Pen names / author personas — domain-admin managed; content creators select
    # one on the composer. Public bio pages live at /authors/:id.
    resources :authors, except: :show do
      # The avatar is its own resource so picking/dropping a picture auto-submits
      # — the same well as the user's own avatar.
      scope module: :authors do
        resource :avatar, only: %i[update destroy]
      end
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
  # RSS feed — declared before blog/:id so "feed" isn't swallowed as an id.
  get "blog/feed" => "blog#feed", as: :blog_feed, defaults: { format: "rss" }
  get "blog/:id" => "blog#show", as: :blog_post

  # Author persona pages: bio + their published posts and books.
  get "authors/:id" => "authors#show", as: :author_page

  # Public book catalog: published books, grouped by series.
  get "books" => "books#index", as: :books
  get "books/:id" => "books#show", as: :book

  # Mailgun event webhooks (delivered/opened/clicked/…) → broadcast metrics.
  # Authenticity is the Mailgun HMAC signature, verified in the controller.
  post "webhooks/mailgun" => "webhooks/mailgun#create"

  # The public Merovex Press site. The About page renders the site's About blurb
  # from Setting.current; the admin backend lives at /admin.
  get "about" => "pages#about", as: :about

  # Legal pages, authored in System settings (privacy carries the cookie notice).
  get "privacy" => "pages#privacy", as: :privacy
  get "terms" => "pages#terms", as: :terms

  # SEO: XML sitemap of the public surface, and a robots.txt that points at it
  # (dynamic so the Sitemap URL carries the real host).
  get "sitemap" => "pages#sitemap", as: :sitemap, defaults: { format: "xml" }
  get "robots.txt" => "pages#robots", as: :robots, format: false

  # Buy-link click-through: counts the click, then redirects to the store.
  get "buy/:id" => "distributors#show", as: :buy

  # Newsletter opt-in (anonymous, double opt-in) at /newsletter. create records a
  # pending subscriber; the token links confirm and unsubscribe. See ADR 0011.
  get  "newsletter" => "subscriptions#new", as: :newsletter
  post "newsletter" => "subscriptions#create"
  # Token is optional so a missing/blank/truncated token (bare URL, an email
  # gateway that strips the path) lands on the branded "invalid link" page from
  # the controller, not a raw 404.
  get  "newsletter/confirm(/:token)" => "subscriptions#confirm", as: :confirm_newsletter
  get  "newsletter/unsubscribe(/:token)" => "subscriptions#unsubscribe", as: :unsubscribe_newsletter
  # "Keep me subscribed" from a re-engagement nudge — a reliable re-engagement
  # signal that doesn't depend on Mailgun open tracking (ADR 0014).
  get  "newsletter/keep(/:token)" => "subscriptions#keep", as: :keep_newsletter
  # Post-signup "check your inbox" page (minimal layout). Both a real opt-in and a
  # honeypot-tripped one redirect here, so the two are indistinguishable.
  get  "newsletter/sent" => "subscriptions#sent", as: :newsletter_sent

  # Contact form (anonymous, double opt-in) at /contact. create records an
  # unconfirmed Missive and emails a fixed-template confirmation; the token link
  # confirms it. Content is only ever read in /admin/missives, never emailed out.
  get  "contact" => "contacts#new", as: :contact
  post "contact" => "contacts#create"
  # Post-submit "check your inbox" page (minimal layout); real + honeypot land here.
  get  "contact/sent" => "contacts#sent", as: :contact_sent
  # Optional token → a bare/blank token renders the branded invalid-link page.
  get  "contact/confirm(/:token)" => "contacts#confirm", as: :confirm_contact

  root "pages#home"
end
