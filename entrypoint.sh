#!/bin/bash

set -euo pipefail

# Define variables
from_branch="$INPUT_FROM_BRANCH"
to_branch="$INPUT_TO_BRANCH"
push_token="${!INPUT_PUSH_TOKEN}"
user_name="GitHub Action : Merge"
user_email="<>"
unique_data=(config/settings_data.json templates/) # Add any other unique files or directories as needed

# Check if push token is set
if [[ -z "${push_token}" ]]; then
  echo "Please set the $INPUT_PUSH_TOKEN environment variable."
  exit 1
fi

# Set git config
git config --global --add safe.directory "${GITHUB_WORKSPACE}"
git config --global user.name "${user_name}"
git config --global user.email "${user_email}"
git remote set-url origin "https://x-access-token:${push_token}@github.com/${GITHUB_REPOSITORY}"

# Fetch and checkout from/to branches
git fetch origin "${from_branch}"
git checkout -b "${from_branch}" "origin/${from_branch}"
git fetch origin "${to_branch}"
git checkout -b "${to_branch}" "origin/${to_branch}"

# Check if merge is needed
if git merge-base --is-ancestor "${from_branch}" "${to_branch}"; then
  echo "No merge is necessary"
  exit 0
fi

# Merge from_branch into to_branch
git merge --no-edit --no-commit --strategy-option theirs --allow-unrelated-histories "${from_branch}"
for i in "${unique_data[@]}"; do
  git checkout HEAD -- "${i}" # Restore unique files
done

# Check if changes were made
if [[ -z $(git status -s) ]]; then
  echo "Tree is clean"
else
  echo "Tree is dirty, committing changes"
  git add "${unique_data[@]}"
  git commit -m "GitHub Action: Merge ${from_branch} into ${to_branch}"
  git push --force origin "${to_branch}"
fi
