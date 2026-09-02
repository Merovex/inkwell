# Deliverability seeds must be able to subscribe even though several of their
# domains (mail-tester.com, mailosaur.net, …) sit on valid_email2's disposable
# list — the Subscriber validator uses disposable_domain_with_allow_list, and
# this merges SEED_DOMAINS into that allow list so the model constant stays the
# single source of truth (no config/allow_listed_email_domains.yml to drift).
# allow_list memoizes a Set that survives code reloads, so one merge after
# boot is enough — after_initialize, not to_prepare: touching the model
# constant mid-initialization loads the SQLite adapter prematurely (the
# "loaded before application initialization" warning on every prod boot).
Rails.application.config.after_initialize do
  ValidEmail2.allow_list.merge(Subscriber::SEED_DOMAINS)
end
