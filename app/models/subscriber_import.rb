require "csv"

# A partner's sign-up export (StoryOrigin, BookFunnel, any CSV of addresses)
# brought onto a site's list by hand — readers who opted in somewhere else
# before the live integration was connected. Uploading only previews: nothing
# touches the roster until the admin confirms, and then every new address goes
# through Subscriber.opt_in, so it lands :pending and gets our double opt-in
# email. A partner's export is not the consent evidence a click from the
# mailbox is.
#
# De-dupes twice: within the file, and against the roster. An address the site
# already holds is left alone in EVERY status — confirmed and pending readers
# aren't re-mailed, and an unsubscribed/bounced/complained one is never
# re-invited (opt_in itself would revive those, which an import must not).
# Addresses the signup gate rejects, or the cross-site suppression list blocks
# (ADR 0027), are skipped too.
#
# The row is the audit trail: who brought which file in, when, under what
# source, and what became of each address.
class SubscriberImport < ApplicationRecord
  # The roster's source column. Partners name themselves; anything else is a
  # plain CSV import. Labels come from Subscriber::INTEGRATION_SOURCES.
  SOURCES = %w[ storyorigin bookfunnel import ].freeze

  # The header names partners put the address under, compared case-blind.
  EMAIL_HEADERS = [ "email", "email address", "e-mail" ].freeze

  MAX_SIZE = 5.megabytes

  belongs_to :account, default: -> { Current.account }
  belongs_to :creator, class_name: "User", default: -> { Current.user }

  has_one_attached :file

  enum :status, %w[ uploaded inviting invited ].index_by(&:itself), default: "uploaded"

  scope :newest_first, -> { order(created_at: :desc) }

  validates :source, inclusion: { in: SOURCES }
  validate :file_is_a_list_of_addresses, on: :create

  # The unique, normalized addresses in the file, in file order.
  def emails
    @emails ||= rows.filter_map { |row| Subscriber.normalize_value_for(:email_address, row[email_header]).presence }.uniq
  end

  # What would become of each address, as of now: "invite", the status of the
  # row the site already holds ("confirmed", "unsubscribed", …), "rejected"
  # (the signup gate's hygiene ladder), or "suppressed".
  def outcomes
    existing   = account.subscribers.where(email_address: emails).pluck(:email_address, :status).to_h
    suppressed = Suppression.in_force_for(account).joins(:person)
      .where(people: { email_address: emails }).distinct.pluck("people.email_address").to_set

    emails.index_with do |email|
      if existing[email]                         then existing[email]
      elsif Subscriber.rejection_reason(email)   then "rejected"
      elsif suppressed.include?(email)           then "suppressed"
      else "invite"
      end
    end
  end

  # Outcome => count: the preview before invitations go out, the record after.
  def summary = tally || outcomes.values.tally

  def invitation_count = summary.fetch("invite", 0)

  # Send the invitations. Outcomes are re-read here rather than trusted from
  # the preview — the roster may have moved since — so a re-run after a crash
  # finds the already-invited as "pending" and leaves them alone.
  def invite!
    results = outcomes
    results.each do |email, outcome|
      Subscriber.opt_in(email_address: email, source:) if outcome == "invite"
    end
    update!(status: :invited, tally: results.values.tally, invited_at: Time.current)
  end

  def source_label = Subscriber.label_for_source(source)

  private
    def rows
      @rows ||= CSV.parse(contents, headers: true)
    end

    def email_header
      rows.headers.compact.find { |header| header.strip.downcase.in?(EMAIL_HEADERS) }
    end

    # Before save the upload is still the request's file; after, it's in storage.
    def contents
      pending = attachment_changes["file"]&.attachable
      raw = pending.respond_to?(:read) ? pending.read.tap { pending.rewind } : file.download
      raw.force_encoding(Encoding::UTF_8).delete_prefix("﻿")
    end

    def file_is_a_list_of_addresses
      return errors.add(:file, "is missing — choose a CSV file") unless file.attached?
      return errors.add(:file, "is over #{MAX_SIZE / 1.megabyte} MB") if file.blob.byte_size > MAX_SIZE
      return errors.add(:file, "has no Email column") unless email_header
      errors.add(:file, "has no addresses in it") if emails.empty?
    rescue CSV::MalformedCSVError, ArgumentError
      errors.add(:file, "isn't a readable CSV file")
    end
end
