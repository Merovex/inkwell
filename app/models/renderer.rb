require "open3"

# Runs the pinned Hugo binary against an exported workspace
# (docs/hugo-build-pipeline.md §5.2): one short-lived child process per
# build, niced so web requests always win the scheduler. --panicOnWarning
# turns template warnings (missing key, nil access) into hard build
# failures, and stderr is captured without --quiet — that flag swallows
# errorf text, which would leave a failed build with no reason attached.
class Renderer
  class BuildError < StandardError; end

  TIMEOUT = 30.seconds

  def initialize(workspace)
    @workspace = Pathname(workspace)
  end

  # Renders to destination (default: public/ inside the workspace) and
  # returns it. clean: empties the destination first — for fixed
  # destinations that are rebuilt in place, like the SiteDesigner preview.
  def render!(destination: workspace.join("public"), clean: false)
    _out, err, status = Timeout.timeout(TIMEOUT) do
      Open3.capture3(
        { "HUGO_ENVIRONMENT" => "production" },
        "nice", "-n", "10",
        HUGO_BIN, "build",
        "--source", workspace.to_s,
        "--destination", destination.to_s,
        "--minify", "--panicOnWarning",
        *("--cleanDestinationDir" if clean),
        chdir: workspace.to_s
      )
    end
    raise BuildError, err unless status.success?
    Pathname(destination)
  end

  private
    attr_reader :workspace
end
