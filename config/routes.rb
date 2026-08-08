Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Dynamic PWA files from app/views/pwa/* (manifest is linked in the layout).
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Host roles (AccountHost, ADR 0018). Until APP_HOST is set every constraint
  # passes and routing behaves exactly as the single-tenant app always has.
  #   app    — any path on the app host (sign-in, setup, personal settings)
  #   admin  — app host AND a real account slug prefix resolved by the extractor
  #   public — a tenant host resolved by domain (the app host never serves the
  #            public site; tenant hosts never serve the admin or sign-in)
  app_routes    = ->(request) { !AccountHost.enforced? || AccountHost.app_host?(request) }
  admin_routes  = ->(request) { !AccountHost.enforced? || request.env["account_host.slug_account"].present? }
  public_routes = ->(request) { !AccountHost.enforced? || request.env["account_host.tenant_account"].present? }

  # Bare app host: the account picker. Authentication is forced by the
  # controller; one membership skips the ceremony and lands straight in that
  # account's admin. Declared before the public root; distinct :as.
  constraints(->(request) { AccountHost.enforced? && AccountHost.app_host?(request) && request.env["account_host.slug_account"].nil? }) do
    root "accounts#index", as: :app_host_root
  end

  # Authentication + the signed-in user's own account live at the top level, not
  # under /admin: signing in and managing yourself aren't domain-admin actions.
  # On the app host these work unprefixed — you sign in before you have an
  # account context, exactly like Fizzy.
  constraints(app_routes) do
    # Passwordless (magic-link) authentication.
    resource :session, only: %i[new create destroy]
    # Redeems the emailed code — hit by the magic link and the manual entry form.
    get "session/verify" => "sessions#verify", as: :verify_session
    # First-run install setup (first user → domain admin); only when no users exist.
    resource :setup, only: %i[new create]
    # Self-registration, gated by a join code (see Signup).
    resource :signup, only: %i[new create]
    # Create a press: any signed-in user; lands in the new account's admin.
    resources :accounts, only: %i[new create]
    # Solid Queue dashboard — platform staff only (Admin::JobsBaseController
    # gates on root); app host only, so tenant domains never even route it.
    mount MissionControl::Jobs::Engine, at: "/jobs"
    # The platform support inbox: support@kindredquill.com mail-in, root
    # staff only (Support::MissivesController gates like /jobs). App host
    # only — this is the App's mail, not any Site's.
    resources :missives, only: %i[index show destroy], module: :support

    # The App's help desk (Tickets). User side at /support: your own tickets,
    # bucketed to you (the Goals pattern); the thread is Comments on the
    # spine, so the nested routes mirror the circles' comment shape. Staff
    # side: the queue at /admin/tickets (bare app host, root-gated like
    # /jobs); a status change is a revision, updated through the nested
    # singular status resource — CRUD, no custom verbs.
    scope module: :support do
      # Platform bulletins (announcements to every user, docs/log 2026-08-06):
      # authored here by root staff; publish/schedule ride the Publishable
      # ladder. Declared BEFORE tickets — its path: "support" wildcard (GET
      # /support/:id) would otherwise swallow /support/bulletins as a ticket
      # id. Readers get the top-level /bulletins below.
      resources :bulletins, path: "support/bulletins", only: %i[index new create edit update], as: :support_bulletins
      resources :tickets, path: "support", only: %i[index new create show] do
        resources :comments, only: %i[new create]
      end
      resources :comments, path: "support/comments", only: %i[edit update destroy], as: :support_comments
      scope path: "/admin", as: :desk do
        resources :tickets, only: :index, controller: "desk_tickets" do
          resource :status, only: :update, controller: "statuses"
        end
      end
    end

    # Announcements, readable by any signed-in user — the bell links here.
    resources :bulletins, only: %i[index show]

    # The bell: opening the flyout marks everything read; the index is the
    # full 30-day window behind the flyout's "See all".
    resources :notifications, only: :index
    # Marking the bell read = creating a reading (the flyout POSTs on open).
    namespace :notifications do
      resource :reading, only: :create
    end
    # Personal settings — always Current.user, no id in the URL. The avatar is its
    # own resource so picking/dropping a picture can auto-submit.
    namespace :user do
      resource :settings, only: %i[show update]
      resource :avatar, only: %i[update destroy]
      # Rotate your invite code (inviters only — see User#can_invite?).
      resource :join_code, only: :update
    end

    # Author circles — cross-site accountability groups a user belongs to,
    # independent of any one site, so they live on the app host at the top level
    # (not under a /{SLUG}/admin) — their URLs never carry a site slug. index is
    # the door from the app menu (a person is in several); show is a circle's
    # home (a preview of its discussions). The nested messages are the circle's
    # discussions: index lists them all, new is the composer, create posts one.
    resources :circles, only: %i[index new create show edit update] do
      # Every circle on the platform (not just yours) — browse-only discovery.
      collection { get :all }
      # The circle's home (circles#show) IS the feed — messages + pulse answers
      # newest-first, lazy-loading more on scroll, filterable by kind. A card's
      # comments open the thread as a modal (fetched into the feed's "modal"
      # frame); comment submits return there via back=wall.
      resources :threads, only: :show, module: "circles/walls", as: :wall_threads
      # A message's edit surface: the composer as a modal (fetched into the
      # feed's "modal" frame); saves return to the feed.
      resources :edits, path: "wall/edits", only: :show, module: "circles/walls", as: :wall_edits
      resources :messages, only: %i[index show new create edit update destroy], module: :circles do
        collection { get :archived }
        member do
          patch :archive
          patch :unarchive
        end
      end
      # Comments hang off any circle record (a Message today, more later), so
      # create nests under the generic record; member actions are keyed by the
      # comment's own Record id.
      resources :records, only: [] do
        resources :comments, only: %i[new create], module: :circles
        # Boosts on any circle record (message, comment, pulse answer) —
        # same shape as the admin side, circle-scoped.
        resources :boosts, only: :create, module: :circles
      end
      resources :comments, only: %i[edit update destroy], module: :circles
      resources :boosts, only: :destroy, module: :circles

      # Your own seat: DELETE = leave the circle (non-owners only — the owner
      # deletes or hands off, they don't abandon).
      resource :membership, only: :destroy, module: :circles
      # The membership page (⋯ menu → "Membership"): roster, invite form,
      # pending seats — Basecamp's "Who's on this project?".
      resources :members, only: :index, module: :circles

      # Invitations — the only door into a circle (they're invite-only; the
      # user-lock beside a circle's name says so). Any member extends one
      # (create); the invitee accepts it from their circles index. destroy
      # doubles as the invitee declining and the inviter/owner revoking.
      resources :invitations, only: %i[create destroy], module: :circles do
        # Accepting = creating the acceptance (membership in, invitation out).
        resource :acceptance, only: :create, module: :invitations
      end

      # Pulse — the circle's recurring check-in. Owner sets it up; members
      # subscribe (their own subscription resource) and post a Beat (their answer).
      resources :pulses, only: %i[new create show edit update destroy], module: :circles do
        # The member's own seat at the check-in: POST joins, DELETE opts out.
        resource :subscription, only: %i[create destroy], module: :pulses
        resources :beats, only: %i[create edit update]
      end
    end

    # Personal practice goals — the author's own, independent of any site or
    # circle (the user is the record bucket). Tallies are the reports against
    # a goal; ids are Record ids, like circles' pulses.
    resources :goals do
      # Archive is the calm way to retire a goal (reversible, no purge clock):
      # POST sets it aside, DELETE restores — the admin archives shape.
      collection { get :archived }
      resource :archive, only: %i[create destroy], module: :goals
      resources :tallies, only: %i[create edit update destroy], module: :goals do
        # Today's record, add-or-edit, as a modal (fetched into the "modal" frame).
        collection { get :today }
      end
    end
  end

  # Inkwell — the admin backend. Everything the author uses to write, publish,
  # and moderate lives under /admin as Admin::*, gated to domain admins
  # (Admin::BaseController). Under APP_HOST enforcement it exists only on the
  # app host behind a resolved /{SLUG} prefix — a tenant domain's /admin is a
  # routing 404, not a controller rejection.
  # /{SLUG} — the account's front door is its admin. Slug-mounted requests
  # only (never legacy mode, where this would shadow the public root).
  constraints(->(request) { request.env["account_host.slug_account"].present? }) do
    root to: redirect { |_params, request| "#{request.script_name}/admin" }, as: :account_root
  end

  constraints(admin_routes) do
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
        collection { get :archived }
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
        collection { get :archived }
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
          # Archive/unarchive any recordable — one shared controller keyed by the
          # Record id (like boosts and comment member actions), no per-type copies.
          resource :archive, only: %i[create destroy]
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
        get :archived, on: :collection
        scope module: :books do
          resource :publish, only: %i[create destroy]
          resource :depiction, only: %i[create destroy]
          resources :events, only: :index
          resources :changes, only: :show
          resources :versions, only: :show
        end
      end

      # Collections — recordables on the spine, Publishable and sortable exactly
      # like Series (its show/edit page lists its books, drag-sortable; reorder
      # PATCHes the Installment positions). A Collection is any curated grouping;
      # a Series is a reading sequence.
      resources :collections do
        patch :reorder, on: :member
        get :search, on: :collection
        scope module: :collections do
          resource :publish, only: %i[create destroy]
        end
      end

      # Container↔book membership, added/removed immediately from the typeahead on
      # the book page (add a series/collection) or a series/collection page (add a
      # book). One controller serves every container (Series, Collection).
      resources :installments, only: %i[create destroy]

      # Store buy-links, added/removed live from a book, series, or collection
      # page. Keyed by the target Record, so one controller serves them all.
      resources :distributors, only: %i[create destroy]

      # System settings — the account's one Site (no id), admin only. Distinct
      # from the personal user settings; this shapes the account's public identity.
      resource :settings, only: %i[show update]

      # Connect-your-domain (Cloudflare for SaaS, docs/custom-domain-onboarding.md):
      # index shows status + the form and the author's DNS instructions; create
      # provisions the custom hostnames + KV; destroy tears the whole connection
      # down (KV keys and custom hostnames both, freeing the allowance).
      resources :custom_domains, only: %i[index create destroy]

      # The Email tab (docs/email-tenant-byod-plan.md): BYOD sending domains —
      # index shows the sending address + DNS instructions; create provisions
      # the SES identity; destroy deletes it. The handle is the author's chosen
      # local part on the shared sending lane (<handle>@kindredquill.email).
      resources :sending_domains, only: %i[index create destroy]

      # The Identity tab's handle typeahead: show answers "is this handle
      # free?" (and counter-offers a suggestion when it isn't). The handle
      # itself saves through the settings form (Site delegates to account).
      resource :handle_availability, only: :show

      # The "Try again" badge on a verifying domain: POST creates a fresh
      # status check — the poll runs inline and the redirect reports the
      # outcome, instead of the author waiting on the background cadence.
      resource :custom_domain_check, only: :create
      resource :sending_domain_check, only: :create

      # The SiteDesigner (ADR 0022, docs/site-designer.md): the author designs
      # the public site against a live preview. The working design lives in
      # localStorage until Save (PATCH designer) graduates it to the account,
      # where the next real build reads it. The preview endpoint is stateless:
      # POST builds the posted design + current published content through the
      # real exporter/Hugo pipeline; GET serves the built files into the
      # editor's iframe.
      resource :designer, only: %i[show update]
      scope path: "designer", module: :designers, as: :designer do
        resource :preview, only: :create
        # Declared before the wildcard so "version" isn't swallowed as a file path.
        get "preview/version" => "previews#version", as: :preview_version
        get "preview/(*path)" => "previews#show", as: :preview_file, format: false
        # The Site's image slots (logo / hero banner / newsletter photo) —
        # binaries can't ride the localStorage lab, so these persist
        # immediately, unlike the rest of the working design.
        patch "image/:slot" => "images#update", as: :image
        delete "image/:slot" => "images#destroy"
      end

      # Newsletter roster — domain-admin only. Read + CSV export + manual
      # unsubscribe; subscribers themselves opt in from the public site. Resend
      # re-issues the confirmation email to a still-pending subscriber. Seed
      # status is a resource: POST flags a deliverability-seed inbox, DELETE
      # returns it to a real reader.
      resources :subscribers, only: :index do
        patch :unsubscribe, on: :member
        post  :resend, on: :member
        resource :seed, only: %i[create destroy], module: :subscribers
        # Reactivation lifts a delivery suppression: a bounced subscriber
        # returns to confirmed (mailbox trouble — consent was never revoked);
        # a complained one is re-invited via a fresh double opt-in instead,
        # never silently. Unsubscribed has no reactivation — they chose.
        resource :reactivation, only: :create, module: :subscribers
      end

      # Broadcasts dashboard — domain-admin only. Read-only send analytics;
      # sending happens from the post page. show is one send's detail:
      # per-recipient milestones and the link-click breakdown.
      resources :broadcasts, only: %i[index show]

      # Contact-form submissions (Missives) — domain-admin only. Read the feed +
      # its Trash tab; destroy purges one outright. There's no create/edit — they
      # arrive from the public /contact form and are confirmed by double opt-in.
      resources :missives, only: %i[index show destroy]

      # Public-site traffic dashboard (Ahoy) — domain-admin only.
      resource :analytics, only: :show

      # Pen names / author personas — domain-admin managed; content creators select
      # one on the composer. Public bio pages live at /authors/:id.
      resources :authors, except: :show do
        # The avatar is its own resource so picking/dropping a picture auto-submits
        # — the same well as the user's own avatar.
        scope module: :authors do
          resource :avatar, only: %i[update destroy]
          # The hero portrait is a second image resource, same auto-submitting
          # well: used for the hero when set, otherwise the avatar stands in.
          resource :hero_image, only: %i[update destroy]
        end
      end

      # Drip campaigns (welcome sequences) and their ordered drops (emails).
      # Activate/deactivate gates enrollment; reorder drags the drops into send order.
      resources :drips do
        collection do
          get :dashboard
        end
        member do
          patch :activate
          patch :reorder
        end
        scope module: :drips do
          resources :drops, only: %i[new create edit update destroy]
        end
      end

      # Living styleguide for building/eyeballing standard elements + components.
      get "theme" => "static#theme", as: :theme
      # Composition demos: a list-view (perma-header + list) and an item-view (editable header).
      get "list-view" => "static#list_view", as: :list_view
      get "item-view" => "static#item_view", as: :item_view

      # Admin landing: the traffic dashboard.
      root "analytics#show"
    end
  end

  # SES event notifications relayed via SNS (delivered/opened/clicked/bounced/
  # complained) → broadcast metrics. Authenticity is the SNS message signature,
  # verified in the controller (ADR 0015 Phase 2). Deliberately unconstrained:
  # the SNS subscription points at the tenant domain and stays put (ADR 0018).
  post "webhooks/ses" => "webhooks/ses#create"

  # Postmark event webhooks (delivered/opened/clicked/bounced/complained) →
  # broadcast metrics. Authenticity is HTTP Basic Auth verified in the controller.
  # Deliberately unconstrained, like the SES hook (ADR 0018).
  post "webhooks/postmark" => "webhooks/postmark#create"

  # The public site — everything below resolves per-tenant by domain.
  constraints(public_routes) do
    # Public posts. The index lists published posts only; :id on the article page
    # is the Record id (the stable public identity), matching the admin side.
    get "posts" => "blog#index", as: :posts
    # RSS feed — declared before posts/:id so "feed" isn't swallowed as an id.
    get "posts/feed" => "blog#feed", as: :posts_feed, defaults: { format: "rss" }
    get "posts/:id" => "blog#show", as: :post

    # Author persona pages: bio + their published posts and books.
    get "authors/:id" => "authors#show", as: :author_page

    # Public book catalog: published books, grouped by series.
    get "books" => "books#index", as: :books
    get "books/:id" => "books#show", as: :book

    # The public Merovex Press site. The About page renders the site's About blurb
    # from the account's Site; the admin backend lives at /admin.
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
    # Where blocked signups land (hygiene / rate limit / Turnstile) — a proxied
    # island like sent, because the static site can't render a flash and
    # GET /newsletter isn't on the Worker allowlist.
    get  "newsletter/rejected" => "subscriptions#rejected", as: :newsletter_rejected

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
end
