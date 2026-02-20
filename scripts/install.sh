#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PATH_BLOCK_START="# >>> bazel-gen installer >>>"
PATH_BLOCK_END="# <<< bazel-gen installer <<<"

DEFAULT_INSTALL_BASE="${HOME}/.local/share/bazel-gen"
DEFAULT_BIN_DIR="${HOME}/.local/bin"
DEFAULT_STATE_FILE="${HOME}/.bazel-gen/install-state"

INSTALL_BASE="${BAZEL_GEN_INSTALL_BASE:-${DEFAULT_INSTALL_BASE}}"
BIN_DIR="${BAZEL_GEN_BIN_DIR:-${DEFAULT_BIN_DIR}}"
STATE_FILE="${BAZEL_GEN_STATE_FILE:-${DEFAULT_STATE_FILE}}"
PATH_UPDATE=1
DRY_RUN=0

declare -a RC_FILES=()

usage() {
  cat <<USAGE
Usage:
  scripts/install.sh [options]

Options:
  --install-base <path>  Install payload directory (default: ${DEFAULT_INSTALL_BASE})
  --bin-dir <path>       Directory where launcher is written (default: ${DEFAULT_BIN_DIR})
  --state-file <path>    Install state file path (default: ${DEFAULT_STATE_FILE})
  --rc-file <path>       Shell rc file to update. Can be specified multiple times.
  --no-path-update       Skip PATH block injection into shell rc files.
  --dry-run              Print actions without writing files.
  -h, --help             Show this help.

Environment overrides:
  BAZEL_GEN_INSTALL_BASE
  BAZEL_GEN_BIN_DIR
  BAZEL_GEN_STATE_FILE
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
  tmp_file="$(mktemp "${TMPDIR:-/tmp}/bazel-gen-install.XXXXXX")"
  awk -v start="${PATH_BLOCK_START}" -v end="${PATH_BLOCK_END}" '
    $0 == start { in_block = 1; next }
    $0 == end { in_block = 0; next }
    in_block != 1 { print }
  ' "${file_path}" > "${tmp_file}"

  if [ "${DRY_RUN}" -eq 1 ]; then
    log "[dry-run] update ${file_path} (remove existing bazel-gen PATH block)"
    rm -f "${tmp_file}"
    return 0
  fi

  cat "${tmp_file}" > "${file_path}"
  rm -f "${tmp_file}"
}

append_path_block() {
  local file_path="$1"

  if [ "${DRY_RUN}" -eq 1 ]; then
    log "[dry-run] update ${file_path} (add bazel-gen PATH block)"
    return 0
  fi

  mkdir -p "$(dirname "${file_path}")"
  touch "${file_path}"
  strip_path_block "${file_path}"

  {
    printf "\n%s\n" "${PATH_BLOCK_START}"
    printf "if [ -d \"%s\" ]; then\n" "${BIN_DIR}"
    printf "  case \":\\$PATH:\" in\n"
    printf "    *:\"%s\":*) ;;\n" "${BIN_DIR}"
    printf "    *) export PATH=\"%s:\\$PATH\" ;;\n" "${BIN_DIR}"
    printf "  esac\n"
    printf "fi\n"
    printf "%s\n" "${PATH_BLOCK_END}"
  } >> "${file_path}"
}

join_by_colon() {
  local result=""
  local item
  for item in "$@"; do
    if [ -z "${result}" ]; then
      result="${item}"
    else
      result="${result}:${item}"
    fi
  done
  printf "%s" "${result}"
}

write_state_file() {
  local app_dir="$1"
  local launcher_path="$2"
  local rc_joined
  rc_joined="$(join_by_colon "${RC_FILES[@]-}")"

  if [ "${DRY_RUN}" -eq 1 ]; then
    log "[dry-run] write ${STATE_FILE}"
    return 0
  fi

  mkdir -p "$(dirname "${STATE_FILE}")"
  {
    printf "BAZEL_GEN_STATE_INSTALL_BASE=%q\n" "${INSTALL_BASE}"
    printf "BAZEL_GEN_STATE_APP_DIR=%q\n" "${app_dir}"
    printf "BAZEL_GEN_STATE_BIN_DIR=%q\n" "${BIN_DIR}"
    printf "BAZEL_GEN_STATE_LAUNCHER_PATH=%q\n" "${launcher_path}"
    printf "BAZEL_GEN_STATE_PATH_UPDATE=%q\n" "${PATH_UPDATE}"
    printf "BAZEL_GEN_STATE_RC_FILES=%q\n" "${rc_joined}"
  } > "${STATE_FILE}"
}

