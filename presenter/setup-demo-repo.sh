#!/usr/bin/env bash
# Create a disposable GitHub repo from the faq-site seed this script lives in and configure it for the
# Phase A demo: clone, new remote, push main and the baseline tag, repo variables and
# secrets, branch protection on main and, with --runner-vm, moving the self-hosted runner
# to the new repo, and, when the fixer App is given, Phase B: FIXER_* values, the agent-fix
# label, and adding the repo to the App's installation. Runs on the presenter's Mac.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: setup-demo-repo.sh [options] [<repo-name>]

Every setting can come from an option or an environment variable; the option wins.

  <repo-name>           new repo and clone name                  $DEMO_REPO_NAME (required)
  --owner OWNER         GitHub user or org                       $DEMO_OWNER (default: the logged-in gh user)
  --source DIR          seed repo to clone                       $DEMO_SOURCE (default: the repo this script is in)
  --dest-root DIR       parent for the new clone                 $DEMO_DEST_ROOT (default: ~/Demos)
  --private             create a private repo                    DEMO_VISIBILITY=private (default: public, so
                                                                 the audience can open it; repos are deleted
                                                                 after each run)
  --namespace NS        KIT_NAMESPACE                            $KIT_NAMESPACE (default: jeremydavis86783)
  --kit-version V       KIT_VERSION                              $KIT_VERSION (default: 1.0.2)
  --reviewer-id ID      REVIEWER_DOCKER_ID                       $REVIEWER_DOCKER_ID (default: mobyreviewer)
  --reviews N           required approving reviews on main       $DEMO_REVIEWS (default: 1, per the spec)
  --enforce-admins      apply branch protection to admins too    DEMO_ENFORCE_ADMINS=true (default: admins can
                                                                 bypass, which lets you merge your own PR)
  --runner-vm VM        re-register the self-hosted runner in    $DEMO_RUNNER_VM (default: none, register by hand)
                        Lima VM VM (~/actions-runner there) to the
                        new repo, with the kvm label
  --runner-name NAME    runner name                              $DEMO_RUNNER_NAME (default: lima-runner)
  Phase B (all skipped unless the App ID is set):
  --fixer-app-id ID     GitHub App ID (moby-content-fixer)     $FIXER_APP_ID
  --fixer-key-file F    the App's private key (.pem)             $FIXER_APP_PRIVATE_KEY_FILE
  --fixer-installation-id ID  the App's installation on your     $FIXER_INSTALLATION_ID (from the URL of
                        account; the new repo is added to it     Settings > Applications > Configure)
  --fixer-docker-id ID  FIXER_DOCKER_ID: the principal the fixer $FIXER_DOCKER_ID (default: the namespace,
                        acts for (delegation)                    i.e. your own Docker account)
  --yes                 skip the confirmation prompt             DEMO_YES=1
  --dry-run             print what would happen; change nothing, prompt for nothing

Secrets come from the environment (REVIEWER_DOCKER_PAT, ANTHROPIC_API_KEY, and for Phase B
FIXER_DOCKER_PAT) or are prompted
for without echo, and are passed to gh on stdin, never on a command line.

Example, fully non-interactive:
  export REVIEWER_DOCKER_PAT=... ANTHROPIC_API_KEY=... DEMO_YES=1
  setup-demo-repo.sh --runner-vm runner faq-site-$(date +%m%d%H%M)

A personal-account runner serves one repo, so --runner-vm moves it on every run: the
previous repo stops getting jobs. Tear a run down with teardown-demo-repo.sh.
EOF
}

