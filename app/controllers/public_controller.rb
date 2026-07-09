# Base for the public Merovex Press site: anonymous access, the standalone
# public layout, and a public-styled 404 (the default errors/not_found view
# wears the Inkwell backend chrome, which isn't loaded out here).
class PublicController < ApplicationController
  allow_unauthenticated_access
  layout "public"

  private
    def render_not_found
      render "errors/public_not_found", status: :not_found
    end

    # The active record behind an id-first public slug, of the expected
    # recordable type (else a 404). Shared by blog/books show.
    def find_public_record(type)
      Record.active.find(params[:id]).tap do |record|
        raise ActiveRecord::RecordNotFound unless record.recordable.is_a?(type)
      end
    end

    # Whether the request came in on the canonical slug (else the caller 301s).
    def canonical_slug?
      params[:id] == @record.to_slug
    end
end
