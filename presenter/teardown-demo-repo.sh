#!/usr/bin/env bash
# Tear down one demo run made by setup-demo-repo.sh: remove the developer sandbox and its
# sandbox-scoped secrets, delete the GitHub repo, and delete the local clone. Runs on the
# presenter's Mac. The self-hosted runner is left alone: the next setup-demo-repo.sh
# --runner-vm moves it to the next repo.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: teardown-demo-repo.sh [options] [<repo-name>]

Every setting can come from an option or an environment variable; the option wins.

  <repo-name>           repo and clone to remove                 $DEMO_REPO_NAME (required)
  --owner OWNER         GitHub user or org                       $DEMO_OWNER (default: the logged-in gh user)
  --dest-root DIR       parent of the clone                      $DEMO_DEST_ROOT (default: ~/Demos)
  --sandbox NAME        developer sandbox to remove              $DEMO_SANDBOX (default: dev)
  --keep-repo           keep the GitHub repo (still removes the sandbox and the clone)
  --yes                 skip the confirmation prompt             DEMO_YES=1
  --dry-run             print what would happen; change nothing

Deleting a repo is permanent and needs the gh delete_repo scope (gh auth refresh -s delete_repo).
EOF
}

OWNER="${DEMO_OWNER:-}"; NAME="${DEMO_REPO_NAME:-}"
DEST_ROOT="${DEMO_DEST_ROOT:-$HOME/Demos}"
SANDBOX="${DEMO_SANDBOX:-dev}"
KEEP_REPO=0
YES="${DEMO_YES:-0}"
DRY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --owner) OWNER=${2:?}; shift 2 ;;
    --dest-root) DEST_ROOT=${2:?}; shift 2 ;;
    --sandbox) SANDBOX=${2:?}; shift 2 ;;
    --keep-repo) KEEP_REPO=1; shift ;;
    --yes|-y) YES=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) [ -z "${NAME_ARG:-}" ] || { echo "only one repo name allowed" >&2; exit 2; }; NAME_ARG=$1; NAME=$1; shift ;;
  esac
done
[ -n "$NAME" ] || { usage >&2; exit 2; }

say() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
run() { if [ "$DRY" = 1 ]; then printf '    [dry-run] %s\n' "$*"; else "$@"; fi; }

command -v gh >/dev/null || die "gh not found"
command -v sbx >/dev/null || die "sbx not found"
gh auth status >/dev/null 2>&1 || die "gh is not logged in: run 'gh auth login'"
[ -n "$OWNER" ] || OWNER=$(gh api user -q .login)
REPO="$OWNER/$NAME"
DEST="$DEST_ROOT/$NAME"

# Refuse anything that doesn't look like a clone of this repo, so a typo can't rm -rf the wrong folder.
if [ -e "$DEST" ]; then
  url=$(git -C "$DEST" remote get-url origin 2>/dev/null || true)
  case "$url" in
    "https://github.com/$REPO.git"|"https://github.com/$REPO"|"git@github.com:$REPO.git") ;;
    *) die "$DEST is not a clone of $REPO (origin: ${url:-none}); not deleting it" ;;
  esac
fi
if [ "$KEEP_REPO" = 0 ]; then
  gh repo view "$REPO" >/dev/null 2>&1 || { echo "note: $REPO not found on GitHub; skipping repo delete" >&2; KEEP_REPO=1; }
  [ "$KEEP_REPO" = 1 ] || gh auth status 2>&1 | grep -q 'delete_repo' \
    || die "gh token lacks the delete_repo scope: run 'gh auth refresh -s delete_repo' (or pass --keep-repo)"
fi

cat <<EOF
Teardown
  sandbox     $SANDBOX (and its scoped anthropic and github secrets)
  repo        $([ "$KEEP_REPO" = 1 ] && echo "kept: $REPO" || echo "DELETE https://github.com/$REPO (permanent)")
  clone       $([ -e "$DEST" ] && echo "delete $DEST" || echo "none at $DEST")
EOF
if [ "$DRY" = 0 ] && [ "$YES" = 0 ]; then
  read -rp "Proceed? [y/N] " ok </dev/tty
  [ "$ok" = y ] || [ "$ok" = Y ] || die "aborted"
fi

# The sandbox bind-mounts the clone, so it goes first.
say "Removing sandbox $SANDBOX and its scoped secrets"
run sbx rm --force "$SANDBOX" 2>/dev/null || true
run sbx secret rm anthropic --sandbox "$SANDBOX" 2>/dev/null || true
run sbx secret rm github --sandbox "$SANDBOX" 2>/dev/null || true

if [ "$KEEP_REPO" = 0 ]; then
  say "Deleting $REPO"
  run gh repo delete "$REPO" --yes
fi

if [ -e "$DEST" ]; then
  say "Deleting $DEST"
  run rm -rf "$DEST"
fi

if [ "$DRY" = 0 ]; then
  say "Remaining secrets (expect nothing scoped to $SANDBOX and no global github)"
  sbx secret ls
fi
