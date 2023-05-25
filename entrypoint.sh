#!/usr/bin/env bash

# If any command in the script fails (returns non-zero exit status), the script will terminate immediately
set -e

# Displaying input information
echo
echo "  'Multi Store Merge Bot' is using the following input:"
echo "    - from_branch = '$INPUT_FROM_BRANCH'"
echo "    - to_branch = '$INPUT_TO_BRANCH'"
echo "    - user_name = 'GitHub Action : Multi Store Merge Bot'"
echo "    - user_email = '<>'"
echo "    - push_token = $INPUT_PUSH_TOKEN = ${!INPUT_PUSH_TOKEN}"
echo

# Setting the input branches and settings data as variables for later use
input_from_branch="$INPUT_FROM_BRANCH"
input_to_branch="$INPUT_TO_BRANCH"

# Check if the push token environment variable is set; if not, terminate the script
if [[ -z "${!INPUT_PUSH_TOKEN}" ]]; then
  echo "Set the ${INPUT_PUSH_TOKEN} env variable."
  exit 1
fi

# Configure Git's global settings for the current user's name and email
git config --global --add safe.directory "$GITHUB_WORKSPACE"
git remote set-url origin https://x-access-token:${!INPUT_PUSH_TOKEN}@github.com/$GITHUB_REPOSITORY.git
git config --global user.name "$INPUT_USER_NAME"
git config --global user.email "$INPUT_USER_EMAIL"

# Enable command tracing - each command is printed before it's executed
set -o xtrace

# Fetch and checkout the 'from' branch
git fetch origin ${input_from_branch}
git checkout ${input_from_branch} && git pull origin ${input_from_branch} || git checkout -b ${input_from_branch} origin/${input_from_branch}

# Fetch and checkout the 'to' branch
git fetch origin ${input_to_branch}
git checkout ${input_to_branch} && git pull origin ${input_to_branch} || git checkout -b ${input_to_branch} origin/${input_to_branch}

# Get the current commit hash
commit_hash=$(git rev-parse --short HEAD)

# Check if merging is necessary, if not then terminate the script
if git merge-base --is-ancestor ${input_from_branch} ${input_to_branch}; then
  echo "No merge is necessary"
  exit 0
fi

# Disable command tracing
set +o xtrace
echo
echo "  'Multi Store Merge Action' is trying to merge the '${input_from_branch}' branch ($(git log -1 --pretty=%H ${input_from_branch}))"
echo "  into the '${input_to_branch}' branch ($(git log -1 --pretty=%H ${input_to_branch}))"
echo

# Enable command tracing again
set -o xtrace

# Perform the merge operation without committing and favoring 'theirs' for conflicts
git merge --no-edit --no-commit --strategy-option theirs --allow-unrelated-histories ${input_from_branch}

# Checkout specific files from the current commit, ignoring errors
git checkout ${commit_hash} templates/\*.json 2>/dev/null || true
git checkout ${commit_hash} sections/\*.json 2>/dev/null || true
git checkout ${commit_hash} locales/\*.json 2>/dev/null || true
git checkout ${commit_hash} config/settings_data.json 2>/dev/null || true

# Display the status after checkout
echo "Status Check: Post Checkout"
git status

# Check if there are any changes to commit
if [[ -z $(git status -s) ]]; then
  echo "No changes to commit, the working tree is clean"
  echo "--- End Script --"
  exit 0
else
  echo "Changes detected, committing changes"

  # Add modified files to the git staging area, ignoring errors
  git add templates/\*.json 2>/dev/null || true
  git add sections/\*.json 2>/dev/null || true
  git add locales/\*.json 2>/dev/null || true
  git add config/settings_data.json 2>/dev/null || true

  # Commit the changes with a message indicating the branches involved in the merge
  git commit -m "GitHub Action: Merge ${input_from_branch} into ${input_to_branch}"

  # Display the status after pushing changes
  echo "Status Check: Post Push "

  # Push the changes to the 'to' branch on the origin remote
  git push --force origin ${input_to_branch}
fi
