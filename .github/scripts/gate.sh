#!/usr/bin/env bash
# Post the reviewer's output to the PR and gate the pipeline. Fails closed:
# a missing or malformed verdict.json is treated as request_changes.
set -euo pipefail

OUT=out
BODY=body.md
: "${PR:?}" "${PR_AUTHOR:?}" "${RUN_URL:?}" "${SBX_NAME:?}" "${REVIEWER_DOCKER_ID:?}"

if ! jq -e '.verdict=="pass" or .verdict=="request_changes"' "$OUT/verdict.json" >/dev/null 2>&1; then
  {
    echo "**Review could not complete.** The reviewer produced no valid \`verdict.json\`, so this pull request is treated as \`request_changes\`."
    echo
    echo "[Run log]($RUN_URL)"
  } > "$BODY"
  gh pr review "$PR" --request-changes --body-file "$BODY"
  exit 1
fi

verdict=$(jq -r '.verdict' "$OUT/verdict.json")
skill_version=$(jq -r '.skill_version // "unknown"' "$OUT/verdict.json")
guide_version=$(jq -r '.style_guide_version // "unknown"' "$OUT/verdict.json")
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

{
  if [ -s "$OUT/review.md" ]; then cat "$OUT/review.md"; else jq -r '.summary' "$OUT/verdict.json"; fi
  echo
  echo "[Screenshots (mobile.png, desktop.png) are in the run artifact]($RUN_URL)"
  echo
  echo "---"
  echo "_Reviewed by \`github-actions[bot]\` · Docker identity \`$REVIEWER_DOCKER_ID\` · sandbox \`$SBX_NAME\` · skill \`docker-style-guide\` v$skill_version · style guide v$guide_version · PR #$PR opened by @$PR_AUTHOR · $now · [run log and screenshots]($RUN_URL)_"
  echo "_This agent could read the branch, render it, and write two files. It could not reach package registries or font CDNs, push, approve, or merge. Write access to this PR belongs to the pipeline, not the agent._"
} > "$BODY"

if [ "$verdict" = "pass" ]; then
  gh pr review "$PR" --comment --body-file "$BODY"
  exit 0
fi
gh pr review "$PR" --request-changes --body-file "$BODY"
exit 1
