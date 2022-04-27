#!/bin/bash

set -e

echo
echo "  'Upmerge Action' is using the following input:"
echo "    - from_branch = '$INPUT_FROM_BRANCH'"
echo "    - to_branch = '$INPUT_TO_BRANCH'"
echo "    - user_name = $INPUT_USER_NAME"
echo "    - user_email = $INPUT_USER_EMAIL"
echo "    - push_token = $INPUT_PUSH_TOKEN = ${!INPUT_PUSH_TOKEN}"
echo


if [[ -z "${!INPUT_PUSH_TOKEN}" ]]; then
  echo "Set the ${INPUT_PUSH_TOKEN} env variable."
  exit 1
fi

git remote set-url origin https://x-access-token:${!INPUT_PUSH_TOKEN}@github.com/$GITHUB_REPOSITORY.git
git config --global user.name "$INPUT_USER_NAME"
git config --global user.email "$INPUT_USER_EMAIL"

set -o xtrace

git fetch origin $INPUT_FROM_BRANCH
(git checkout $INPUT_FROM_BRANCH && git pull)||git checkout -b $INPUT_FROM_BRANCH origin/$INPUT_FROM_BRANCH

git fetch origin $INPUT_TO_BRANCH
(git checkout $INPUT_TO_BRANCH && git pull)||git checkout -b $INPUT_TO_BRANCH origin/$INPUT_TO_BRANCH

if git merge-base --is-ancestor $INPUT_FROM_BRANCH $INPUT_TO_BRANCH; then
  echo "No merge is necessary"
  exit 0
fi;

set +o xtrace
echo
echo "  'Upmerge Action' is trying to merge the '$INPUT_FROM_BRANCH' branch ($(git log -1 --pretty=%H $INPUT_FROM_BRANCH))"
echo "  into the '$INPUT_TO_BRANCH' branch ($(git log -1 --pretty=%H $INPUT_TO_BRANCH))"
echo
set -o xtrace

# Do the merge
git merge --no-ff --no-edit $INPUT_FROM_BRANCH

# Push the branch
git push --force origin $INPUT_TO_BRANCH
