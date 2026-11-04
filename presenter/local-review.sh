#!/usr/bin/env bash
# Run the Phase A reviewer locally, without GitHub: the same steps as the `review` job in
# faq-site/.github/workflows/review.yml (policy, scoped secrets, create, prove the blast radius,
# render, review, collect, remove), then print the verdict and the comment gate.sh would post.
# This is the spec's fallback 5 (section 8): "show the YAML and say the runner is the only difference".
#
# Two ways to run it:
#   on any host with sbx (the runner VM, or the Mac):   local-review.sh [options] <repo-dir>
#   from the Mac, reviewing in the Lima VM as mobyreviewer:  local-review.sh --vm runner [options] <repo-dir>
# --vm bundles the committed branch, copies it and this script into the VM, runs there, and
# copies the outputs back. Nothing is pushed anywhere.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: local-review.sh [options] <repo-dir>

  --base REF          base to diff against (default: main)
  --pr N              PR number shown in the prompt and footer (default: 0, local-only)
  --name NAME         sandbox name (default: local-review-<timestamp>)
  --namespace NS      Docker Hub namespace (default: $KIT_NAMESPACE or jeremydavis86783)
  --kit-version V     reviewer and style-guide tag (default: $KIT_VERSION or 1.0.2)
  --reviewer-id ID    Docker identity named in the footer (default with --vm: mobyreviewer;
                      otherwise left out, since this host's sbx login is whoever you are)
  --out DIR           where outputs land (default: <repo-dir>/out/local-review-<timestamp>)
  --vm NAME           run inside Lima VM NAME instead of here (run this from the Mac)
  --keep              leave the sandbox and its secrets in place afterwards
  -h, --help          this help

Reviews the committed HEAD of <repo-dir>; uncommitted changes are not included. The Anthropic
key comes from $ANTHROPIC_API_KEY or a silent prompt and is scoped to this sandbox only.
Exit status: 0 for pass, 1 for request_changes (missing or invalid verdict counts as that), 2 for usage.
EOF
}

BASE=main; PR=0; NAME=""; OUT=""; VM=""; KEEP=0
NAMESPACE="${KIT_NAMESPACE:-jeremydavis86783}"
KIT_VERSION="${KIT_VERSION:-1.0.2}"
REVIEWER_ID=""
REPO=""

while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE="$2"; shift 2 ;;
    --pr) PR="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    --kit-version) KIT_VERSION="$2"; shift 2 ;;
    --reviewer-id) REVIEWER_ID="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --vm) VM="$2"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) [ -z "$REPO" ] || { echo "only one repo-dir" >&2; exit 2; }; REPO="$1"; shift ;;
  esac
done
[ -n "$REPO" ] || { usage >&2; exit 2; }

say() { printf '\n==> %s\n' "$*"; }
die() { echo "local-review: $*" >&2; exit 2; }

REPO="$(cd "$REPO" && git rev-parse --show-toplevel)" || die "$REPO is not a git repo"
TS="$(date +%Y%m%d-%H%M%S)"
NAME="${NAME:-local-review-$TS}"
BASE_SHA="$(git -C "$REPO" rev-parse --verify -q "$BASE^{commit}")" || die "base '$BASE' not found in $REPO"
HEAD_DESC="$(git -C "$REPO" log -1 --format='%h %s')"
git -C "$REPO" diff --quiet HEAD -- || echo "warning: uncommitted changes in $REPO are not reviewed" >&2

# ---- --vm: hand off to the Lima VM ----------------------------------------------------------
if [ -n "$VM" ]; then
  command -v limactl >/dev/null || die "limactl not found (--vm is for the Mac)"
  OUT="${OUT:-$REPO/out/local-review-$TS}"
  # Under the VM user's home: that path is known to mount (the runner's checkouts live there too).
  WORK="$(limactl shell "$VM" sh -c 'echo "$HOME"')/local-review-$TS"
  REVIEWER_ID="${REVIEWER_ID:-mobyreviewer}"
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"; git -C "$REPO" branch -D local-review-base >/dev/null 2>&1 || true' EXIT
  say "Bundling $(git -C "$REPO" rev-parse --abbrev-ref HEAD) ($HEAD_DESC) and base $BASE for VM '$VM'"
  git -C "$REPO" branch -f local-review-base "$BASE_SHA" >/dev/null
  git -C "$REPO" bundle create "$tmp/repo.bundle" HEAD local-review-base 2>/dev/null
  limactl shell "$VM" mkdir -p "$WORK"
  limactl copy "$tmp/repo.bundle" "$VM:$WORK/repo.bundle"
  limactl copy "$0" "$VM:$WORK/local-review.sh"
  limactl shell "$VM" bash -c "set -e; cd '$WORK' && git init -q repo && cd repo \
    && git fetch -q ../repo.bundle 'HEAD:refs/heads/review' 'local-review-base:refs/heads/base' \
    && git checkout -q review"
  args=(--base base --pr "$PR" --name "$NAME" --namespace "$NAMESPACE" --kit-version "$KIT_VERSION"
        --reviewer-id "$REVIEWER_ID" --out "$WORK/out")
  [ "$KEEP" = 1 ] && args+=(--keep)
  rc=0
  # Runs interactively so the key prompt works; the key stays in the VM's sbx secret store.
  limactl shell "$VM" bash "$WORK/local-review.sh" "${args[@]}" "$WORK/repo" || rc=$?
  mkdir -p "$OUT"
  for f in review.md verdict.json comment.md agent.log policy-log.json mobile.png desktop.png computed.json; do
    limactl copy "$VM:$WORK/out/$f" "$OUT/$f" 2>/dev/null || echo "not copied back: $f" >&2
  done
  limactl shell "$VM" rm -rf "$WORK"
  echo; echo "Outputs: $OUT"
  exit "$rc"
