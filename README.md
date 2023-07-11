# Multi Store Merge GitHub Action for Shopify

This GitHub action is designed to automate the process of merging changes between branches in Shopify repositories. It handles specific file checkout and commit operations, focusing on the unique structure of Shopify themes and their configuration files.

The action works based on the following rules:
- If a merge is unnecessary (the 'from' branch is already an ancestor of the 'to' branch), the action performs no action.
- If the merge fails due to conflicts, the action will fail, and the repository maintainer is required to perform the merge manually.

## Installation

To use this action, create the `.github/workflows/multi-store-merge.yml` file in your Shopify repository with the following content:

```yml
name: "Multi Store Merge"

on:
  push:

jobs:
  merge:
    runs-on: ubuntu-latest


    steps:
      - name: Checkout
        uses: actions/checkout@v2

      - name: Shopify Multi Store Deployer
        uses: jamiemccleave/shopify-multi-store-deployer@v2.0
        with:
          from_branch: "master"
          to_branch: "stores/store-name/master-region"
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

**Note:** Replace `from-branch-name`, `to-branch-name`, `bot@email.com`, and `your-repo` with the corresponding values for your scenario. Also, replace `PUSH_TOKEN` with the name of the secret containing the token for push operations.

## Parameters

### `from_branch`

The name of the branch from which changes will be merged (default `master`).

### `to_branch`

The name of the branch into which changes will be merged (default `develop`).

### `user_name`

The user name to be used for git commits (default `GitHub Action : Multi Store Merge Bot`).

### `user_email`

The user email to be used for git commits (default `actions@github.com`).

### `push_token`

The name of the environment variable containing the token to use for push operations (default `GITHUB_TOKEN`). This is particularly useful when pushing changes onto protected branches. To avoid exposing sensitive information in the logs, it's strongly recommended to store this token value in a secret. The `GITHUB_TOKEN` is still required for making API calls.

```yml
with:
  push_token: "YOUR_PUSH_TOKEN"
env:
  GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  YOUR_PUSH_TOKEN: ${{ secrets.YOUR_PUSH_TOKEN }}
```

### `local_settings_data`

A boolean parameter that dictates how `config/*.json` files are handled in Shopify themes. If set to `true`, all files in the `config` directory are checked out and added to the commit. If set to `false`, only the `config/settings_data.json` file is handled (default `false`). 

```yml
with:
  local_settings_data: true
```

**Note:** Replace `YOUR_PUSH_TOKEN` with the name of your specific secret for the push token.

## Workflow

The action operates by merging changes from the specified 'from' branch into the 'to' branch. During the merge process, specific files related to Shopify theme configurations (e.g., template JSON files, section JSON files, locale JSON files, and settings_data.json) are selectively checked out and added to the commit, providing a granular control over the merge operation.
```
