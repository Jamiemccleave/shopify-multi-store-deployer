#!/bin/bash

set -e

# Display input information
echo
echo "  'Upmerge Action' is using the following input:"
echo "    - from_branch = '$INPUT_FROM_BRANCH'"
echo "    - to_branch = '$INPUT_TO_BRANCH'"
echo "    - user_name = 'GitHub Action : Merge'"
echo "    - user_email = '<>'"
echo "    - push_token = $INPUT_PUSH_TOKEN = ${!INPUT_PUSH_TOKEN}"
echo

# Check if push token is set
if [[ -z "${!INPUT_PUSH_TOKEN}" ]]; then
  echo "Set the ${INPUT_PUSH_TOKEN} env variable."
  exit 1
fi

# Configure Git
git config --global --add safe.directory "$GITHUB_WORKSPACE"
git remote set-url origin https://x-access-token:${!INPUT_PUSH_TOKEN}@github.com/$GITHUB_REPOSITORY.git
git config --global user.name "$INPUT_USER_NAME"
git config --global user.email "$INPUT_USER_EMAIL"

set -o xtrace

# Fetch and checkout from_branch
git fetch origin $INPUT_FROM_BRANCH
git checkout $INPUT_FROM_BRANCH && git pull origin $INPUT_FROM_BRANCH || git checkout -b $INPUT_FROM_BRANCH origin/$INPUT_FROM_BRANCH

# Fetch and checkout to_branch
git fetch origin $INPUT_TO_BRANCH
git checkout $INPUT_TO_BRANCH && git pull origin $INPUT_TO_BRANCH || git checkout -b $INPUT_TO_BRANCH origin/$INPUT_TO_BRANCH

# Get the current commit hash
hash=$(git rev-parse --short HEAD)

# Check if merge is necessary
if git merge-base --is-ancestor $INPUT_FROM_BRANCH $INPUT_TO_BRANCH; then
  echo "No merge is necessary"
  exit 0
fi

set +o xtrace
echo
echo "  'Upmerge Action' is trying to merge the '$INPUT_FROM_BRANCH' branch ($(git log -1 --pretty=%H $INPUT_FROM_BRANCH))"
echo "  into the '$INPUT_TO_BRANCH' branch ($(git log -1 --pretty=%H $INPUT_TO_BRANCH))"
echo
set -o xtrace

# Perform the merge
git merge --no-edit --no-commit --strategy-option theirs --allow-unrelated-histories $INPUT_FROM_BRANCH

# Checkout specific files from the hash
git checkout $hash config/settings_data.json
git checkout $hash templates/\*.liquid
git checkout $hash section/\*.json

echo "Status Check: Post Checkout"
git status

# Check if there are changes to commit
if [[ -z $(git status -s) ]]; then
  echo "tree is clean"
  echo "--- End Script --"
  exit 0
else
  echo "tree is dirty, committing changes"
  git commit -m "GitHub Action: Merge ${from_branch} into ${to_branch}"
  git add config/settings_data.json
  git add templates/\*.liquid
  git add section/\*.json

  echo "Status Check: Post Push "

  # Push the branch
  git push --force origin $INPUT_TO_BRANCH
fi


