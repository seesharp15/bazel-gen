#!/usr/bin/env bash
set -euo pipefail

PATH_BLOCK_START="# >>> bazel-gen installer >>>"
PATH_BLOCK_END="# <<< bazel-gen installer <<<"

DEFAULT_INSTALL_BASE="${HOME}/.local/share/bazel-gen"
DEFAULT_BIN_DIR="${HOME}/.local/bin"
DEFAULT_STATE_FILE="${HOME}/.bazel-gen/install-state"
DEFAULT_CONFIG_DIR="${HOME}/.bazel-gen"

INSTALL_BASE_OVERRIDE=""
BIN_DIR_OVERRIDE=""
STATE_FILE="${BAZEL_GEN_STATE_FILE:-${DEFAULT_STATE_FILE}}"
DRY_RUN=0

declare -a RC_FILES=()

auto_detect_rc_files=1

usage() {
  cat <<USAGE
Usage:
  scripts/uninstall.sh [options]

Options:
  --install-base <path>  Install payload directory override.
  --bin-dir <path>       Launcher directory override.
  --state-file <path>    Install state file path (default: ${DEFAULT_STATE_FILE})
  --rc-file <path>       Shell rc file to clean. Can be specified multiple times.
  --no-rc-auto-detect    Do not auto-include detected rc files.
  --dry-run              Print actions without writing files.
  -h, --help             Show this help.

Behavior:
  Uninstall removes the launcher, installed payload, shell PATH block, and ~/.bazel-gen.
USAGE
}

log() {
  printf "%s\n" "$*"
}

die() {
  printf "error: %s\n" "$*" >&2
  exit 1
}

run_cmd() {
  if [ "${DRY_RUN}" -eq 1 ]; then
    printf "[dry-run]"
    printf " %q" "$@"
    printf "\n"
    return 0
  fi
  "$@"
}

expand_home() {
  local path="$1"
  case "${path}" in
    "~")
      printf "%s" "${HOME}"
      ;;
    "~/"*)
      printf "%s/%s" "${HOME}" "${path#~/}"
      ;;
    *)
      printf "%s" "${path}"
      ;;
  esac
}

add_unique_rc_file() {
  local file_path="$1"
  local existing
  for existing in "${RC_FILES[@]-}"; do
    if [ "${existing}" = "${file_path}" ]; then
      return 0
    fi
  done
  RC_FILES+=("${file_path}")
}

detect_rc_files() {
  local shell_name
  shell_name="$(basename "${SHELL:-}")"
  case "${shell_name}" in
    zsh)
      printf "%s\n" "${HOME}/.zshrc"
      printf "%s\n" "${HOME}/.zprofile"
      ;;
    bash)
      printf "%s\n" "${HOME}/.bashrc"
      printf "%s\n" "${HOME}/.bash_profile"
      ;;
  esac
  printf "%s\n" "${HOME}/.profile"
}

strip_path_block() {
  local file_path="$1"
  [ -f "${file_path}" ] || return 0

  local tmp_file
  tmp_file="$(mktemp "${TMPDIR:-/tmp}/bazel-gen-uninstall.XXXXXX")"
  awk -v start="${PATH_BLOCK_START}" -v end="${PATH_BLOCK_END}" '
    $0 == start { in_block = 1; next }
    $0 == end { in_block = 0; next }
    in_block != 1 { print }
  ' "${file_path}" > "${tmp_file}"

  if [ "${DRY_RUN}" -eq 1 ]; then
    log "[dry-run] update ${file_path} (remove bazel-gen PATH block)"
    rm -f "${tmp_file}"
    return 0
  fi

  cat "${tmp_file}" > "${file_path}"
  rm -f "${tmp_file}"
}

remove_file_if_exists() {
  local target="$1"
  if [ -f "${target}" ] || [ -L "${target}" ]; then
    run_cmd rm -f "${target}"
  fi
}

assert_safe_rm_path() {
  local path="$1"
  case "${path}" in
    ""|"/"|"."|".."|"~"|"${HOME}")
      die "Refusing to remove unsafe path: ${path}"
      ;;
  esac
}

