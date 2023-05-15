#!/usr/bin/env bash

set -e

# Display input information
echo
echo "  'Multi Store Merge Bot' is using the following input:"
echo "    - from_branch = '$INPUT_FROM_BRANCH'"
echo "    - to_branch = '$INPUT_TO_BRANCH'"
echo "    - user_name = 'GitHub Action : Multi Store Merge Bot'"
echo "    - user_email = '<>'"
echo "    - push_token = $INPUT_PUSH_TOKEN = ${!INPUT_PUSH_TOKEN}"
echo

# Store input branch names as lowercase variables
input_from_branch="$INPUT_FROM_BRANCH"
input_to_branch="$INPUT_TO_BRANCH"

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
git fetch origin ${input_from_branch}
git checkout ${input_from_branch} && git pull origin ${input_from_branch} || git checkout -b ${input_from_branch} origin/${input_from_branch}

# Fetch and checkout to_branch
git fetch origin ${input_to_branch}
git checkout ${input_to_branch} && git pull origin ${input_to_branch} || git checkout -b ${input_to_branch} origin/${input_to_branch}

# Get the current commit hash
commit_hash=$(git rev-parse --short HEAD)

# Check if merge is necessary
if git merge-base --is-ancestor ${input_from_branch} ${input_to_branch}; then
  echo "No merge is necessary"
  exit 0
fi

set +o xtrace
echo
echo "  'Multi Store Merge Action' is trying to merge the '${input_from_branch}' branch ($(git log -1 --pretty=%H ${input_from_branch}))"
echo "  into the '${input_to_branch}' branch ($(git log -1 --pretty=%H ${input_to_branch}))"
echo
set -o xtrace

# Perform the merge
git merge --no-edit --no-commit --strategy-option theirs --allow-unrelated-histories ${input_from_branch}

# Checkout specific files from the commit_hash, ignoring errors
git checkout ${commit_hash} config/\*.json 2>/dev/null || true
git checkout ${commit_hash} templates/\*.json 2>/dev/null || true
git checkout ${commit_hash} sections/\*.json 2>/dev/null || true
git checkout ${commit_hash} locales/\*.json 2>/dev/null || true

echo "Status Check: Post Checkout"
git status

# Check if there are changes to commit
if [[ -z $(git status -s) ]]; then
  echo "tree is clean"
  echo "--- End Script --"
  exit 0
else
  echo "tree is dirty, committing changes"
  
  # Add modified files, ignoring errors
  git add config/\*.json 2>/dev/null || true
  git add templates/\*.json 2>/dev/null || true
  git add sections/\*.json 2>/dev/null || true
  git add locales/\*.json 2>/dev/null || true
  
  # Commit the changes with the correct branch names
  git commit -m "GitHub Action: Merge ${input_from_branch} into ${input_to_branch}"

  echo "Status Check: Post Push "

  # Push the branch
  git push --force origin ${input_to_branch}
fi


