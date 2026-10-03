#!/bin/bash

set -e

# Resolve the project from this script so startup also works from another directory.
cd "$(dirname "${BASH_SOURCE[0]}")"

# Load Ruby management directly; interactive zsh configuration cannot run in Bash.
chruby_prefix="$(brew --prefix chruby)"
# ShellCheck cannot resolve Homebrew's runtime-dependent installation path.
# shellcheck source=/dev/null
source "$chruby_prefix/share/chruby/chruby.sh"

# Activate correct Ruby version
chruby 3.4.1

# Serve locally; this does not publish the site.
exec bundle exec jekyll serve --host 127.0.0.1
