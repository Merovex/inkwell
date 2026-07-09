class AddEngagementToSubscribers < ActiveRecord::Migration[8.2]
  def change
    # Engagement-based sunset (list hygiene): last_engaged_at is the most recent
    # open/click across their broadcasts (reset point); re_engagement_sent_at
    # marks when the "still want these?" nudge went out. See SubscriberSunsetJob.
    change_table :subscribers, bulk: true do |t|
      t.datetime :last_engaged_at
      t.datetime :re_engagement_sent_at
    end

    # The weekly sunset sweep prefilters on status + how long they've been cold.
    add_index :subscribers, [ :status, :last_engaged_at ]
  end
end
