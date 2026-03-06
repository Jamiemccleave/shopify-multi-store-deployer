# Shopify Multi-Store Deployer

A GitHub Action that automates branch merging across Shopify theme repositories — intelligently preserving per-store merchant configuration while keeping code in sync.

## How It Works

Shopify theme repos used across multiple stores share the same Liquid/CSS/JS code but have different JSON configuration files per store (set by merchants through the Theme Editor). This action handles the merge so that:

- **Code changes** (Liquid, CSS, JS, `config/settings_schema.json`) always come from the source branch
- **Merchant config** (`templates/*.json`, `sections/*.json`, `config/settings_data.json`) is always preserved from the store branch

### Shopify File Roles

| File | Owner | Behaviour |
|---|---|---|
| `templates/*.json` | Merchant (Theme Editor) | Always preserved from store branch |
| `sections/*.json` | Merchant (Theme Editor) | Always preserved from store branch |
| `config/settings_data.json` | Merchant (Theme Editor) | Preserved by default; or all `config/` with `local_settings_data: true` |
| `config/settings_schema.json` | Developer | Always updated from source branch |
| `locales/*.json` | Developer (usually) | Updated from source by default; opt-in preserve with `preserve_locales: true` |
| All other files | Developer | Always updated from source branch |

---

## Quickstart

Create `.github/workflows/multi-store-merge.yml` in your Shopify theme repository:

```yml
name: "Multi Store Merge"

on:
  push:
    branches:
      - master
    paths-ignore:
      - 'templates/*.json'
      - 'config/*.json'
      - 'locales/*.json'
      - 'sections/*.json'

jobs:
  deploy-uk:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Merge master into UK store
        uses: jamiemccleave/shopify-multi-store-deployer@v3
        with:
          from_branch: "master"
          to_branch: "stores/uk/master"
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

> **Note:** `fetch-depth: 0` is required so the action can access full branch history.

> **Note:** `paths-ignore` prevents the workflow re-triggering when the action writes JSON config files back to the store branch. Without it you risk an infinite loop if you are using a PAT instead of `GITHUB_TOKEN`.

---

## Staging Branch

The `config_source_branch` input enables a staging branch that mirrors production merchant config while running against new code — a true preview of what production will look like after the deploy.

```
master ──┬──► stores/uk/master   (code from master + JSON from stores/uk/master)
          └──► stores/uk/staging  (code from master + JSON from stores/uk/master)
```

```yml
name: "Multi Store Merge"

on:
  push:
    branches:
      - master
    paths-ignore:
      - 'templates/*.json'
      - 'config/*.json'
      - 'locales/*.json'
      - 'sections/*.json'

jobs:
  deploy-production:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Merge master into UK production
        uses: jamiemccleave/shopify-multi-store-deployer@v3
        with:
          from_branch: "master"
          to_branch: "stores/uk/master"
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  deploy-staging:
    runs-on: ubuntu-latest
    needs: deploy-production
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Merge master into UK staging (config from production)
        uses: jamiemccleave/shopify-multi-store-deployer@v3
        with:
          from_branch: "master"
          to_branch: "stores/uk/staging"
          config_source_branch: "stores/uk/master"
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

---

## Multi-Store Matrix

Deploy to multiple stores in parallel with a single workflow:

```yml
name: "Multi Store Merge"

on:
  push:
    branches:
      - master
    paths-ignore:
      - 'templates/*.json'
      - 'config/*.json'
      - 'locales/*.json'
      - 'sections/*.json'

jobs:
  deploy:
    strategy:
      matrix:
        store: [uk, us, eu, au]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Deploy ${{ matrix.store }}
        uses: jamiemccleave/shopify-multi-store-deployer@v3
        with:
          from_branch: "master"
          to_branch: "stores/${{ matrix.store }}/master"
          push_token: "PUSH_TOKEN"
        env:
          PUSH_TOKEN: ${{ secrets.PUSH_TOKEN }}

  deploy-staging:
    strategy:
      matrix:
        store: [uk, us, eu, au]
    needs: deploy
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Deploy ${{ matrix.store }} staging
        uses: jamiemccleave/shopify-multi-store-deployer@v3
        with:
          from_branch: "master"
          to_branch: "stores/${{ matrix.store }}/staging"
          config_source_branch: "stores/${{ matrix.store }}/master"
          push_token: "PUSH_TOKEN"
        env:
          PUSH_TOKEN: ${{ secrets.PUSH_TOKEN }}
```

---

## Open a PR Instead of Pushing Directly

Set `create_pr: true` to push the merge result to a temporary branch and open a pull request into `to_branch` rather than force-pushing. Useful for teams that require review before store branches are updated.

```yml
- name: Merge master into UK store (via PR)
  uses: jamiemccleave/shopify-multi-store-deployer@v3
  with:
    from_branch: "master"
    to_branch: "stores/uk/master"
    create_pr: "true"
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

The PR branch is named `auto-merge/{from}-into-{to}-{timestamp}` and the PR URL is printed in the step log and job summary.

> **Note:** The token must have `pull-requests: write` permission to create PRs. `GITHUB_TOKEN` has this by default; if using a PAT ensure it is granted.

---

## Parameters

### `from_branch`
Branch to merge code from. Default: `"master"`

### `to_branch`
Branch to merge into. Recommended convention: `"stores/{store-name}/{env}"` (e.g. `stores/uk/master`). Default: `"develop"`

### `config_source_branch`
Branch to pull Shopify JSON config files from. Defaults to `to_branch` (standard behaviour). Set to a production branch when deploying to staging so staging uses production merchant config.

### `create_pr`
If `true`, pushes the merge result to a temporary `auto-merge/*` branch and opens a pull request into `to_branch` instead of pushing directly. Default: `"false"`

### `local_settings_data`
If `true`, preserves all `config/*.json` files from the store branch. If `false` (default), only `config/settings_data.json` is preserved.

### `preserve_locales`
If `true`, preserves `locales/*.json` from the store branch. Default `false` — locales are typically developer-owned translation files and should update from the source branch. Set to `true` only if your store has custom translations.

### `user_name`
Git commit author name. Default: `"GitHub Action : Multi Store Merge Bot"`

### `user_email`
Git commit author email. Default: `"actions@github.com"`

### `push_token`
Name of the environment variable holding the push token. Default: `"GITHUB_TOKEN"`. Use a custom PAT when pushing to protected branches:

```yml
with:
  push_token: "PUSH_TOKEN"
env:
  GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  PUSH_TOKEN: ${{ secrets.PUSH_TOKEN }}
```

---

## Branch Naming Convention

The recommended branch structure for multi-store repos:

```
master                        ← shared source of truth (all code changes go here)
stores/uk/master              ← UK production store
stores/uk/staging             ← UK staging (code from master, config from stores/uk/master)
stores/us/master              ← US production store
stores/us/staging             ← US staging
stores/eu/master              ← EU production store
```

---

## Job Summary

Every run writes a markdown summary to the GitHub Actions job summary page (visible under the run's "Summary" tab), including: merge status, branches, commit hash, files changed, and which files were preserved from which branch.

---

## Behaviour

- If `from_branch` is already an ancestor of `to_branch`, the action exits cleanly with no changes.
- Merge conflicts are auto-resolved in favour of `from_branch` (`--strategy-option theirs`), then the specified Shopify config files are restored from the config source.
- Push uses `--force-with-lease` to prevent overwriting concurrent changes.
- When `create_pr: true`, a temporary branch is pushed and a PR is opened via the GitHub API. The action fails if the API call does not return `201`.