write_launcher() {
  local app_dir="$1"
  local launcher_path="$2"

  if [ "${DRY_RUN}" -eq 1 ]; then
    log "[dry-run] write ${launcher_path}"
    return 0
  fi

  mkdir -p "$(dirname "${launcher_path}")"
  cat > "${launcher_path}" <<LAUNCHER
#!/usr/bin/env bash
set -euo pipefail
exec "${app_dir}/bin/bazel-gen" "\$@"
LAUNCHER
  chmod +x "${launcher_path}"
}

validate_repo_layout() {
  [ -f "${REPO_ROOT}/bin/bazel-gen" ] || die "Missing ${REPO_ROOT}/bin/bazel-gen"
  [ -d "${REPO_ROOT}/lib" ] || die "Missing ${REPO_ROOT}/lib"
  [ -d "${REPO_ROOT}/templates" ] || die "Missing ${REPO_ROOT}/templates"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --install-base)
      [ "$#" -ge 2 ] || die "Missing value for --install-base"
      INSTALL_BASE="$2"
      shift 2
      ;;
    --bin-dir)
      [ "$#" -ge 2 ] || die "Missing value for --bin-dir"
      BIN_DIR="$2"
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
    --no-path-update)
      PATH_UPDATE=0
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

INSTALL_BASE="$(expand_home "${INSTALL_BASE}")"
BIN_DIR="$(expand_home "${BIN_DIR}")"
STATE_FILE="$(expand_home "${STATE_FILE}")"

validate_repo_layout

if [ "${PATH_UPDATE}" -eq 1 ] && [ "${#RC_FILES[@]}" -eq 0 ]; then
  while IFS= read -r file_path; do
    [ -n "${file_path}" ] || continue
    add_unique_rc_file "${file_path}"
  done < <(detect_rc_files)
fi

APP_DIR="${INSTALL_BASE}/app"
LAUNCHER_PATH="${BIN_DIR}/bazel-gen"

if [ -d "${APP_DIR}" ]; then
  run_cmd rm -rf "${APP_DIR}"
fi
run_cmd mkdir -p "${APP_DIR}"
run_cmd cp -R "${REPO_ROOT}/bin" "${APP_DIR}/bin"
run_cmd cp -R "${REPO_ROOT}/lib" "${APP_DIR}/lib"
run_cmd cp -R "${REPO_ROOT}/templates" "${APP_DIR}/templates"
run_cmd cp "${REPO_ROOT}/README.md" "${APP_DIR}/README.md"

write_launcher "${APP_DIR}" "${LAUNCHER_PATH}"
write_state_file "${APP_DIR}" "${LAUNCHER_PATH}"

if [ "${PATH_UPDATE}" -eq 1 ]; then
  local_rc_file=""
  for local_rc_file in "${RC_FILES[@]-}"; do
    append_path_block "${local_rc_file}"
  done
fi

if [ "${DRY_RUN}" -eq 1 ]; then
  log "dry-run complete"
  exit 0
fi

log "Installed bazel-gen"
log "  payload: ${APP_DIR}"
log "  launcher: ${LAUNCHER_PATH}"
log "  state: ${STATE_FILE}"

if [ "${PATH_UPDATE}" -eq 1 ]; then
  log "  PATH updated in:"
  rc_file=""
  for rc_file in "${RC_FILES[@]-}"; do
    log "    ${rc_file}"
  done
fi

case ":${PATH}:" in
  *:"${BIN_DIR}":*)
    ;;
  *)
    log "Current shell PATH does not include ${BIN_DIR}."
    log "Run: export PATH=\"${BIN_DIR}:\$PATH\""
    ;;
esac

log "Verify: bazel-gen --help"
