#!/usr/bin/env bash
set -e

# ─────────────────────────────────────────────────────────
# Inputs
# ─────────────────────────────────────────────────────────
input_from_branch="${INPUT_FROM_BRANCH:-master}"
input_to_branch="${INPUT_TO_BRANCH:-develop}"
input_user_name="${INPUT_USER_NAME:-GitHub Action : Multi Store Merge Bot}"
input_user_email="${INPUT_USER_EMAIL:-actions@github.com}"
input_push_token_var="${INPUT_PUSH_TOKEN:-GITHUB_TOKEN}"
input_local_settings_data="${INPUT_LOCAL_SETTINGS_DATA:-false}"
input_preserve_locales="${INPUT_PRESERVE_LOCALES:-false}"
input_config_source_branch="${INPUT_CONFIG_SOURCE_BRANCH:-}"

# Config source defaults to to_branch if not specified (preserves existing behaviour)
if [[ -z "${input_config_source_branch}" ]]; then
  input_config_source_branch="${input_to_branch}"
fi

# ─────────────────────────────────────────────────────────
# Step summary helpers
# ─────────────────────────────────────────────────────────
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
run_timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo 'unknown')"

summary_header() {
  {
    echo "## Shopify Multi-Store Merge — ${run_timestamp}"
    echo ""
    echo "| Field | Value |"
    echo "|---|---|"
    echo "| From branch | \`${input_from_branch}\` |"
    echo "| To branch | \`${input_to_branch}\` |"
    echo "| Config source | \`${input_config_source_branch}\` |"
    echo "| Preserve locales | \`${input_preserve_locales}\` |"
    echo "| Local settings data | \`${input_local_settings_data}\` |"
  } >> "${SUMMARY}"
}

summary_result() {
  local status="$1" commit="$2" files="$3"
  {
    echo "| Merge status | ${status} |"
    if [[ -n "${commit}" ]]; then echo "| Commit | \`${commit}\` |"; fi
    if [[ -n "${files}" ]];  then echo "| Files changed | ${files} |"; fi
    echo ""
  } >> "${SUMMARY}"
}

summary_preserved() {
  local config_src="$1"
  {
    echo "### Preserved files (from \`${config_src}\`)"
    echo "- \`templates/*.json\` — merchant section layouts"
    echo "- \`sections/*.json\` — section app-block state"
    if [[ "${input_local_settings_data}" == "true" ]]; then
      echo "- \`config/*.json\` — all theme config (including settings_data.json)"
    else
      echo "- \`config/settings_data.json\` — theme editor settings"
    fi
    if [[ "${input_preserve_locales}" == "true" ]]; then echo "- \`locales/*.json\` — store translations (opt-in)"; fi
  } >> "${SUMMARY}"
}

# ─────────────────────────────────────────────────────────
# Startup log
# ─────────────────────────────────────────────────────────
echo ""
echo "::group::Multi Store Merge Bot — configuration"
echo "  from_branch          : ${input_from_branch}"
echo "  to_branch            : ${input_to_branch}"
echo "  config_source_branch : ${input_config_source_branch}"
echo "  user_name            : ${input_user_name}"
echo "  user_email           : ${input_user_email}"
echo "  push_token           : ${input_push_token_var} (value hidden)"
echo "  local_settings_data  : ${input_local_settings_data}"
echo "  preserve_locales     : ${input_preserve_locales}"
echo "::endgroup::"
echo ""

summary_header

# ─────────────────────────────────────────────────────────
# Validate push token
# ─────────────────────────────────────────────────────────
if [[ -z "${!input_push_token_var}" ]]; then
  echo "::error::Push token env var '${input_push_token_var}' is not set. Aborting."
  summary_result "❌ Failed — push token '\`${input_push_token_var}\`' not set" "" ""
  exit 1
fi

# ─────────────────────────────────────────────────────────
# Branch naming convention check
# ─────────────────────────────────────────────────────────
if [[ ! "${input_to_branch}" =~ ^stores/[^/]+/.+$ ]]; then
  echo "::warning::to_branch '${input_to_branch}' does not follow the recommended 'stores/{store-name}/{env}' convention."
fi

# ─────────────────────────────────────────────────────────
# Git configuration
# ─────────────────────────────────────────────────────────
echo "::group::Git configuration"
git config --global --add safe.directory "${GITHUB_WORKSPACE}"
git remote set-url origin "https://x-access-token:${!input_push_token_var}@github.com/${GITHUB_REPOSITORY}.git"
git config --global user.name "${input_user_name}"
git config --global user.email "${input_user_email}"
git lfs install 2>/dev/null || true
echo "  remote URL set (token hidden)"
echo "  user.name  : ${input_user_name}"
echo "  user.email : ${input_user_email}"
echo "::endgroup::"