fi

# ---- local: mirror the review job -----------------------------------------------------------
command -v sbx >/dev/null || die "sbx not found"
command -v jq >/dev/null || die "jq not found"
PROMPT_FILE="$REPO/kits/mobyreviewer/review-prompt.md"
[ -f "$PROMPT_FILE" ] || die "$PROMPT_FILE not found"
[ -f "$REPO/index.html" ] || die "$REPO/index.html not found"
OUT="${OUT:-$REPO/out/local-review-$TS}"
mkdir -p "$OUT"
WL="docker.io/$NAMESPACE/mobyreviewer:$KIT_VERSION"
MX="docker.io/$NAMESPACE/docker-style-guide:$KIT_VERSION"

cleanup() {
  [ "$KEEP" = 1 ] && { echo "--keep: sandbox $NAME and its secrets left in place"; return; }
  say "Removing sandbox $NAME and its scoped secrets"
  sbx rm --force "$NAME" >/dev/null 2>&1 || true
  sbx secret rm github --sandbox "$NAME" >/dev/null 2>&1 || true
  sbx secret rm anthropic --sandbox "$NAME" >/dev/null 2>&1 || true
}

say "Reviewing $HEAD_DESC against $BASE (${BASE_SHA:0:7}) on $(hostname)"

say "Deny-by-default network policy"
policy=$(sbx policy ls)
echo "$policy"
if grep -q 'Managed by' <<<"$policy"; then echo "org-governed: local init skipped"
elif grep -q 'default-deny-all' <<<"$policy"; then echo "already deny-all"
else sbx policy init deny-all; fi

say "Agent credentials, scoped to $NAME only"
KEY="${ANTHROPIC_API_KEY:-}"
if [ -z "$KEY" ]; then read -rsp "Anthropic API key: " KEY; echo; fi
[ -n "$KEY" ] || die "no Anthropic key"
trap cleanup EXIT
sbx secret set anthropic --sandbox "$NAME" -t "$KEY" --force
unset KEY
# The kit requires a github credential; locally there is no GitHub, so it gets a placeholder.
sbx secret set github --sandbox "$NAME" -t local-review-no-github --force

say "Create reviewer sandbox (private clone; this checkout stays read-only to the agent)"
time sbx create --name "$NAME" --skills=off --clone "$WL" --kit "$MX" "$REPO"

say "Prove the blast radius before the agent runs"
sbx policy ls "$NAME" --wide
sbx policy check network --sandbox "$NAME" api.anthropic.com
for host in fonts.googleapis.com registry.npmjs.org; do
  if sbx policy check network --sandbox "$NAME" "$host"; then
    echo "local-review: $host is reachable from the reviewer sandbox" >&2; exit 1
  fi
done

say "Render the site (Chromium, file:// only)"
sbx exec "$NAME" mkdir -p /tmp/reviews
time sbx exec "$NAME" render.sh "$REPO"

say "Run the review"
PROMPT=$(sed "s/{{PR}}/$PR/g; s/{{BASE}}/$BASE_SHA/g" "$PROMPT_FILE")
time sbx exec "$NAME" claude --dangerously-skip-permissions -p "$PROMPT" | tee "$OUT/agent.log"

say "Collect outputs into $OUT"
for f in review.md verdict.json mobile.png desktop.png computed.json; do
  sbx cp "$NAME:/tmp/reviews/$f" "$OUT/$f" 2>/dev/null || echo "missing: $f"
done
sbx policy log "$NAME" --json > "$OUT/policy-log.json" 2>/dev/null || true
sbx policy log "$NAME" || true

# ---- what gate.sh would post (fails closed) ---------------------------------------------------
say "Verdict"
if ! jq -e '.verdict=="pass" or .verdict=="request_changes"' "$OUT/verdict.json" >/dev/null 2>&1; then
  echo "Review could not complete: no valid verdict.json, so this counts as request_changes."
  exit 1
fi
verdict=$(jq -r '.verdict' "$OUT/verdict.json")
jq . "$OUT/verdict.json"
{
  if [ -s "$OUT/review.md" ]; then cat "$OUT/review.md"; else jq -r '.summary' "$OUT/verdict.json"; fi
  echo
  echo "---"
  echo "_Reviewed locally on \`$(hostname)\`${REVIEWER_ID:+ · Docker identity \`$REVIEWER_ID\`} · sandbox \`$NAME\` · skill \`docker-style-guide\` v$(jq -r '.skill_version // "unknown"' "$OUT/verdict.json") · style guide v$(jq -r '.style_guide_version // "unknown"' "$OUT/verdict.json") · $(date -u +%Y-%m-%dT%H:%M:%SZ)_"
  echo "_This agent could read the branch, render it, and write two files. It could not reach package registries or font CDNs, push, approve, or merge._"
} > "$OUT/comment.md"
say "Comment gate.sh would post ($OUT/comment.md)"
cat "$OUT/comment.md"
echo
if [ "$verdict" = "pass" ]; then echo "PASS: the check would be green."; exit 0; fi
echo "REQUEST CHANGES: the check would be red and build skipped."; exit 1
