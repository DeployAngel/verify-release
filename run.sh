#!/usr/bin/env bash
# Registers the deploy with DeployAngel, waits for its verdict, and leaves
# report.rb to decide whether the step passes.
set -uo pipefail

error() { echo "::error title=DeployAngel::$1"; }

if ! command -v ruby >/dev/null 2>&1; then
  error "Ruby isn't installed on this runner. Add ruby/setup-ruby before this step."
  exit 1
fi
if [ -z "${DEPLOYANGEL_API_TOKEN:-}" ]; then
  error "api-token is empty. Save a \"CI deploys\" token as a secret and pass it as api-token."
  exit 1
fi
case "$INPUT_WAIT" in
  initial|verdict|closed|none) ;;
  *) error "wait must be initial, verdict, closed, or none, not \"$INPUT_WAIT\"."; exit 1 ;;
esac

# The gem gets its own gem home, so the app's bundle is never touched. The
# CLI doesn't need Bundler or Rails.
export GEM_HOME="${RUNNER_TEMP:-/tmp}/deployangel-gem"
export GEM_PATH="$GEM_HOME"
unset BUNDLE_GEMFILE RUBYOPT
if ! gem list --installed deployangel --version "$INPUT_GEM_VERSION" >/dev/null 2>&1; then
  if ! gem install deployangel --version "$INPUT_GEM_VERSION" --no-document --silent; then
    error "Couldn't install the deployangel gem ($INPUT_GEM_VERSION). It needs Ruby 3.1 or later; ruby/setup-ruby installs one."
    exit 1
  fi
fi
deployangel="$GEM_HOME/bin/deployangel"

target=()
if [ -n "$INPUT_COMMIT" ]; then target+=(--commit="$INPUT_COMMIT"); fi
if [ -n "$INPUT_VERSION" ]; then target+=(--version="$INPUT_VERSION"); fi

if [ "$INPUT_REGISTER" = "true" ]; then
  if ! "$deployangel" release ${target[@]+"${target[@]}"}; then
    error "Couldn't register the deploy. Check that api-token is a \"CI deploys\" token."
    exit 1
  fi
fi
[ "$INPUT_WAIT" = "none" ] && exit 0

# verify looks up one release: by version when one was given, otherwise by
# the commit that was registered.
if [ -n "$INPUT_VERSION" ]; then
  target=(--version="$INPUT_VERSION")
elif [ -n "${INPUT_COMMIT:-${GITHUB_SHA:-}}" ]; then
  target=(--commit="${INPUT_COMMIT:-$GITHUB_SHA}")
fi

document="$(mktemp)"
"$deployangel" verify --wait --until="$INPUT_WAIT" --timeout="$INPUT_TIMEOUT" --format=json \
  ${target[@]+"${target[@]}"} >"$document"
code=$?
ruby "$GITHUB_ACTION_PATH/report.rb" "$document" "$code"