# ─────────────────────────────────────────────────────────
# Branch setup
# ─────────────────────────────────────────────────────────
echo "::group::Branch setup"

git fetch origin "${input_from_branch}"
git checkout "${input_from_branch}" 2>/dev/null && git pull origin "${input_from_branch}" \
  || git checkout -b "${input_from_branch}" "origin/${input_from_branch}"
echo "  Fetched and checked out: ${input_from_branch}"

git fetch origin "${input_to_branch}"
git checkout "${input_to_branch}" 2>/dev/null && git pull origin "${input_to_branch}" \
  || git checkout -b "${input_to_branch}" "origin/${input_to_branch}"
echo "  Fetched and checked out: ${input_to_branch}"

# Snapshot the to_branch tip before merge (used to restore config files)
to_branch_commit=$(git rev-parse HEAD)
echo "  Pre-merge commit (${input_to_branch}): ${to_branch_commit}"

# Fetch config source branch if it differs from to_branch
if [[ "${input_config_source_branch}" != "${input_to_branch}" ]]; then
  git fetch origin "${input_config_source_branch}"
  echo "  Fetched config source: ${input_config_source_branch}"
fi

# Resolve the commit to pull JSON config from
config_commit=$(git rev-parse "origin/${input_config_source_branch}")
echo "  Config source commit: ${config_commit}"

echo "::endgroup::"

# ─────────────────────────────────────────────────────────
# Merge check — skip if already up to date
# ─────────────────────────────────────────────────────────
if git merge-base --is-ancestor "${input_from_branch}" "${input_to_branch}"; then
  echo "::notice::${input_from_branch} is already an ancestor of ${input_to_branch} — no merge needed."
  summary_result "⏭️ Skipped — already up to date" "" ""
  exit 0
fi

echo ""
echo "  Merging '${input_from_branch}' ($(git log -1 --pretty=%H "${input_from_branch}"))"
echo "  into    '${input_to_branch}' ($(git log -1 --pretty=%H "${input_to_branch}"))"
echo ""

# ─────────────────────────────────────────────────────────
# Merge (staged, not committed — conflicts auto-resolved to theirs)
# ─────────────────────────────────────────────────────────
echo "::group::Merge"
git merge --no-edit --no-commit --strategy-option theirs --allow-unrelated-histories "${input_from_branch}"
echo "  Merge staged (conflicts resolved to ${input_from_branch})"
echo "::endgroup::"

# ─────────────────────────────────────────────────────────
# Restore per-store Shopify config files from config_source_branch
# ─────────────────────────────────────────────────────────
echo "::group::Restoring Shopify config from '${input_config_source_branch}'"

restore_json() {
  local label="$1" dir="$2"
  local -a files
  mapfile -t files < <(git ls-tree -r --name-only "${config_commit}" -- "${dir}" 2>/dev/null | grep '\.json$')
  if [[ ${#files[@]} -gt 0 ]]; then
    git checkout "${config_commit}" -- "${files[@]}"
    echo "  Restored: ${label} (${#files[@]} files)"
  else
    echo "  Skipped:  ${label} (none found in ${input_config_source_branch})"
  fi
}

restore_json "templates/*.json" "templates/"
restore_json "sections/*.json"  "sections/"

if [[ "${input_local_settings_data}" == "true" ]]; then
  restore_json "config/*.json" "config/"
else
  if git checkout "${config_commit}" -- "config/settings_data.json" 2>/dev/null; then
    echo "  Restored: config/settings_data.json"
  else
    echo "  Skipped:  config/settings_data.json (not found in ${input_config_source_branch})"
  fi
fi

if [[ "${input_preserve_locales}" == "true" ]]; then
  restore_json "locales/*.json" "locales/"
else
  echo "  Skipped:  locales/ (preserve_locales=false — locales update from ${input_from_branch})"
fi

echo "::endgroup::"

# ─────────────────────────────────────────────────────────
# Commit and push
# ─────────────────────────────────────────────────────────
echo "::group::Commit and push"

if [[ -z $(git status -s) ]]; then
  echo "  No changes to commit — working tree is clean."
  echo "::endgroup::"
  summary_result "⏭️ Skipped — no changes after config restore" "" ""
  exit 0
fi

git add -A

files_changed=$(git diff --cached --name-only | wc -l | tr -d ' ')
echo "  Files staged: ${files_changed}"

commit_msg="GitHub Action: Merge ${input_from_branch} into ${input_to_branch} [config from ${input_config_source_branch}]"
git commit -m "${commit_msg}"
new_commit=$(git rev-parse --short HEAD)
echo "  Committed: ${new_commit}"

git push --force-with-lease origin "${input_to_branch}"
echo "  Pushed to origin/${input_to_branch} (force-with-lease)"

echo "::endgroup::"

summary_result "✅ Merged successfully" "${new_commit}" "${files_changed}"
summary_preserved "${input_config_source_branch}"
