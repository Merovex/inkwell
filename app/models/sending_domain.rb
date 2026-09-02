# One BYOD sending domain on the SES onboarding path — the email twin of
# CustomDomain. Always a subdomain (news.merovex.press, never the apex): the
# author's root-domain reputation stays out of it. The domain column's UNIQUE
# index is what stops two accounts claiming the same identity.
class SendingDomain < ApplicationRecord
  belongs_to :account

  # pending      — row created, SES identity not yet written
  # verifying    — identity created; waiting on DKIM CNAMEs + MAIL FROM MX (poll job)
  # live         — DKIM SUCCESS and MAIL FROM SUCCESS; broadcast_from uses it
  # error        — provisioning failed (surface the reason)
  # disconnected — author removed it; the SES identity is deleted
  STATUSES = %w[ pending verifying live error disconnected ].freeze

  validates :domain, presence: true,
    uniqueness: { case_sensitive: false } # advisory; the unique index is authoritative
  validates :status, inclusion: { in: STATUSES }

  scope :connected, -> { where.not(status: "disconnected") }
  scope :live, -> { where(status: "live") }

  STATUSES.each { |s| define_method("#{s}?") { status == s } }

  # The DNS records the author must publish, shaped for the copy_field rows.
  # Three CNAMEs prove DKIM; the MX + SPF TXT on the MAIL FROM subdomain align
  # SPF; the DMARC TXT is a recommendation, not a gate.
  def dkim_records
    Array(dkim_tokens).map do |token|
      { name: "#{token}._domainkey.#{domain}", value: "#{token}.dkim.amazonses.com" }
    end
  end

  def mail_from_mx_value = "10 feedback-smtp.#{Ses::Client.region}.amazonses.com"
  def spf_value = %("v=spf1 include:amazonses.com -all")
  def dmarc_name = "_dmarc.#{domain}"
  def dmarc_value = %("v=DMARC1; p=quarantine")
end
