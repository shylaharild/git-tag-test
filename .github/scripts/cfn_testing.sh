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
  bandit=0


  while :; do
    case "${1-}" in
      -v | --verbose) set -x ;;
      --dryrun) dryrun=1 ;;
      --bandit) bandit=1;;
      *) break ;;
    esac
    shift
  done

  if [[ $bandit -eq 1 ]]; then
    log "${SCRIPT_NAME}" "INFO" "Bandit Python scanning is enabled..."
  else
    log "${SCRIPT_NAME}" "WARN" "Bandit Python scanning skipped..."
  fi

  return 0
}

# Finish Function
finish() {
  log "${SCRIPT_NAME}" "INFO" "*** SCRIPT FINISH ***"
}

# Change folder or directory
change_directory() {
  local directory="${1:-}"
  cd "${directory}"
}

# Install requirements
install_requirements() {
  sudo apt install gem curl -y
  sudo gem install cfn-nag
  pip install cfn-lint
  if [[ $bandit -eq 1 ]]; then
    log "${SCRIPT_NAME}" "INFO" "Installing Bandit..."
    pip install bandit
  fi
  sudo curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin
}

# Move workload folders
move_folders() {
  mkdir -p workload-artifacts
  mv ./100-manifests workload-artifacts/
  mv ./0-account workload-artifacts/
  mv ./1-infrastructure workload-artifacts/
  mv ./*.json workload-artifacts/
  ls -lR ./workload-artifacts

  log "${SCRIPT_NAME}" "INFO" "changing dicrecoty..."
  change_directory "workload-artifacts"
}

# CFN Lint Return value check
cfn_lint_ret_check() {
  local ret_value="${1:-}"

  case "${ret_value}" in
    0)
      log "${SCRIPT_NAME}" "INFO" "No issue was found"
      ;;
    2)
      die "${SCRIPT_NAME}" "An error: ${ret_value}"
      ;;
    4)
      log "${SCRIPT_NAME}" "WARN" "A warning: ${ret_value}"
      ;;
    6)
      die "${SCRIPT_NAME}" "An error and a warning: ${ret_value}"
      ;;
    8)
      log "${SCRIPT_NAME}" "INFO" "An informational: ${ret_value}"
      ;;
    10)
      die "${SCRIPT_NAME}" "An error and informational: ${ret_value}"
      ;;
    12)
      log "${SCRIPT_NAME}" "WARN" "A warning and informational: ${ret_value}"
      ;;
    14)
      die "${SCRIPT_NAME}" "An error, a warning, and an informational: ${ret_value}"
      ;;
    *)
      log "${SCRIPT_NAME}" "INFO" "Unknown ret value: ${ret_value}"
      ;;
  esac
}

# Main function
main() {
  log "${SCRIPT_NAME}" "INFO" "*** SCRIPT START ***"
  parse_params "$@"

  log "${SCRIPT_NAME}" "INFO" "Installing requirements..."
  install_requirements

  log "${SCRIPT_NAME}" "INFO" "listing the local directory..."
  ls -lath
  move_folders

  log "${SCRIPT_NAME}" "INFO" "running the bandit testing..."
  bandit -r .

  log "${SCRIPT_NAME}" "INFO" "running the grype scanner..."
  /usr/local/bin/grype dir:. --only-fixed --fail-on medium

  local files
  local ret_value
  log "${SCRIPT_NAME}" "INFO" "running the cfn-lint testing..."
  files=$(find . -type f | egrep 'json|yaml|yml|template' | egrep -i 'cloudformation|cf|template.yaml|template.yml|template.json' | egrep -v 'params|manifest|.aws-sam')
  ret_value=0
  cfn-lint -eI $files || ret_value=$?
  cfn_lint_ret_check "${ret_value}"
  log "${SCRIPT_NAME}" "INFO" "running the cfn_nag testing..."
  cfn_nag $files
  log "${SCRIPT_NAME}" "INFO" "baseline cfn testing completed..."
}

main "$@"