OWNER="${DEMO_OWNER:-}"; NAME="${DEMO_REPO_NAME:-}"
SOURCE="${DEMO_SOURCE:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || true)}"
DEST_ROOT="${DEMO_DEST_ROOT:-$HOME/Demos}"
VISIBILITY="${DEMO_VISIBILITY:-public}"
NAMESPACE="${KIT_NAMESPACE:-jeremydavis86783}"
KIT_VERSION="${KIT_VERSION:-1.0.2}"
REVIEWER_ID="${REVIEWER_DOCKER_ID:-mobyreviewer}"
REVIEWS="${DEMO_REVIEWS:-1}"
ENFORCE_ADMINS="${DEMO_ENFORCE_ADMINS:-false}"
DRY=0
YES="${DEMO_YES:-0}"
RUNNER_VM="${DEMO_RUNNER_VM:-}"
RUNNER_NAME="${DEMO_RUNNER_NAME:-lima-runner}"
FIXER_APP_ID="${FIXER_APP_ID:-}"
FIXER_KEY_FILE="${FIXER_APP_PRIVATE_KEY_FILE:-}"
FIXER_INSTALLATION_ID="${FIXER_INSTALLATION_ID:-}"
FIXER_ID="${FIXER_DOCKER_ID:-$NAMESPACE}"
BASELINE_TAG=unstyled-baseline

while [ $# -gt 0 ]; do
  case "$1" in
    --owner) OWNER=${2:?}; shift 2 ;;
    --source) SOURCE=${2:?}; shift 2 ;;
    --dest-root) DEST_ROOT=${2:?}; shift 2 ;;
    --private) VISIBILITY=private; shift ;;
    --public) VISIBILITY=public; shift ;;
    --namespace) NAMESPACE=${2:?}; shift 2 ;;
    --kit-version) KIT_VERSION=${2:?}; shift 2 ;;
    --reviewer-id) REVIEWER_ID=${2:?}; shift 2 ;;
    --reviews) REVIEWS=${2:?}; shift 2 ;;
    --enforce-admins) ENFORCE_ADMINS=true; shift ;;
    --runner-vm) RUNNER_VM=${2:?}; shift 2 ;;
    --runner-name) RUNNER_NAME=${2:?}; shift 2 ;;
    --fixer-app-id) FIXER_APP_ID=${2:?}; shift 2 ;;
    --fixer-key-file) FIXER_KEY_FILE=${2:?}; shift 2 ;;
    --fixer-installation-id) FIXER_INSTALLATION_ID=${2:?}; shift 2 ;;
    --fixer-docker-id) FIXER_ID=${2:?}; shift 2 ;;
    --yes|-y) YES=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) [ -z "${NAME_ARG:-}" ] || { echo "only one repo name allowed" >&2; exit 2; }; NAME_ARG=$1; NAME=$1; shift ;;
  esac
done
[ -n "$NAME" ] || { usage >&2; exit 2; }
case "$REVIEWS" in ''|*[!0-9]*) echo "--reviews must be a number" >&2; exit 2 ;; esac
case "$VISIBILITY" in private|public) ;; *) echo "DEMO_VISIBILITY must be private or public" >&2; exit 2 ;; esac
case "$ENFORCE_ADMINS" in true|false) ;; *) echo "DEMO_ENFORCE_ADMINS must be true or false" >&2; exit 2 ;; esac

say() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
# Print the command in dry-run mode, run it otherwise.
run() { if [ "$DRY" = 1 ]; then printf '    [dry-run] %s\n' "$*"; else "$@"; fi; }

command -v git >/dev/null || die "git not found"
command -v gh >/dev/null || die "gh not found (https://cli.github.com)"

# ---- preflight (read-only) -------------------------------------------------
say "Preflight"
gh auth status >/dev/null 2>&1 || die "gh is not logged in: run 'gh auth login'"
gh auth status 2>&1 | grep -q 'workflow' \
  || echo "warning: gh token may lack the 'workflow' scope; pushing .github/workflows will fail (gh auth refresh -s workflow)" >&2

[ -n "$OWNER" ] || OWNER=$(gh api user -q .login)
REPO="$OWNER/$NAME"
DEST="$DEST_ROOT/$NAME"
URL="https://github.com/$REPO.git"

[ -d "$SOURCE/.git" ] || die "source is not a git repo: $SOURCE"
git -C "$SOURCE" rev-parse --verify -q "refs/tags/$BASELINE_TAG" >/dev/null \
  || die "source has no '$BASELINE_TAG' tag; tag the unstyled commit first"
