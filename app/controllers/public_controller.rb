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
end
