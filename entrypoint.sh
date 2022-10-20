#!/bin/bash

set -e

echo
echo "  'Upmerge Action' is using the following input:"
echo "    - from_branch = '$INPUT_FROM_BRANCH'"
echo "    - to_branch = '$INPUT_TO_BRANCH'"
echo "    - user_name = 'GitHub Action : EN>FR'"
echo "    - user_email = '<>'"
echo "    - push_token = $INPUT_PUSH_TOKEN = ${!INPUT_PUSH_TOKEN}"
echo


if [[ -z "${!INPUT_PUSH_TOKEN}" ]]; then
  echo "Set the ${INPUT_PUSH_TOKEN} env variable."
  exit 1
fi

git config --global --add safe.directory "$GITHUB_WORKSPACE"
git remote set-url origin https://x-access-token:${!INPUT_PUSH_TOKEN}@github.com/$GITHUB_REPOSITORY.git
git config --global user.name "$INPUT_USER_NAME"
git config --global user.email "$INPUT_USER_EMAIL"

set -o xtrace

git fetch origin $INPUT_FROM_BRANCH
(git checkout $INPUT_FROM_BRANCH && git pull origin $INPUT_FROM_BRANCH && git push origin $INPUT_FROM_BRANCH)||git checkout -b $INPUT_FROM_BRANCH origin/$INPUT_FROM_BRANCH

#git log -1

git fetch origin $INPUT_TO_BRANCH
(git checkout $INPUT_TO_BRANCH && git pull origin $INPUT_TO_BRANCH)||git checkout -b $INPUT_TO_BRANCH origin/$INPUT_TO_BRANCH

#git log -1
git rev-parse --short HEAD
hash=$(git rev-parse --short HEAD)

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

# status 
#git status 

# Do the merge
git merge --no-edit --no-commit --strategy-option theirs --allow-unrelated-histories $INPUT_FROM_BRANCH
#git merge -m "GitHub Action: Merge Develop into France" develop

git checkout $hash  config/settings_data.json
git checkout $hash  templates/

if [[ -z $(git status -s) ]]; then
  echo "tree is clean"

else
  echo "tree is dirty, commiting changes"
  
  git commit -am  "GitHub Action: Merge "
  git add config/settings_data.json
  git add templates/
 
fi
  




# Push the branch
git push --force origin $INPUT_TO_BRANCH
