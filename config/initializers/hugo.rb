# The static-site toolchain (docs/hugo-build-pipeline.md §5.2). Production
# installs the pinned Hugo into the Docker image and sets HUGO_BIN there; dev
# machines resolve the mise-pinned binary from PATH — both are 0.164.0, and
# an upgrade is a deliberate two-pin diff (Dockerfile ARG + mise config).
#
# THEME_PATH points at the Hugo theme tree. The theme is vendored in this repo
# at vendor/filibuster — the primary source, edited here and shipped in the
# image by the Dockerfile's `COPY . .` — so dev, test, and production all read
# it from there. Set the THEME_PATH env to point at an external checkout to
# override (e.g. developing against a sibling filibuster clone).
HUGO_BIN = ENV.fetch("HUGO_BIN", "hugo")
THEME_PATH = Pathname(ENV.fetch("THEME_PATH") { Rails.root.join("vendor/filibuster").to_s })
