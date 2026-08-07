# Enable newsletter signup for one account — the whole sequence in one
# command, safe to re-run (every step is idempotent):
#
#   SES tenant   (EmailConnection.provision_tenant — stamps the signup gate)
#   Turnstile    (TurnstileConnection.provision — the bot front door)
#   Republish    (SiteBuildJob.schedule — the band swaps mailto for the form)
#
#   bin/rails "newsletter:enable[cohwall]"                        # dev box
#   bin/kamal app exec 'bin/rails "newsletter:enable[cohwall]"'   # production
#
# The sending-domain admin flow runs the same provisioning on connect
# (EmailConnection#connect); this task is the by-hand entry point — accounts
# connected before that landed, or comped without a BYOD sending domain.
namespace :newsletter do
  desc "Provision SES tenant + Turnstile widget and republish the site. bin/rails 'newsletter:enable[handle|slug|domain]'"
  task :enable, [ :account ] => :environment do |_task, args|
    ident = args[:account].presence or abort %(Usage: bin/rails "newsletter:enable[handle|slug|domain]")
    account = Account.find_by(handle: ident.downcase) ||
              Account.find_by(slug: Sluggable.normalize(ident)) ||
              Account.find_by(domain: AccountHost.canonical_host(ident)) or
      abort "No account matches #{ident.inspect} (tried handle, slug, domain)."

    puts "Account: #{account.name} (#{account.slug})"

    result = EmailConnection.provision_tenant(account)
    abort "  SES tenant failed: #{result.error}" unless result.ok?
    puts "  SES tenant #{account.ses_tenant_name} ✓"

    begin
      TurnstileConnection.provision(account)
      puts "  Turnstile widget #{account.reload.turnstile_site_key} ✓"
    rescue Cloudflare::Client::Error => error
      abort "  Turnstile widget failed: #{error.message} (re-run after fixing; the tenant stamp is kept)"
    end

    SiteBuildJob.schedule(account)
    puts "  Site rebuild queued — the band picks up the form on publish."
  end
end
