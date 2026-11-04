# Running the demo: a new repo for every run

Every demo run starts from a fresh GitHub repo, cloned from the seed (`jeremyrdavis/faq-site`), and is deleted afterwards. This folder (`presenter/`) is presenter tooling: it is copied into each demo repo with the rest of the seed, but the demo's agents don't use it. Nothing is reset. A run is one command to set up, the five demo beats, and one command to tear down.

| Piece | Where |
|---|---|
| Seed repo | `jeremyrdavis/faq-site` (`main` and tag `unstyled-baseline` = unstyled site plus the current pipeline) |
| Setup / teardown | `presenter/setup-demo-repo.sh`, `presenter/teardown-demo-repo.sh` in a local clone of the seed (called `$S/…` below) |
| Developer (Sandbox #1) | your Mac, your Docker login, `moby-developer` + `docker-style-guide` mixin, direct mode |
| Reviewer (CI) | GitHub Actions on the self-hosted runner `lima-runner` in Lima VM `runner`, Docker identity `mobyreviewer`, `--clone` |
| Images | `docker.io/jeremydavis86783/mobyreviewer:1.0.2`, `docker.io/jeremydavis86783/docker-style-guide:1.0.2` |

## Once per machine

### Prerequisites

- `sbx` ≥ 0.45, `gh`, `git` and `limactl` on the Mac.
- The Lima VM `runner` (Ubuntu 24.04 arm64, nested virtualization, your user in the `kvm` group).
  - `sbx` is installed and signed in as `mobyreviewer`.
  - The GitHub Actions runner is unpacked at `~/actions-runner`. It doesn't need to be registered: setup does that.
- The images above are published.

### `gh` scopes

```bash
gh auth refresh -s workflow,delete_repo        # push .github/workflows; delete demo repos
```

### An environment file, kept outside any repo

`~/demo.env` holds two secrets: the Docker PAT and the Anthropic key.

```bash
export REVIEWER_DOCKER_PAT=...                 # PAT for the mobyreviewer Docker account
export ANTHROPIC_API_KEY=...                   # Console API key (OAuth does not work for third-party kits)
export DEMO_DEST_ROOT=~/Demos        # where clones land: $DEMO_DEST_ROOT/<repo-name>
export DEMO_RUNNER_VM=runner                   # move the VM runner to each new repo
export DEMO_YES=1                              # no confirmation prompts
export S=~/Workspace/mobyreviwer/demo-03/faq-site/presenter   # presenter/ in your clone of the seed
```

### Mac hygiene

`sbx secret ls` must show **no global `github` secret**. Every secret the demo uses is scoped to one sandbox.

## Each run

### 1. Set up (about 1 minute)

```bash
source ~/demo.env
REPO=faq-site-$(date +%m%d%H%M)
$S/setup-demo-repo.sh --dry-run "$REPO"        # read the plan
$S/setup-demo-repo.sh "$REPO"
cd "$DEMO_DEST_ROOT/$REPO"
NEW=jeremyrdavis/$REPO
```

What setup does:

- clones the seed and creates a private repo
- pushes `main` and `unstyled-baseline`
- sets the variables `KIT_NAMESPACE`, `KIT_VERSION` and `REVIEWER_DOCKER_ID`, and the secrets `REVIEWER_DOCKER_PAT` and `ANTHROPIC_API_KEY`
- protects `main` (required check `publish`, 1 review, admins may bypass)
- moves `lima-runner` to the new repo with the `kvm` label

Check the last line of its output:

```
runner: lima-runner online self-hosted,Linux,ARM64,kvm
```

If `kvm` is missing, `review` jobs wait forever. Add it with:

```bash
ID=$(gh api repos/$NEW/actions/runners -q '.runners[] | select(.name=="lima-runner") | .id')
gh api -X POST repos/$NEW/actions/runners/$ID/labels -f 'labels[]=kvm'
```

### 2. Stage

- **Browser tabs:**
  - the unstyled site (`open index.html`)
  - the repo's `kits/` folder
  - Pull requests
  - Actions
- **Terminal:** a large font, in `$DEMO_DEST_ROOT/$REPO`.
- **Recording:** for the fallback capture run, start it now (⌘⇧5).

### 3. The demo (spec §7, about 8 minutes)

**Beat 1 (0:00–1:00): the kits.** Show `kits/` in the browser: three workload YAMLs and one mixin.

> "One style guide, three jobs. The mixin is the shared knowledge; the workloads are the roles."

**Beat 2 (1:00–3:00): the developer opens a PR.**

```bash
sbx secret set anthropic --sandbox dev -t "$ANTHROPIC_API_KEY" --force
sbx secret set github    --sandbox dev -t "$(gh auth token)" --force
sbx run --name dev --skills=off ./kits/moby-developer \
  --kit docker.io/jeremydavis86783/docker-style-guide:1.0.2 . \
  -- "Style the site per the docker-style-guide skill, commit on a new branch, push it, and open a PR."
```

If Claude asks whether to use `ANTHROPIC_API_KEY`, answer **Yes**. In a second terminal:

```bash
gh pr list -R $NEW
```

> Narrate the sandbox, not the CSS. Your token is injected at the boundary and the agent never holds it.

**Beat 3 (3:00–5:30): the reviewer runs in CI.**

```bash
gh run watch -R $NEW                           # or the Actions tab
```

Point out, in the `review` job:

- `sbx login` as `mobyreviewer`
- the policy checks: api.anthropic.com **Allowed**; fonts.googleapis.com and registry.npmjs.org **Denied**
- `sbx create --clone`
- the render step (about 1.5 minutes)
- the review
- `rm`

> "Same style guide, different identity, read-only clone, and no route to a font CDN or a package registry."

**Beat 4 (5:30–7:00): the review on the PR.**

```bash
gh pr view <N> -R $NEW --web
RUN=$(gh run list -R $NEW -w review -L1 --json databaseId -q '.[0].databaseId')
rm -rf /tmp/ci-review && gh run download $RUN -R $NEW -n "review-$RUN" -D /tmp/ci-review
open /tmp/ci-review/{mobile,desktop}.png
```

Show:

- **The comment:** from `github-actions[bot]`, with the footer naming Docker identity `mobyreviewer`, the skill version and the style guide version.
- **The checks:** `review`, `publish` and `build` green on `pass`. On `request_changes`, the check is red and `build` is skipped.

> "Who reviewed, which guide version, on whose PR, and what it couldn't do. The bot can block a merge but can't approve one."

**Beat 5 (7:00–8:00): a person merges.**

```bash
gh pr merge <N> -R $NEW --merge --admin --delete-branch
git pull -q && open index.html                 # now styled
```

GitHub doesn't let a PR's author approve their own PR, so `--admin` is the approval here. Say so, or have a second account approve it.

> "Agents propose, people decide."

### 4. Tear down

```bash
$S/teardown-demo-repo.sh "$REPO"
```

- **What it does:**
  - removes the `dev` sandbox and its scoped secrets
  - deletes the GitHub repo (permanently)
  - deletes the clone, but only if its `origin` is that repo
- **What it leaves:** the runner. The next setup moves it.
- **Options:**
  - `--dry-run` to preview
  - `--keep-repo` to keep the repo on GitHub, for example to look at it later

## If something goes wrong

| Symptom | Cause | Fix |
|---|---|---|
| `review` job sits at "Waiting for a runner" | runner offline or missing `kvm` | Check `gh api repos/$NEW/actions/runners`. In the VM: `cd ~/actions-runner && sudo ./svc.sh status`. Add the label as in step 1. |
| Setup: "no runner at ~/actions-runner" | runner not unpacked in the VM | Download `actions-runner-linux-arm64-<v>.tar.gz` into `~/actions-runner` in the VM and unpack it. |
| Setup: "source has uncommitted changes" | the seed has local edits | Commit or stash them in the seed first. |
| Teardown: "lacks the delete_repo scope" | `gh` token scope | `gh auth refresh -s delete_repo` |
| The developer agent can't authenticate | API key not scoped to `dev`, or expired | `sbx secret ls`, then re-run the `sbx secret set anthropic --sandbox dev …` line. Fallback: `sbx run --name dev --skills=off claude .` (OAuth, no mixin; the guide is at the repo root). |
| The demo stalls for more than 20 seconds | anything | Cut to the fallback recording and narrate. Don't debug live. |

## Fallback without GitHub Actions

`$S/local-review.sh --vm runner .` runs the review job's steps inside the VM as `mobyreviewer` against the committed branch. It prints the verdict and the comment the gate would post, and copies the outputs to `out/local-review-<timestamp>/`. Run it from the demo clone, on the PR branch.

## Phase A sign-off

Phase A is done when two runs in a row go from setup to teardown with nothing needing a fix, and one of them is recorded as the fallback capture. Phase B (the fixer) starts only after that.
