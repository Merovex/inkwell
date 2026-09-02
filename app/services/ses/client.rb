# Thin SES v2 client for the sending-domain onboarding flow and per-site
# tenancy (docs/email-tenant-byod-plan.md): create a tenant, associate it with
# the identities/config sets its mail rides, create/read/delete a BYOD email
# identity. Only the calls the flow needs — the platform layer stays in
# lib/tasks/email.rake. Injectable everywhere it's used so tests pass a fake.
#
# Credentials come from ses.* (same keys the delivery method uses). Tenant
# resource associations need ARNs, which need the AWS account id — read from
# ses.account_id when present, else one STS lookup memoized per process.
module Ses
  class Client
    class Error < StandardError; end

    # What the status poll needs from GetEmailIdentity, in one flat value:
    # DKIM CNAMEs published AND the MAIL FROM MX resolving.
    Identity = Struct.new(:dkim_tokens, :dkim_status, :mail_from_status, keyword_init: true) do
      def verified? = dkim_status == "SUCCESS" && mail_from_status == "SUCCESS"
    end

    def self.region = Rails.application.credentials.dig(:ses, :region)

    def create_tenant(name)
      with_errors_wrapped do
        sesv2.create_tenant(tenant_name: name)
      rescue Aws::SESV2::Errors::AlreadyExistsException
        # Idempotent: re-provisioning after a partial failure is safe.
      end
    end

    # Attributes a resource's sends to the tenant. Both identities and config
    # sets associate through the same call; existing associations are kept.
    def associate_identity(tenant_name, domain) = associate(tenant_name, "identity/#{domain}")
    def associate_config_set(tenant_name, name) = associate(tenant_name, "configuration-set/#{name}")

    # Creates the BYOD identity and returns its three DKIM tokens. An identity
    # that already exists in the account (e.g. news.merovex.press, provisioned
    # by hand pre-feature) is adopted, not an error — its tokens are read back.
    def create_identity(domain, config_set: nil)
      with_errors_wrapped do
        params = { email_identity: domain }
        params[:configuration_set_name] = config_set if config_set
        sesv2.create_email_identity(**params).dkim_attributes.tokens
      rescue Aws::SESV2::Errors::AlreadyExistsException
        sesv2.get_email_identity(email_identity: domain).dkim_attributes.tokens
      end
    end

    # Custom MAIL FROM aligns SPF with the author's subdomain (the same
    # bounce.<domain> convention as the platform identities).
    def set_mail_from(domain, mail_from_domain)
      with_errors_wrapped do
        sesv2.put_email_identity_mail_from_attributes(
          email_identity: domain,
          mail_from_domain: mail_from_domain,
          behavior_on_mx_failure: "USE_DEFAULT_VALUE"
        )
      end
    end

    def get_identity(domain)
      with_errors_wrapped do
        got = sesv2.get_email_identity(email_identity: domain)
        Identity.new(
          dkim_tokens: got.dkim_attributes&.tokens,
          dkim_status: got.dkim_attributes&.status,
          mail_from_status: got.mail_from_attributes&.mail_from_domain_status
        )
      end
    end

    def delete_identity(domain)
      with_errors_wrapped do
        sesv2.delete_email_identity(email_identity: domain)
      rescue Aws::SESV2::Errors::NotFoundException
        # Already gone — disconnect stays idempotent.
      end
    end

    private
      def associate(tenant_name, resource)
        with_errors_wrapped do
          sesv2.create_tenant_resource_association(
            tenant_name: tenant_name,
            resource_arn: "arn:aws:ses:#{self.class.region}:#{aws_account_id}:#{resource}"
          )
        rescue Aws::SESV2::Errors::AlreadyExistsException, Aws::SESV2::Errors::ConflictException
        end
      end

      def sesv2
        @sesv2 ||= Aws::SESV2::Client.new(
          region: self.class.region,
          access_key_id: Rails.application.credentials.dig(:ses, :access_key_id),
          secret_access_key: Rails.application.credentials.dig(:ses, :secret_access_key)
        )
      end

      def aws_account_id
        Rails.application.credentials.dig(:ses, :account_id).presence || self.class.sts_account_id
      end

      def self.sts_account_id
        @sts_account_id ||= Aws::STS::Client.new(
          region: region,
          access_key_id: Rails.application.credentials.dig(:ses, :access_key_id),
          secret_access_key: Rails.application.credentials.dig(:ses, :secret_access_key)
        ).get_caller_identity.account
      end

      def with_errors_wrapped
        yield
      rescue Aws::Errors::ServiceError => error
        raise Error, "SES #{error.class.name.split("::").last}: #{error.message}"
      end
  end
end
