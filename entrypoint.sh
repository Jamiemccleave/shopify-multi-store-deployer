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
input_create_pr="${INPUT_CREATE_PR:-false}"

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
# PolinRider supply-chain scan
# Scans all staged files before committing. Aborts if any
# Operation PolinRider IOCs are detected in the merged content.
# ─────────────────────────────────────────────────────────
scan_for_polinrider() {
  echo "::group::PolinRider security scan"
  local FAIL=0
  local -a staged
  mapfile -t staged < <(git diff --cached --name-only 2>/dev/null)

  if [[ ${#staged[@]} -eq 0 ]]; then
    echo "  No staged files to scan."
    echo "::endgroup::"
    echo "| Security Scan | ✅ Clean (no staged files) |" >> "${SUMMARY}"
    return 0
  fi

  # 1. Hidden Unicode — zero-width joiners, variation selectors, bidirectional controls
  local UNICODE_PAT
  UNICODE_PAT=$'\xe2\x80\x8b|\xe2\x80\x8c|\xe2\x80\x8d|\xef\xb8\x80|\xe2\x80\xaa|\xe2\x80\xab|\xe2\x80\xac|\xe2\x80\xad|\xe2\x80\xae'
  for file in "${staged[@]}"; do
    case "${file}" in
      *.js|*.ts|*.jsx|*.tsx|*.liquid|*.json|*.css)
        if git show ":${file}" 2>/dev/null | LC_ALL=C grep -Pq "${UNICODE_PAT}"; then
          echo "::error file=${file}::PolinRider: Hidden Unicode detected — possible Glassworm injection"
          FAIL=1
        fi
        ;;
    esac
  done

  # 2. PolinRider fingerprint string
  for file in "${staged[@]}"; do
    if git show ":${file}" 2>/dev/null | grep -qF "global['_V']='8-'"; then
      echo "::error file=${file}::PolinRider: Glassworm fingerprint detected in ${file}"
      FAIL=1
    fi
  done

  # 3. Blockchain C2 endpoints (BeaverTail comms)
  local C2_PAT="trongrid\.io|aptoslabs\.com|bsc-dataseed|fullnode\.mainnet\.aptoslabs"
  for file in "${staged[@]}"; do
    case "${file}" in
      *.js|*.ts|*.jsx|*.tsx|*.json|*.liquid)
        if git show ":${file}" 2>/dev/null | grep -Pq "${C2_PAT}"; then
          echo "::error file=${file}::PolinRider: Blockchain C2 endpoint detected in ${file}"
          FAIL=1
        fi
        ;;
    esac
  done

  # 4. Binary-extension masquerade — skip assets/ (legitimate Shopify fonts live there)
  for file in "${staged[@]}"; do
    case "${file}" in
      *.woff|*.woff2|*.ttf|*.otf|*.eot|*.ico|*.wasm)
        [[ "${file}" == */assets/* ]] && continue
        local MIME
        MIME=$(git show ":${file}" 2>/dev/null | file --mime-type -b - 2>/dev/null || echo "unknown")
        case "${MIME}" in
          text/*|application/javascript|application/x-sh)
            echo "::error file=${file}::PolinRider: Masquerade detected — ${file} contains ${MIME} content"
            FAIL=1
            ;;
        esac
        ;;
    esac
  done

  echo "::endgroup::"

  if [[ "${FAIL}" -eq 1 ]]; then
    echo "::error::PolinRider scan FAILED — merge aborted. Review flagged files before proceeding."
    echo "| Security Scan | ❌ Failed — PolinRider IOCs detected in staged files |" >> "${SUMMARY}"
    return 1
  fi

  echo "  PolinRider scan: clean (${#staged[@]} files checked)"
  echo "| Security Scan | ✅ Clean — ${#staged[@]} files scanned |" >> "${SUMMARY}"
  return 0
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
echo "  create_pr            : ${input_create_pr}"
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
# Commit and push (or open PR)
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

scan_for_polinrider || exit 1

commit_msg="GitHub Action: Merge ${input_from_branch} into ${input_to_branch} [config from ${input_config_source_branch}]"
git commit -m "${commit_msg}"
new_commit=$(git rev-parse --short HEAD)
echo "  Committed: ${new_commit}"

if [[ "${input_create_pr}" == "true" ]]; then
  # Push to a staging branch and open a PR instead of pushing directly
  from_safe=$(echo "${input_from_branch}" | tr '/' '-')
  to_safe=$(echo "${input_to_branch}" | tr '/' '-')
  pr_branch="auto-merge/${from_safe}-into-${to_safe}-$(date +%s)"

  git push origin "HEAD:${pr_branch}"
  echo "  Pushed to origin/${pr_branch}"

  TOKEN="${!input_push_token_var}"
  pr_response=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Authorization: token ${TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/${GITHUB_REPOSITORY}/pulls" \
    -d "{
      \"title\": \"${commit_msg}\",
      \"body\": \"Automated PR created by Multi Store Merge Action.\\nMerging \`${input_from_branch}\` into \`${input_to_branch}\`.\",
      \"head\": \"${pr_branch}\",
      \"base\": \"${input_to_branch}\"
    }")

  pr_http_code=$(echo "${pr_response}" | tail -1)
  pr_body=$(echo "${pr_response}" | head -n -1)

  if [[ "${pr_http_code}" == "201" ]]; then
    pr_url=$(echo "${pr_body}" | grep -o '"html_url":"[^"]*"' | head -1 | cut -d'"' -f4)
    echo "  PR created: ${pr_url}"
    echo "::endgroup::"
    summary_result "✅ PR created" "${new_commit}" "${files_changed}"
    echo "| Pull Request | [${pr_url}](${pr_url}) |" >> "${SUMMARY}"
  else
    echo "::error::Failed to create PR (HTTP ${pr_http_code}). Response: ${pr_body}"
    echo "::endgroup::"
    summary_result "❌ Failed — PR creation returned HTTP ${pr_http_code}" "${new_commit}" "${files_changed}"
    exit 1
  fi
else
  git push origin "${input_to_branch}"
  echo "  Pushed to origin/${input_to_branch}"
  echo "::endgroup::"
  summary_result "✅ Merged successfully" "${new_commit}" "${files_changed}"
fi

summary_preserved "${input_config_source_branch}"
