# frozen_string_literal: true

# Sluggable — opaque public identifiers (Crockford base32, uppercase only).
#
# Usage:
#   class Account < ApplicationRecord
#     include Sluggable
#     self.slug_param_only = true   # bare slug in URLs, no name prefix
#     self.slug_prefix = ""         # optional, e.g. "A"
#   end
#
# Migration requirement (the validation alone is NOT race-safe):
#   add_column :accounts, :slug, :string, null: false
#   add_index  :accounts, :slug, unique: true
#
# Lookup behavior:
#   Account.find(42)            -> primary key (integer or numeric string)
#   Account.find("K7TXM4")      -> slug
#   Account.find("k7txm4")      -> slug (normalized: upcased, I/L->1, O->0)
#   Account.find("acme-K7TXM4") -> slug (to_param form, last segment wins)
#   Account.find(1, 2) / find([1, 2]) -> passes through to Rails as before
module Sluggable
  extend ActiveSupport::Concern

  SLUG_LENGTH = 6

  # Crockford base32: no I, L, O, U. Case-insensitive on input,
  # canonical uppercase in storage. Human-transcribable.
  CROCKFORD_32 = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
  LETTERS      = "ABCDEFGHJKMNPQRSTVWXYZ"

  SLUG_FORMAT = /\A[#{LETTERS}][#{CROCKFORD_32}]*\z/

  # Crockford decode rules: i/l read as 1, o reads as 0.
  def self.normalize(input)
    input.to_s.upcase.tr("ILO", "110")
  end

  included do
    class_attribute :slug_param_only, default: false
    class_attribute :slug_prefix, default: ""

    before_validation :set_slug, on: :create
    validates :slug, presence: true, uniqueness: true,
                     format: { with: SLUG_FORMAT }
  end

  def to_param
    return slug if self.class.slug_param_only

    title_or_name = to_s.presence || self.class.model_name.human.downcase
    [ title_or_name.to_s.parameterize, slug ].compact.join("-")
  end

  def save(**)  = retrying_slug_collision { super }
  def save!(**) = retrying_slug_collision { super }

  private

  def set_slug
    self.slug ||= self.class.generate_unique_slug
  end

  # Retry with a fresh slug if the unique index catches a generation race.
  # Message sniffing is adapter-specific; the "slug" fragment matches SQLite
  # and MySQL constraint errors.
  def retrying_slug_collision
    attempts = 0
    begin
      yield
    rescue ActiveRecord::RecordNotUnique => e
      raise unless new_record? && e.message.include?("slug") && (attempts += 1) <= 2

      self.slug = self.class.generate_unique_slug
      retry
    end
  end

  # Slug-aware find, applied to both the class and all relations
  # (scopes, associations) via `relation.extending`.
  module SlugFinder
    # Preserve Rails semantics: find(1, 2), find([1, 2]), and block
    # form all pass straight through. Only a single, non-numeric
    # argument is treated as a possible slug.
    def find(*ids, &block)
      return super if block_given? || ids.size != 1

      id = ids.first
      return super if id.is_a?(Array) || id.is_a?(Integer)
      return super if id.to_s.match?(/\A\d+\z/) # NOTE: assumes integer PKs

      find_by!(slug: extract_slug(id))
    end

    private

    def extract_slug(param)
      Sluggable.normalize(param.to_s.split("-").last)
    end
  end

  class_methods do
    def relation
      super.extending(SlugFinder)
    end

    def find(*ids, &block)
      all.find(*ids, &block)
    end

    # Never issue a slug that collides with a first path segment the app host
    # serves unprefixed (see AccountHost::Extractor). Only words of exactly
    # SLUG_LENGTH Crockford characters can collide; "assets" qualifies.
    RESERVED_SLUGS = %w[ ASSETS ].freeze

    def generate_unique_slug
      loop do
        candidate = "#{slug_prefix}#{generate_slug}"
        next if RESERVED_SLUGS.include?(candidate)
        return candidate unless exists?(slug: candidate) # advisory; index is authoritative
      end
    end

    def generate_slug(size: SLUG_LENGTH)
      # First character is always a letter so a slug can never be
      # mistaken for a numeric primary key.
      first = LETTERS.chars.sample(random: SecureRandom)
      rest  = SecureRandom.alphanumeric(size - 1, chars: CROCKFORD_32.chars)
      "#{first}#{rest}"
    end
  end
end
