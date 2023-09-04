#!/bin/bash
set -euo pipefail
IFS=$'\n\t'
# shellcheck disable=SC2026
trap 'finish' EXIT

# What is my name?
declare SCRIPT_NAME
declare SCRIPT_DIR
SCRIPT_NAME=$(basename -- "$0" .sh)
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
readonly SCRIPT_NAME
readonly SCRIPT_DIR

# Grab common functions
# shellcheck source=./common.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

# Parse Parameters
parse_params() {
  # default values of variables set from params
  dryrun=0
  github_labels=""
  github_user=""
  github_token=""

  while :; do
    case "${1-}" in
      -v | --verbose) set -x ;;
      --dryrun) dryrun=1 ;;
      -l | --github_labels)
        github_labels="${2-}"
        shift
        ;;
      -u | --github_user)
        github_user="${2-}"
        shift
        ;;
      -x | --github_token)
        github_token="${2-}"
        shift
        ;;
      -?*)
        die "${SCRIPT_NAME}" "Unknown option: $1" "128"
        ;;
      *) break ;;
    esac
    shift
  done

  if [[ "${github_user}" == "" ]]; then
    die "${SCRIPT_NAME}" \
      "you must specify the github_user (using -u or --github_user <username>)" 1
  fi

  if [[ "${github_token}" == "" ]]; then
    die "${SCRIPT_NAME}" \
      "you must specify the github_token (using -x or --github_token <{ github.token }>)" 1
  fi

  return 0
}

# Finish Function
finish() {
  log "${SCRIPT_NAME}" "INFO" "*** SCRIPT FINISH ***"
}

get_current_version() {
  local current_version
  current_version=$(git describe --tags --abbrev=0)
  
  echo "${current_version}"
}

get_increment_type() {
  local pr_labels_json="${1:-}"
  local label_names
  label_names=$(echo "${pr_labels_json}" | jq -r ".[] | .name")
  local increment_type=""

  # shellcheck disable=SC2068
  for label in ${label_names[@]}; do
    case "${label}" in
      bump:major)
        increment_type="major"
        break
        ;;
      bump:minor)
        increment_type="minor"
        break
        ;;
      bump:patch)
        increment_type="patch"
        break
        ;;
      *)
        increment_type="minor"
        break
        ;;
    esac
  done

  echo "${increment_type}"
}

increment_version() {
  local current_version="${1:-}"
  local increment_type="${2:-}"
  local major_version
  local minor_version
  local patch_version
  major_version=$(cut -d '.' -f1 <<<"${current_version}")
  minor_version=$(cut -d '.' -f2 <<<"${current_version}")
  patch_version=$(cut -d '.' -f3 <<<"${current_version}")

  case "${increment_type}" in
    major)
      ((major_version++))
      minor_version=0
      patch_version=0
      ;;
    minor)
      ((minor_version++))
      patch_version=0
      ;;
    patch)
      ((patch_version++))
      ;;
    *)
      ((minor_version++))
      ;;
  esac
  echo "${major_version}.${minor_version}.${patch_version}"
}

bump_version() {
  local incremented_version="${1:-}"
  local increment_type="${2:-}"
  local github_user="${3:-}"

  git config user.name "${github_user}"
  git config user.email "${github_user}@users.noreply.github.com"

  git tag -a "${incremented_version}" -m "Version v${incremented_version}"
  git push origin "${incremented_version}"
}

post_message() {
  local current_version="${1:-}"
  local incremented_version="${2:-}"
  local github_user="${3:-}"
  local github_token="${4:-}"
  local message
  local body
  local endpoint
  
  endpoint="${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments"
  message="[Bumped!](${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}) Version [v${current_version}](${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/releases/tag/${current_version}) -> [v${incremented_version}](${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/releases/tag/${incremented_version})"
  body="$(echo ${message} | jq -ncR '{body: input}')"

  curl -H "Authorization: token ${github_token}" -d "${body}" "${endpoint}"
}

main() {
  log "${SCRIPT_NAME}" "INFO" "*** SCRIPT START ***"
  parse_params "$@"

  local current_version
  current_version=$(get_current_version)
  log "${SCRIPT_NAME}" "INFO" "current version: ${current_version}"

  local increment_type
  increment_type=$(get_increment_type "${github_labels}")
  log "${SCRIPT_NAME}" "INFO" "increment type: ${increment_type}"

  local incremented_version
  incremented_version=$(increment_version "${current_version}" "${increment_type}")
  log "${SCRIPT_NAME}" "INFO" "INCREMENTED VERSION: ${incremented_version}"

  if [[ $dryrun -eq 0 ]]; then
    log "${SCRIPT_NAME}" "INFO" "bumping the version..."
    bump_version "${incremented_version}" "${increment_type}" "${github_user}"
    log "${SCRIPT_NAME}" "INFO" "posting message on the PR..."
    post_message "${current_version}" "${incremented_version}" "${github_user}" "${github_token}"
  else
    log "${SCRIPT_NAME}" "WARN" "not bumping the version (dryrun)"
    log "${SCRIPT_NAME}" "WARN" "current version is ${current_Version}"
    log "${SCRIPT_NAME}" "WARN" "incremented version is ${incremented_version}"
    log "${SCRIPT_NAME}" "WARN" "PR number is ${PR_NUMBER}"
    log "${SCRIPT_NAME}" "WARN" "PR title is ${PR_TITLE}"
  fi
}

main "$@"
