#!/usr/bin/env bash

BAZEL_GEN_VERSION="0.1.0"
BAZEL_GEN_DRY_RUN=0

bazel_gen_info() {
  printf "%s\n" "$*"
}

bazel_gen_error() {
  printf "error: %s\n" "$*" >&2
}

bazel_gen_die() {
  bazel_gen_error "$*"
  exit 1
}

bazel_gen_to_lower() {
  printf "%s" "$1" | tr '[:upper:]' '[:lower:]'
}

bazel_gen_to_upper() {
  printf "%s" "$1" | tr '[:lower:]' '[:upper:]'
}

bazel_gen_expand_home() {
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

bazel_gen_validate_app_name() {
  local app_name="$1"
  case "${app_name}" in
    [A-Za-z][A-Za-z0-9_-]*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

bazel_gen_validate_package() {
  local package_name="$1"
  [[ "${package_name}" =~ ^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$ ]]
}

bazel_gen_validate_scala_version() {
  local scala_version="$1"
  [[ "${scala_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

bazel_gen_slug_to_identifier() {
  local value
  value="$(printf "%s" "$1" | tr '[:upper:]' '[:lower:]' | tr '-' '_' | tr -cd '[:alnum:]_')"
  if [ -z "${value}" ]; then
    value="app"
  fi
  case "${value}" in
    [0-9]*)
      value="app_${value}"
      ;;
  esac
  printf "%s" "${value}"
}

bazel_gen_default_package() {
  local app_name="$1"
  printf "com.example.%s" "$(bazel_gen_slug_to_identifier "${app_name}")"
}

bazel_gen_validate_identifier() {
  local identifier="$1"
  [[ "${identifier}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

bazel_gen_module_name_from_app() {
  bazel_gen_slug_to_identifier "$1"
}

bazel_gen_package_path() {
  printf "%s" "$1" | tr '.' '/'
}

bazel_gen_has_directory_entries() {
  local path="$1"
  if [ ! -d "${path}" ]; then
    return 1
  fi
  [ -n "$(find "${path}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]
}

bazel_gen_prepare_target_dir() {
  local target_dir="$1"
  local force="$2"

  if [ -d "${target_dir}" ]; then
    if bazel_gen_has_directory_entries "${target_dir}" && [ "${force}" -ne 1 ]; then
      bazel_gen_die "Target directory exists and is not empty: ${target_dir} (use --force to overwrite generated files)"
    fi
    if bazel_gen_has_directory_entries "${target_dir}" && [ "${force}" -eq 1 ]; then
      bazel_gen_info "warning: target directory is not empty; known generated files will be overwritten."
    fi
    return 0
  fi

  if [ "${BAZEL_GEN_DRY_RUN}" -eq 1 ]; then
    bazel_gen_info "[dry-run] mkdir -p ${target_dir}"
    return 0
  fi

  mkdir -p "${target_dir}"
}

bazel_gen_mkdir() {
  local path="$1"
  if [ "${BAZEL_GEN_DRY_RUN}" -eq 1 ]; then
    bazel_gen_info "[dry-run] mkdir -p ${path}"
    return 0
  fi
  mkdir -p "${path}"
}

bazel_gen_write_file() {
  local destination="$1"
  if [ "${BAZEL_GEN_DRY_RUN}" -eq 1 ]; then
    bazel_gen_info "[dry-run] write ${destination}"
    cat >/dev/null
    return 0
  fi
  mkdir -p "$(dirname "${destination}")"
  cat >"${destination}"
}

bazel_gen_copy_file() {
  local source="$1"
  local destination="$2"
  if [ "${BAZEL_GEN_DRY_RUN}" -eq 1 ]; then
    bazel_gen_info "[dry-run] copy ${destination}"
    return 0
  fi
  mkdir -p "$(dirname "${destination}")"
  cp "${source}" "${destination}"
}

bazel_gen_set_executable_like() {
  local source="$1"
  local destination="$2"
  if [ ! -x "${source}" ]; then
    return 0
  fi
  if [ "${BAZEL_GEN_DRY_RUN}" -eq 1 ]; then
    bazel_gen_info "[dry-run] chmod +x ${destination}"
    return 0
  fi
  chmod +x "${destination}"
}

bazel_gen_join_path() {
  local left="${1%/}"
  local right="$2"
  if [ -z "${left}" ] || [ "${left}" = "." ]; then
    printf "%s" "${right}"
    return 0
  fi
  printf "%s/%s" "${left}" "${right}"
}

bazel_gen_escape_sed_replacement() {
  printf "%s" "$1" | sed -e 's/[\/&|]/\\&/g'
}

bazel_gen_replace_builtin_placeholders() {
  local value="$1"
  value="${value//__APP_NAME__/${BAZEL_GEN_TMPL_APP_NAME:-}}"
  value="${value//__APP_SLUG__/${BAZEL_GEN_TMPL_APP_SLUG:-}}"
  value="${value//__MODULE_NAME__/${BAZEL_GEN_TMPL_MODULE_NAME:-}}"
  value="${value//__PACKAGE__/${BAZEL_GEN_TMPL_PACKAGE:-}}"
  value="${value//__PACKAGE_PATH__/${BAZEL_GEN_TMPL_PACKAGE_PATH:-}}"
  value="${value//__SCALA_VERSION__/${BAZEL_GEN_TMPL_SCALA_VERSION:-}}"
  value="${value//__RULES_SCALA_VERSION__/${BAZEL_GEN_TMPL_RULES_SCALA_VERSION:-}}"
  value="${value//__JAVA_VERSION__/${BAZEL_GEN_TMPL_JAVA_VERSION:-}}"
  value="${value//__RULES_JAVA_VERSION__/${BAZEL_GEN_TMPL_RULES_JAVA_VERSION:-}}"
  value="${value//__YEAR__/${BAZEL_GEN_TMPL_YEAR:-}}"
  printf "%s" "${value}"
}