[ -z "$(git -C "$SOURCE" status --porcelain)" ] || die "source has uncommitted changes: $SOURCE"
# A demo clone also carries presenter/, so running from one would seed the next demo with styled CSS.
git -C "$SOURCE" diff --quiet "$BASELINE_TAG" HEAD -- index.html styles.css tokens.css STYLE_GUIDE.md \
  || die "source's site files differ from $BASELINE_TAG (is $SOURCE a demo clone? run this from the seed)"
case "$(git -C "$SOURCE" log -1 --format=%ae "$BASELINE_TAG")" in
  *example.invalid) die "baseline commit still has the placeholder author; fix it before cloning" ;;
esac
[ ! -e "$DEST" ] || die "destination already exists: $DEST"
if gh repo view "$REPO" >/dev/null 2>&1; then die "$REPO already exists on GitHub; pick a new name"; fi
if [ -n "$RUNNER_VM" ]; then
  command -v limactl >/dev/null || die "limactl not found (needed for --runner-vm)"
  limactl shell "$RUNNER_VM" bash -c 'test -x ~/actions-runner/config.sh' \
    || die "no runner at ~/actions-runner in VM '$RUNNER_VM' (download and unpack it there first)"
fi

get_secret() { # name -> value on stdout; env first, then silent prompt
  local name=$1 val=${!1:-}
  if [ -z "$val" ]; then
    [ "$DRY" = 1 ] && { printf '<%s>' "$name"; return; }
    read -rsp "$name: " val </dev/tty; echo >&2
  fi
  [ -n "$val" ] || die "$name is empty"
  printf '%s' "$val"
}
DOCKER_PAT=$(get_secret REVIEWER_DOCKER_PAT)
ANTHROPIC_KEY=$(get_secret ANTHROPIC_API_KEY)
if [ -n "$FIXER_APP_ID" ]; then
  [ -n "$FIXER_KEY_FILE" ] || die "Phase B needs the App's private key: --fixer-key-file or FIXER_APP_PRIVATE_KEY_FILE"
  [ -r "$FIXER_KEY_FILE" ] || die "cannot read $FIXER_KEY_FILE"
  grep -q 'PRIVATE KEY' "$FIXER_KEY_FILE" || die "$FIXER_KEY_FILE does not look like a PEM private key"
  FIXER_PAT=$(get_secret FIXER_DOCKER_PAT)
  PHASE_B="App $FIXER_APP_ID, FIXER_DOCKER_ID=$FIXER_ID, label agent-fix, installation ${FIXER_INSTALLATION_ID:-not given (add the repo by hand)}"
else
  PHASE_B="skipped (no FIXER_APP_ID)"
fi

if [ -n "$RUNNER_VM" ]; then
  RUNNER_PLAN="move $RUNNER_NAME (VM $RUNNER_VM) here, labels self-hosted,Linux,ARM64,kvm"
  RUNNER_NEXT="moved to this repo (see above)."
else
  RUNNER_PLAN="not moved (register one by hand)"
  RUNNER_NEXT="register one for $REPO with labels self-hosted, linux, kvm, or re-run with --runner-vm."
fi
cat <<EOF
Plan
  repo        $REPO ($VISIBILITY)
  clone       $DEST  (from $SOURCE)
  variables   KIT_NAMESPACE=$NAMESPACE KIT_VERSION=$KIT_VERSION REVIEWER_DOCKER_ID=$REVIEWER_ID
  secrets     REVIEWER_DOCKER_PAT, ANTHROPIC_API_KEY
  protection  main: required check 'publish', $REVIEWS approving review(s), enforce_admins=$ENFORCE_ADMINS
  runner      $RUNNER_PLAN
  phase B     $PHASE_B
EOF
if [ "$DRY" = 0 ] && [ "$YES" = 0 ]; then
  read -rp "Proceed? [y/N] " ok </dev/tty
  [ "$ok" = y ] || [ "$ok" = Y ] || die "aborted"
fi

