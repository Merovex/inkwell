# Deliverability seeds must be able to subscribe even though several of their
# domains (mail-tester.com, mailosaur.net, …) sit on valid_email2's disposable
# list — the Subscriber validator uses disposable_domain_with_allow_list, and
# this merges SEED_DOMAINS into that allow list so the model constant stays the
# single source of truth (no config/allow_listed_email_domains.yml to drift).
# allow_list memoizes a Set, so merging mutates the one the validator reads;
# re-merging on reload is a no-op.
Rails.application.config.to_prepare do
  ValidEmail2.allow_list.merge(Subscriber::SEED_DOMAINS)
end
