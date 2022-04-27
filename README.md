# Upmerge GitHub Action

This action is heavily inspired by [robotology/gh-action-nigthly-merge](https://github.com/robotology/gh-action-nightly-merge).

Automatically merge one branch into another.

If the merge is not necessary, the action will do nothing.
If the merge fails due to conflicts, the action will fail, and the repository
maintainer should perform the merge manually.

## Installation

To enable the action simply create the `.github/workflows/upmerge.yml`
file with the following content:

```yml
name: 'Up merge'

on:
  push:

jobs:
  nightly-merge:

    runs-on: ubuntu-latest

    steps:
    - name: Checkout
      uses: actions/checkout@v2

    - name: Up Merge
      uses: bambamboole/gha-upmerge@master
      with:
        stable_branch: 'master'
        development_branch: 'develop'
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## Parameters

### `from_branch`

The name of the from branch (default `master`).

### `to_branch`

The name of the to branch (default `develop`).

### `user_name`

User name for git commits (default `GitHub Upmerge Action`).

### `user_email`

User email for git commits (default `actions@github.com`).

### `push_token`

Environment variable containing the token to use for push (default
`GITHUB_TOKEN`).
Useful for pushing on protected branches.
Using a secret to store this variable value is strongly recommended, since this
value will be printed in the logs.
The `GITHUB_TOKEN` is still used for API calls, therefore both token should be
available.

```yml
      with:
        push_token: 'FOO_TOKEN'
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        FOO_TOKEN: ${{ secrets.FOO_TOKEN }}
```