# ---- clone and create ------------------------------------------------------
say "Cloning seed to $DEST"
run mkdir -p "$DEST_ROOT"
run git clone "$SOURCE" "$DEST"

say "Creating $REPO"
run gh repo create "$REPO" "--$VISIBILITY" --description "Disposable FAQ demo site (style guide demo)"
run git -C "$DEST" remote set-url origin "$URL"

say "Pushing main and $BASELINE_TAG"
run git -C "$DEST" push -u origin main
run git -C "$DEST" push origin "refs/tags/$BASELINE_TAG"

# ---- repository variables and secrets -------------------------------------
say "Setting repository variables"
run gh variable set KIT_NAMESPACE --repo "$REPO" --body "$NAMESPACE"
run gh variable set KIT_VERSION --repo "$REPO" --body "$KIT_VERSION"
run gh variable set REVIEWER_DOCKER_ID --repo "$REPO" --body "$REVIEWER_ID"

say "Setting repository secrets (values passed on stdin)"
if [ "$DRY" = 1 ]; then
  printf '    [dry-run] gh secret set REVIEWER_DOCKER_PAT --repo %s < <value>\n' "$REPO"
  printf '    [dry-run] gh secret set ANTHROPIC_API_KEY --repo %s < <value>\n' "$REPO"
else
  printf '%s' "$DOCKER_PAT" | gh secret set REVIEWER_DOCKER_PAT --repo "$REPO"
  printf '%s' "$ANTHROPIC_KEY" | gh secret set ANTHROPIC_API_KEY --repo "$REPO"
fi

# ---- Phase B: the fixer --------------------------------------------------------
if [ -n "$FIXER_APP_ID" ]; then
  say "Phase B: fixer variables, secrets and label"
  run gh variable set FIXER_APP_ID --repo "$REPO" --body "$FIXER_APP_ID"
  run gh variable set FIXER_DOCKER_ID --repo "$REPO" --body "$FIXER_ID"
  if [ "$DRY" = 1 ]; then
    printf '    [dry-run] gh secret set FIXER_APP_PRIVATE_KEY --repo %s < %s\n' "$REPO" "$FIXER_KEY_FILE"
    printf '    [dry-run] gh secret set FIXER_DOCKER_PAT --repo %s < <value>\n' "$REPO"
  else
    gh secret set FIXER_APP_PRIVATE_KEY --repo "$REPO" < "$FIXER_KEY_FILE"
    printf '%s' "$FIXER_PAT" | gh secret set FIXER_DOCKER_PAT --repo "$REPO"
  fi
  run gh label create agent-fix --repo "$REPO" --color 1D63ED --force \
    --description "A person approves the content fixer working on this issue"
  # Keep the App's installation on selected repositories: add each demo repo as it is made.
  if [ -n "$FIXER_INSTALLATION_ID" ]; then
    if [ "$DRY" = 1 ]; then
      printf '    [dry-run] gh api -X PUT user/installations/%s/repositories/<id of %s>\n' "$FIXER_INSTALLATION_ID" "$REPO"
    elif ! repo_id=$(gh api "repos/$REPO" -q .id) || [ -z "$repo_id" ] \
      || ! gh api -X PUT "user/installations/$FIXER_INSTALLATION_ID/repositories/$repo_id" >/dev/null; then
      echo "warning: could not add $REPO to the App installation; add it by hand: Settings > Applications > moby-content-fixer > Configure > Repository access" >&2
    fi
  fi
fi

# ---- branch protection (after the push: the branch must exist) -------------
say "Protecting main"
PROTECTION=$(cat <<EOF
{
  "required_status_checks": { "strict": false, "contexts": ["publish"] },
  "enforce_admins": $ENFORCE_ADMINS,
  "required_pull_request_reviews": { "required_approving_review_count": $REVIEWS },
  "restrictions": null
}
EOF
)
if [ "$DRY" = 1 ]; then
  printf '    [dry-run] gh api -X PUT repos/%s/branches/main/protection --input - <<< %s\n' "$REPO" "$(echo "$PROTECTION" | tr -d '\n ')"
