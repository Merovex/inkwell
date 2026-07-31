# The static-site toolchain (docs/hugo-build-pipeline.md §5.2). Production
# installs the pinned Hugo into the Docker image and sets HUGO_BIN there; dev
# machines resolve the mise-pinned binary from PATH — both are 0.164.0, and
# an upgrade is a deliberate two-pin diff (Dockerfile ARG + mise config).
#
# THEME_PATH points at a filibuster checkout. In the kindred-quill repo the
# app and theme are siblings, which is the dev default; production points at
# the vendored pinned copy.
HUGO_BIN = ENV.fetch("HUGO_BIN", "hugo")
THEME_PATH = Pathname(ENV.fetch("THEME_PATH") { Rails.root.join("../filibuster").to_s })
