# A reader magnet — the free ebook a welcome campaign gives new subscribers.
# Attach one to a Drop and that email grows a "Get {title}" claim button; the
# email itself never carries a file or a file URL. A plain account-scoped
# model, not a recordable: this is fulfillment bookkeeping, not site content,
# so no versioning ceremony and no site rebuilds.
#
# Files live in the PRIVATE r2_magnets bucket — never kindredquill-sites,
# which the edge Worker serves publicly by path. Readers only ever see
# short-lived presigned URLs, minted per download by Claims::Downloads.
class Magnet < ApplicationRecord
  # epub + pdf covers everyone: Send-to-Kindle has taken epub since 2022
  # (mobi is retired), Apple Books and Play Books read epub natively.
  FORMATS = %w[ epub pdf ].freeze
  CONTENT_TYPES = { "epub" => "application/epub+zip", "pdf" => "application/pdf" }.freeze
  MAX_FILE_SIZE = 50.megabytes

  belongs_to :account, default: -> { Current.account }

  has_one_attached :epub, service: :r2_magnets
  has_one_attached :pdf,  service: :r2_magnets

  has_many :grants, dependent: :destroy
  # Drop versions keep their magnet_id through revisions (Recordable#build_successor
  # dups scalars); deleting the magnet unhooks them rather than orphaning the FK.
  has_many :drops, dependent: :nullify

  validates :title, presence: true
  validate :acceptable_files

  scope :ordered, -> { order(:title) }

  # The formats a claim page can actually offer.
  def formats = FORMATS.select { |format| file_for(format).attached? }

  def file_for(format) = format == "epub" ? epub : pdf

  # A subscriber's key to this magnet, minted at drop-send time and reused on
  # every later send (the unique [magnet, subscriber] index makes this
  # race-safe, same idiom as Drip#enroll).
  def grant_to(subscriber)
    grants.create_or_find_by!(subscriber: subscriber)
  end

  private
    # A magnet with nothing to download is a dead claim page — require at
    # least one file, and hold each to its format's real content type.
    def acceptable_files
      errors.add(:base, "Attach an EPUB or a PDF") unless FORMATS.any? { |format| file_for(format).attached? }

      FORMATS.each do |format|
        file = file_for(format)
        next unless file.attached?

        errors.add(format.to_sym, "must be an #{format.upcase} file") unless file.content_type == CONTENT_TYPES[format]
        errors.add(format.to_sym, "must be smaller than #{MAX_FILE_SIZE / 1.megabyte} MB") if file.byte_size > MAX_FILE_SIZE
      end
    end
end