elif ! printf '%s' "$PROTECTION" | gh api -X PUT "repos/$REPO/branches/main/protection" --input - >/dev/null; then
  echo "warning: branch protection failed. Private repos on a free personal plan don't support it; use --public or protect main by hand." >&2
fi

# ---- self-hosted runner ----------------------------------------------------
if [ -n "$RUNNER_VM" ]; then
  say "Moving runner $RUNNER_NAME (VM $RUNNER_VM) to $REPO"
  # Deregister from the repo it serves now. If that repo is gone, no remove token can be had,
  # so the local registration files are dropped instead.
  OLD_URL=$(limactl shell "$RUNNER_VM" bash -c 'cat ~/actions-runner/.runner 2>/dev/null' \
    | sed -n 's/.*"gitHubUrl": *"\([^"]*\)".*/\1/p' || true)
  OLD_REPO=${OLD_URL#https://github.com/}
  if [ "$DRY" = 1 ]; then
    printf '    [dry-run] in VM %s: deregister from %s, config.sh --url %s --name %s --labels kvm, svc.sh install+start\n' \
      "$RUNNER_VM" "${OLD_REPO:-nothing}" "https://github.com/$REPO" "$RUNNER_NAME"
  else
    REMOVE_TOKEN=""
    [ -z "$OLD_REPO" ] || REMOVE_TOKEN=$(gh api -X POST "repos/$OLD_REPO/actions/runners/remove-token" -q .token 2>/dev/null || true)
    REG_TOKEN=$(gh api -X POST "repos/$REPO/actions/runners/registration-token" -q .token)
    # Sent on stdin so the tokens never appear on a command line.
    limactl shell "$RUNNER_VM" bash -s <<EOF
set -e
cd ~/actions-runner
sudo ./svc.sh stop >/dev/null 2>&1 || true
sudo ./svc.sh uninstall >/dev/null 2>&1 || true
if [ -f .runner ]; then
  ./config.sh remove --token "$REMOVE_TOKEN" >/dev/null 2>&1 || rm -f .runner .credentials .credentials_rsaparams
fi
./config.sh --unattended --replace --url "https://github.com/$REPO" --token "$REG_TOKEN" \
  --name "$RUNNER_NAME" --labels kvm --work _work >/dev/null
sudo ./svc.sh install >/dev/null
sudo ./svc.sh start >/dev/null
EOF
    unset REMOVE_TOKEN REG_TOKEN
    st=""
    for _ in $(seq 1 20); do
      st=$(gh api "repos/$REPO/actions/runners" -q ".runners[] | select(.name==\"$RUNNER_NAME\") | .status" 2>/dev/null || true)
      [ "$st" = online ] && break; sleep 3
    done
    [ "$st" = online ] || echo "warning: runner $RUNNER_NAME is not online yet (status: ${st:-not registered}); check 'sudo ./svc.sh status' in the VM" >&2
  fi
fi

# ---- report ----------------------------------------------------------------
if [ "$DRY" = 0 ]; then
  say "Result"
  gh variable list --repo "$REPO"
  gh secret list --repo "$REPO"
  gh api "repos/$REPO/actions/runners" -q '.runners[] | "runner: \(.name) \(.status) \([.labels[].name] | join(","))"'
fi

cat <<EOF

Done: https://github.com/$REPO

Next:
  1. Runner: $RUNNER_NEXT
     Phase B: $PHASE_B
  2. Launch the developer sandbox from the new clone:
       cd $DEST
       sbx secret set anthropic --sandbox dev -t "<API key>" --force
       sbx secret set github --sandbox dev -t "\$(gh auth token)" --force
       sbx run --name dev --skills=off ./kits/moby-developer --kit docker.io/$NAMESPACE/docker-style-guide:$KIT_VERSION . -- "Style the site per the docker-style-guide skill, commit on a new branch, push it, and open a PR."

Teardown: $(dirname "$0")/teardown-demo-repo.sh --owner $OWNER --dest-root $DEST_ROOT $NAME
EOF
