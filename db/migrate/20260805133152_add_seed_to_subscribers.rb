class AddSeedToSubscribers < ActiveRecord::Migration[8.2]
  def change
    # Deliverability-seed inboxes (aboutmy.email, mailosaur, …): allowed to
    # subscribe and confirm, but excluded from counts and from broadcast/drip
    # sends. Set at creation from Subscriber::SEED_DOMAINS, or manually from
    # the admin roster for rotating-domain services.
    add_column :subscribers, :seed, :boolean, default: false, null: false
  end
end
