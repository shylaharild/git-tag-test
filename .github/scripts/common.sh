#!/bin/bash
#-----------------------
# Common Bash Functions
#-----------------------

# Log information, warn or error message
# Log Types are INFO, WARN and ERROR
log() {
  local script_name="${1:-}"
  local log_type="${2:-}"
  local message="${3:-}"
  echo "[Script] [${script_name}] ${log_type}: ${message}"
}

# Die function
die() {
  local script_name="${1:-}"
  local message="${2:-}"
  local exit_code="${3:-}"
  log "${script_name}" "ERROR" "${message}"
  exit $exit_code
}

# Delete a file
delete_file() {
  local file_name="${1:-}"
  if [ -f "${file_name}" ]; then
    rm "${file_name}"
  fi
}
