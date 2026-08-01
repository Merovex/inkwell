# The SiteDesigner's preview: stateless build-from-payload
# (docs/site-designer.md §2.3). The working design lives in the browser
# (localStorage — scaffolding until the schema settles), so create receives
# the design JSON, builds it with the account's current published content
# through the real exporter + Hugo pipeline, and show serves the built
# files into the editor's iframe. Nothing here persists anything.
class Admin::Designers::PreviewsController < Admin::BaseController
  # show serves the built site's files — including its JavaScript — into
  # the preview iframe. Forgery protection would 422 controller-served JS
  # on plain GETs (the cross-origin <script> embedding defense); a GET
  # file-server carries no CSRF surface, and the auth gate stays.
  skip_forgery_protection only: :show

  def create
    workspace = Exporter.new(Current.account,
      design: SiteDesign.new(params).to_h,
      base_url: "#{admin_designer_preview_file_path(path: nil)}/",
      preview: true).export!
    Renderer.new(workspace).render!(destination: preview_root, clean: true)
    head :no_content
  rescue SiteDesign::Invalid => error
    render json: { error: error.message }, status: :unprocessable_entity
  ensure
    FileUtils.rm_rf(workspace) if workspace  # workspaces are ephemeral (§5.2)
  end

  # Development only: the designer polls this and rebuilds the preview when
  # the theme tree changes, so theme edits show up like live reload.
  def version
    head :not_found and return unless Rails.env.development?

    render json: { version: Theme.current.fingerprint }
  end

  def show
    file = preview_root.join(params[:path].presence || "index.html").cleanpath
    file = file.join("index.html") if file.directory?

    if file.file? && file.to_s.start_with?("#{preview_root}/")
      # The preview is rebuilt in place on every design change, so its URLs must
      # never be cached — otherwise the browser (or Thruster) serves a stale page
      # for a URL the author already visited, which reads as "stuck on the home
      # page." no-store keeps every navigation a fresh fetch.
      response.set_header("cache-control", "no-store")
      send_file file, disposition: :inline,
        type: Mime::Type.lookup_by_extension(file.extname.delete("."))&.to_s || "application/octet-stream"
    else
      head :not_found
    end
  end

  private
    # Fixed per-account destination, rebuilt in place on every POST; the
    # iframe reloads only after the build returns, so it never reads a
    # half-written tree in practice. (Reader builds get pointer-flip
    # atomicity; the single-author preview doesn't need it.) Parallel test
    # workers each get their own tree — the fixture account is shared, and
    # one worker's clean rebuild would clobber another's mid-assertion.
    def preview_root
      Rails.root.join("tmp/builds", Current.account.slug,
        Rails.env.test? ? "preview-#{Process.pid}" : "preview")
    end
end