remove_dir_if_exists() {
  local target="$1"
  [ -d "${target}" ] || return 0
  assert_safe_rm_path "${target}"
  run_cmd rm -rf "${target}"
}

remove_dir_if_empty() {
  local target="$1"
  [ -d "${target}" ] || return 0
  if [ -z "$(find "${target}" -mindepth 1 -print -quit 2>/dev/null)" ]; then
    run_cmd rmdir "${target}"
  fi
}

load_state_file() {
  [ -f "${STATE_FILE}" ] || return 0
  # shellcheck disable=SC1090
  source "${STATE_FILE}"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --install-base)
      [ "$#" -ge 2 ] || die "Missing value for --install-base"
      INSTALL_BASE_OVERRIDE="$2"
      shift 2
      ;;
    --bin-dir)
      [ "$#" -ge 2 ] || die "Missing value for --bin-dir"
      BIN_DIR_OVERRIDE="$2"
      shift 2
      ;;
    --state-file)
      [ "$#" -ge 2 ] || die "Missing value for --state-file"
      STATE_FILE="$2"
      shift 2
      ;;
    --rc-file)
      [ "$#" -ge 2 ] || die "Missing value for --rc-file"
      add_unique_rc_file "$(expand_home "$2")"
      shift 2
      ;;
    --no-rc-auto-detect)
      auto_detect_rc_files=0
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

STATE_FILE="$(expand_home "${STATE_FILE}")"
load_state_file

INSTALL_BASE="${BAZEL_GEN_STATE_INSTALL_BASE:-${BAZEL_GEN_INSTALL_BASE:-${DEFAULT_INSTALL_BASE}}}"
BIN_DIR="${BAZEL_GEN_STATE_BIN_DIR:-${BAZEL_GEN_BIN_DIR:-${DEFAULT_BIN_DIR}}}"
APP_DIR="${BAZEL_GEN_STATE_APP_DIR:-${INSTALL_BASE}/app}"
LAUNCHER_PATH="${BAZEL_GEN_STATE_LAUNCHER_PATH:-${BIN_DIR}/bazel-gen}"
CONFIG_DIR="${DEFAULT_CONFIG_DIR}"

if [ -n "${INSTALL_BASE_OVERRIDE}" ]; then
  INSTALL_BASE="$(expand_home "${INSTALL_BASE_OVERRIDE}")"
  APP_DIR="${INSTALL_BASE}/app"
fi

if [ -n "${BIN_DIR_OVERRIDE}" ]; then
  BIN_DIR="$(expand_home "${BIN_DIR_OVERRIDE}")"
  LAUNCHER_PATH="${BIN_DIR}/bazel-gen"
fi

if [ -n "${BAZEL_GEN_STATE_RC_FILES:-}" ]; then
  IFS=':' read -r -a state_rc_files <<< "${BAZEL_GEN_STATE_RC_FILES}"
  for rc_path in "${state_rc_files[@]}"; do
    [ -n "${rc_path}" ] || continue
    add_unique_rc_file "${rc_path}"
  done
fi

if [ "${auto_detect_rc_files}" -eq 1 ]; then
  while IFS= read -r rc_path; do
    [ -n "${rc_path}" ] || continue
    add_unique_rc_file "${rc_path}"
  done < <(detect_rc_files)
fi

for rc_file in "${RC_FILES[@]-}"; do
  strip_path_block "${rc_file}"
done

remove_file_if_exists "${LAUNCHER_PATH}"
remove_dir_if_exists "${APP_DIR}"
remove_dir_if_empty "${INSTALL_BASE}"

remove_file_if_exists "${STATE_FILE}"
remove_dir_if_exists "${CONFIG_DIR}"

remove_dir_if_empty "${BIN_DIR}"

if [ "${DRY_RUN}" -eq 1 ]; then
  log "dry-run complete"
  exit 0
fi

log "Uninstalled bazel-gen"
log "  removed launcher: ${LAUNCHER_PATH}"
log "  removed payload: ${APP_DIR}"
log "  removed config: ${CONFIG_DIR}"
log "  removed PATH blocks from shell rc files"
