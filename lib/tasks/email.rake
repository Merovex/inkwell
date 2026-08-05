# Provision the kindredquill.com sending identities and platform tenants on
# SES (docs/email-architecture.md + docs/ses-tenants.md). Idempotent: existing
# resources are read, not recreated, so re-running after a partial failure is
# safe. DRY_RUN=1 prints the plan without touching AWS.
#
#   bin/rails email:provision DRY_RUN=1   # preview
#   bin/rails email:provision             # create + print the DNS records
#
# What this deliberately does NOT do:
#   - DNS: the DKIM/MAIL FROM/DMARC records are printed as a zone snippet to
#     paste at the registrar (automate only if kindredquill.com lands on
#     Route 53).
#   - Tenant reputation policy (Strict/Standard): not in aws-sdk-sesv2 1.105 —
#     set per tenant in the console until an SDK bump exposes it.
#   - Site tenants (`site-<account_id>`): provisioned by the app when a Site
#     is created, not here. This task owns only the platform layer.
namespace :email do
  IDENTITIES = {
    "verify.kindredquill.com" => { config_set: "inkwell-transactional", tenant: "platform-auth" },
    "notify.kindredquill.com" => { config_set: "inkwell-marketing",     tenant: "platform-circles" },
    "news.kindredquill.com"   => { config_set: "inkwell-marketing",     tenant: nil } # site tenants attach later
  }.freeze

  TENANTS = %w[ platform-auth platform-circles ].freeze

  desc "Read-only probe: whose key is this, and can it see SES identities/tenants/config sets?"
  task preflight: :environment do
    region = ENV["AWS_REGION"].presence || Rails.application.credentials.dig(:ses, :region)
    creds  = Aws::Credentials.new(
      ENV["AWS_ACCESS_KEY_ID"].presence  || Rails.application.credentials.dig(:ses, :access_key_id),
      ENV["AWS_SECRET_ACCESS_KEY"].presence || Rails.application.credentials.dig(:ses, :secret_access_key)
    )
    abort "No credentials found (ses.* in Rails credentials, or AWS_* env)." if creds.access_key_id.blank?

    ses = Aws::SESV2::Client.new(region:, credentials: creds)
    probe = lambda do |label, &check|
      result = check.call
      puts "  ✓ #{label}#{result ? " — #{result}" : ""}"
    rescue Aws::Errors::ServiceError => e
      puts "  ✗ #{label} — #{e.class.name.split("::").last}: #{e.message}"
    end

    begin
      who = Aws::STS::Client.new(region:, credentials: creds).get_caller_identity
      puts "key belongs to: #{who.arn} (account #{who.account}, region #{region})"
      puts "→ that IAM principal's policies are what the *IF* hangs on."
    rescue Aws::Errors::ServiceError => e
      puts "sts:GetCallerIdentity failed (#{e.message}) — key may be invalid."
    end

    probe.("ses:ListEmailIdentities") { "#{ses.list_email_identities(page_size: 5).email_identities.map(&:identity_name).join(", ")}" }
    probe.("ses:ListConfigurationSets") { ses.list_configuration_sets.configuration_sets.join(", ") }
    probe.("ses:ListTenants") { t = ses.list_tenants.tenants; t.any? ? t.map(&:tenant_name).join(", ") : "none yet" }
    puts "Reads passing usually means the policy is ses:* (writes will pass too)."
    puts "Reads denied means the key is send-only — run provision with an admin key via AWS_* env vars."
  end

  desc "Create the kindredquill.com SES identities + platform tenants; print the DNS records"
  task provision: :environment do
    # The app's ses.* credentials by default; override with AWS_ACCESS_KEY_ID /
    # AWS_SECRET_ACCESS_KEY (+ optional AWS_REGION) to run one-off with an
    # admin key when the sending key's IAM policy is send-only.
    region = ENV["AWS_REGION"].presence || Rails.application.credentials.dig(:ses, :region)
    creds  = Aws::Credentials.new(
      ENV["AWS_ACCESS_KEY_ID"].presence  || Rails.application.credentials.dig(:ses, :access_key_id),
      ENV["AWS_SECRET_ACCESS_KEY"].presence || Rails.application.credentials.dig(:ses, :secret_access_key)
    )
    dry = ENV["DRY_RUN"].present?
    abort "No ses credentials configured (needed unless DRY_RUN=1)." if !dry && creds.access_key_id.blank?

    ses = dry ? nil : Aws::SESV2::Client.new(region:, credentials: creds)
    account_id = dry ? "<account>" : Aws::STS::Client.new(region:, credentials: creds).get_caller_identity.account
    dkim = {} # domain => tokens

    IDENTITIES.each do |domain, opts|
      if dry
        puts "would create identity #{domain} (default config set #{opts[:config_set]}) + MAIL FROM bounce.#{domain}"
        dkim[domain] = %w[ token1 token2 token3 ]
        next
      end

      begin
        resp = ses.create_email_identity(email_identity: domain, configuration_set_name: opts[:config_set])
        dkim[domain] = resp.dkim_attributes.tokens
        puts "created identity #{domain}"
      rescue Aws::SESV2::Errors::AlreadyExistsException
        got = ses.get_email_identity(email_identity: domain)
        dkim[domain] = got.dkim_attributes.tokens
        puts "identity #{domain} already exists (status: #{got.verification_status})"
      end

      # Custom MAIL FROM aligns SPF with the subdomain (the runbook pattern).
      ses.put_email_identity_mail_from_attributes(
        email_identity: domain,
        mail_from_domain: "bounce.#{domain}",
        behavior_on_mx_failure: "USE_DEFAULT_VALUE"
      )
    end

    TENANTS.each do |name|
      if dry
        puts "would create tenant #{name}"
        next
      end
      begin
        ses.create_tenant(tenant_name: name)
        puts "created tenant #{name}"
      rescue Aws::SESV2::Errors::AlreadyExistsException
        puts "tenant #{name} already exists"
      end
    end

    # Associate each tenant with the identity + config set its mail rides.
    associations = IDENTITIES.filter_map do |domain, opts|
      next unless opts[:tenant]
      [ [ opts[:tenant], "arn:aws:ses:#{region}:#{account_id}:identity/#{domain}" ],
        [ opts[:tenant], "arn:aws:ses:#{region}:#{account_id}:configuration-set/#{opts[:config_set]}" ] ]
    end.flatten(1)

    associations.each do |tenant, arn|
      if dry
        puts "would associate #{tenant} ← #{arn}"
        next
      end
      begin
        ses.create_tenant_resource_association(tenant_name: tenant, resource_arn: arn)
        puts "associated #{tenant} ← #{arn.split(/:(?=[^:]+\z)/).last}"
      rescue Aws::SESV2::Errors::AlreadyExistsException, Aws::SESV2::Errors::ConflictException
        puts "association exists: #{tenant} ← #{arn.split(/:(?=[^:]+\z)/).last}"
      end
    end

    feedback_host = "feedback-smtp.#{region}.amazonses.com"
    puts <<~DNS

      ── DNS records to publish for kindredquill.com ─────────────────────────
      #{IDENTITIES.keys.map do |domain|
          tokens = dkim[domain]
          [
            tokens.map { |t| "#{t}._domainkey.#{domain}.  CNAME  #{t}.dkim.amazonses.com." },
            "bounce.#{domain}.  MX   10 #{feedback_host}.",
            %(bounce.#{domain}.  TXT  "v=spf1 include:amazonses.com -all"),
            %(_dmarc.#{domain}.  TXT  "v=DMARC1; p=quarantine; rua=mailto:support@kindredquill.com"),
            ""
          ]
        end.flatten.join("\n")}
      # Root lock (docs/email-architecture.md — the root never sends):
      kindredquill.com.  TXT  "v=spf1 -all"
      _dmarc.kindredquill.com.  TXT  "v=DMARC1; p=reject; rua=mailto:support@kindredquill.com"
      ────────────────────────────────────────────────────────────────────────

      Console follow-ups (not in aws-sdk-sesv2 1.105):
        - Set tenant reputation policy: platform-auth → Strict, platform-circles → Standard.
        - Per-subdomain DMARC moves p=quarantine → p=reject once reports look aligned.
    DNS
  end

  # The inbound stack: SES receipt rule → S3 → SNS → the app's :ses ingress.
  # PRECONDITIONS (console, done once): the kindredquill-inbound-email bucket
  # exists with the AllowSESPuts bucket policy, and inkwell-ses has s3:GetObject
  # on it. Idempotent like provision. Afterwards: put the printed topic ARN in
  # credentials (mailin.sns_topic_arn), deploy, THEN add the root MX record —
  # MX last, or support@ blackholes while the rule doesn't exist.
  INBOUND_BUCKET   = "kindredquill-inbound-email"
  INBOUND_RULE_SET = "kindredquill-inbound"
  INBOUND_TOPIC    = "kindredquill-mailin"
  INBOUND_ADDRESS  = "support@kindredquill.com"
  INGRESS_ENDPOINT = "https://app.kindredquill.com/rails/action_mailbox/ses/inbound_emails"

  desc "Provision the support@ inbound stack: SNS topic, receipt rule → S3, activate"
  task provision_inbound: :environment do
    region = ENV["AWS_REGION"].presence || Rails.application.credentials.dig(:ses, :region)
    creds  = Aws::Credentials.new(
      ENV["AWS_ACCESS_KEY_ID"].presence  || Rails.application.credentials.dig(:ses, :access_key_id),
      ENV["AWS_SECRET_ACCESS_KEY"].presence || Rails.application.credentials.dig(:ses, :secret_access_key)
    )
    dry = ENV["DRY_RUN"].present?
    abort "No credentials (ses.* or AWS_* env; needed unless DRY_RUN=1)." if !dry && creds.access_key_id.blank?

    if dry
      puts "would create SNS topic #{INBOUND_TOPIC}, subscribe #{INGRESS_ENDPOINT},"
      puts "create receipt rule set #{INBOUND_RULE_SET} with rule for #{INBOUND_ADDRESS}"
      puts "  (S3 → #{INBOUND_BUCKET}, prefix support/, SNS notify), scan on, TLS optional, then activate."
      next
    end

    sns = Aws::SNS::Client.new(region:, credentials: creds)
    topic_arn = sns.create_topic(name: INBOUND_TOPIC).topic_arn # idempotent by name
    puts "topic: #{topic_arn}"

    # The gem auto-confirms the SubscriptionConfirmation POST — but only once
    # the app is deployed with mailin.sns_topic_arn set. Subscribing before
    # that leaves it PendingConfirmation; re-run this task to re-request.
    # A pending subscription (arn "PendingConfirmation") doesn't count as
    # existing — re-subscribing the same endpoint makes SNS re-send the
    # confirmation, which is exactly the re-request path after deploying.
    confirmed = sns.list_subscriptions_by_topic(topic_arn:).subscriptions
                   .any? { |sub| sub.endpoint == INGRESS_ENDPOINT && sub.subscription_arn.start_with?("arn:") }
    if confirmed
      puts "subscription confirmed (#{INGRESS_ENDPOINT})"
    else
      sns.subscribe(topic_arn:, protocol: "https", endpoint: INGRESS_ENDPOINT)
      puts "subscription requested for #{INGRESS_ENDPOINT} (confirms once the deployed app answers)"
    end

    ses = Aws::SES::Client.new(region:, credentials: creds) # receipt rules are the classic API
    begin
      ses.create_receipt_rule_set(rule_set_name: INBOUND_RULE_SET)
      puts "created rule set #{INBOUND_RULE_SET}"
    rescue Aws::SES::Errors::AlreadyExists
      puts "rule set #{INBOUND_RULE_SET} exists"
    end

    rule = {
      name: "support",
      enabled: true,
      recipients: [ INBOUND_ADDRESS ],
      scan_enabled: true, # SES spam/virus verdicts ride the receipt headers
      actions: [ { s3_action: { bucket_name: INBOUND_BUCKET, object_key_prefix: "support/", topic_arn: } } ]
    }
    begin
      ses.create_receipt_rule(rule_set_name: INBOUND_RULE_SET, rule:)
      puts "created rule support → s3://#{INBOUND_BUCKET}/support/ + SNS"
    rescue Aws::SES::Errors::AlreadyExists
      ses.update_receipt_rule(rule_set_name: INBOUND_RULE_SET, rule:)
      puts "rule support existed — updated in place"
    end

    # Only ONE rule set is active per account/region. If a sibling app's set is
    # active (Covenant!), do NOT steal it — merge instead: this rule must move
    # into the active set. The task refuses rather than guesses.
    active = ses.describe_active_receipt_rule_set.metadata&.name
    if active.nil?
      ses.set_active_receipt_rule_set(rule_set_name: INBOUND_RULE_SET)
      puts "activated #{INBOUND_RULE_SET}"
    elsif active == INBOUND_RULE_SET
      puts "#{INBOUND_RULE_SET} already active"
    else
      puts <<~WARN
        !! NOT activating: rule set #{active.inspect} is currently active (a sibling
        app's inbound?). SES allows one active set per account/region — activating
        ours would break theirs. Add the support rule to #{active.inspect} instead:
          AWS_* bin/rails email:adopt_inbound_rule ACTIVE_SET=#{active}
      WARN
    end

    puts <<~NEXT

      Next:
        1. credentials: mailin.sns_topic_arn = #{topic_arn}
           (optional: mailin.account_slug = the Site whose /admin/missives receives support mail)
        2. deploy — the app then auto-confirms the SNS subscription
        3. re-run this task if the subscription shows pending, to re-request
        4. LAST: add DNS  kindredquill.com.  MX  10 inbound-smtp.#{region}.amazonaws.com.
    NEXT
  end

  desc "Add the support receipt rule to an already-active rule set (ACTIVE_SET=name)"
  task adopt_inbound_rule: :environment do
    set = ENV.fetch("ACTIVE_SET")
    region = ENV["AWS_REGION"].presence || Rails.application.credentials.dig(:ses, :region)
    creds  = Aws::Credentials.new(
      ENV["AWS_ACCESS_KEY_ID"].presence  || Rails.application.credentials.dig(:ses, :access_key_id),
      ENV["AWS_SECRET_ACCESS_KEY"].presence || Rails.application.credentials.dig(:ses, :secret_access_key)
    )
    sns = Aws::SNS::Client.new(region:, credentials: creds)
    topic_arn = sns.create_topic(name: INBOUND_TOPIC).topic_arn
    ses = Aws::SES::Client.new(region:, credentials: creds)
    rule = {
      name: "kindredquill-support",
      enabled: true,
      recipients: [ INBOUND_ADDRESS ],
      scan_enabled: true,
      actions: [ { s3_action: { bucket_name: INBOUND_BUCKET, object_key_prefix: "support/", topic_arn: } } ]
    }
    begin
      ses.create_receipt_rule(rule_set_name: set, rule:)
      puts "added kindredquill-support rule to #{set}"
    rescue Aws::SES::Errors::AlreadyExists
      ses.update_receipt_rule(rule_set_name: set, rule:)
      puts "kindredquill-support rule updated in #{set}"
    end
  end
end
