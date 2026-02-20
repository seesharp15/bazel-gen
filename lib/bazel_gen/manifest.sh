#!/usr/bin/env bash

BAZEL_GEN_MANIFEST_DESCRIPTION=""
BAZEL_GEN_MANIFEST_OPTION_KEYS=()
BAZEL_GEN_MANIFEST_OPTION_FLAGS=()
BAZEL_GEN_MANIFEST_OPTION_TYPES=()
BAZEL_GEN_MANIFEST_OPTION_DEFAULTS=()
BAZEL_GEN_MANIFEST_OPTION_REQUIRED=()
BAZEL_GEN_MANIFEST_OPTION_DESCRIPTIONS=()
BAZEL_GEN_MANIFEST_OPTION_VALUES=()

bazel_gen_manifest_reset() {
  BAZEL_GEN_MANIFEST_DESCRIPTION=""
  BAZEL_GEN_MANIFEST_OPTION_KEYS=()
  BAZEL_GEN_MANIFEST_OPTION_FLAGS=()
  BAZEL_GEN_MANIFEST_OPTION_TYPES=()
  BAZEL_GEN_MANIFEST_OPTION_DEFAULTS=()
  BAZEL_GEN_MANIFEST_OPTION_REQUIRED=()
  BAZEL_GEN_MANIFEST_OPTION_DESCRIPTIONS=()
  BAZEL_GEN_MANIFEST_OPTION_VALUES=()
}

bazel_gen_manifest_find_key_index() {
  local key="$1"
  local i
  for ((i = 0; i < ${#BAZEL_GEN_MANIFEST_OPTION_KEYS[@]}; i++)); do
    if [ "${BAZEL_GEN_MANIFEST_OPTION_KEYS[${i}]}" = "${key}" ]; then
      printf "%s" "${i}"
      return 0
    fi
  done
  return 1
}

bazel_gen_manifest_find_flag_index() {
  local flag="$1"
  local i
  for ((i = 0; i < ${#BAZEL_GEN_MANIFEST_OPTION_FLAGS[@]}; i++)); do
    if [ "${BAZEL_GEN_MANIFEST_OPTION_FLAGS[${i}]}" = "${flag}" ]; then
      printf "%s" "${i}"
      return 0
    fi
  done
  return 1
}

bazel_gen_manifest_normalize_bool() {
  local value
  value="$(bazel_gen_to_lower "$1")"
  case "${value}" in
    1|true|yes|on)
      printf "true"
      ;;
    0|false|no|off)
      printf "false"
      ;;
    *)
      return 1
      ;;
  esac
}

bazel_gen_manifest_validate_type() {
  local type="$1"
  local value="$2"
  local flag_name="$3"
  case "${type}" in
    string)
      return 0
      ;;
    version)
      if ! bazel_gen_validate_scala_version "${value}"; then
        bazel_gen_die "Invalid value for ${flag_name}: '${value}' (expected x.y.z)"
      fi
      ;;
    int)
      if ! [[ "${value}" =~ ^[0-9]+$ ]]; then
        bazel_gen_die "Invalid value for ${flag_name}: '${value}' (expected integer)"
      fi
      ;;
    bool)
      if ! bazel_gen_manifest_normalize_bool "${value}" >/dev/null; then
        bazel_gen_die "Invalid value for ${flag_name}: '${value}' (expected true/false)"
      fi
      ;;
    *)
      bazel_gen_die "Unsupported option type '${type}' in template manifest"
      ;;
  esac
}

bazel_gen_manifest_upsert_option() {
  local key="$1"
  local flag="$2"
  local type="$3"
  local default_value="$4"
  local required="$5"
  local description="$6"

  if ! bazel_gen_validate_identifier "${key}"; then
    bazel_gen_die "Invalid option key '${key}' in template manifest"
  fi
  if ! [[ "${flag}" =~ ^--[a-z0-9][a-z0-9-]*$ ]]; then
    bazel_gen_die "Invalid option flag '${flag}' in template manifest"
  fi
  case "${type}" in
    string|version|int|bool)
      ;;
    *)
      bazel_gen_die "Invalid option type '${type}' in template manifest"
      ;;
  esac
  case "${required}" in
    required|optional)
      ;;
    *)
      bazel_gen_die "Invalid required value '${required}' in template manifest (expected required|optional)"
      ;;
  esac

  local index
  if ! index="$(bazel_gen_manifest_find_key_index "${key}")"; then
    index="${#BAZEL_GEN_MANIFEST_OPTION_KEYS[@]}"
  fi

  BAZEL_GEN_MANIFEST_OPTION_KEYS[${index}]="${key}"
  BAZEL_GEN_MANIFEST_OPTION_FLAGS[${index}]="${flag}"
  BAZEL_GEN_MANIFEST_OPTION_TYPES[${index}]="${type}"
  BAZEL_GEN_MANIFEST_OPTION_DEFAULTS[${index}]="${default_value}"
  BAZEL_GEN_MANIFEST_OPTION_REQUIRED[${index}]="${required}"
  BAZEL_GEN_MANIFEST_OPTION_DESCRIPTIONS[${index}]="${description}"
}

bazel_gen_manifest_load_file() {
  local manifest_file="$1"
  local line
  local line_number=0

  while IFS= read -r line || [ -n "${line}" ]; do
    line_number=$((line_number + 1))
    line="${line%$'\r'}"

    [ -n "${line}" ] || continue
    case "${line}" in
      \#*)
        continue
        ;;
    esac

    if [[ "${line}" == description\|* ]]; then
      BAZEL_GEN_MANIFEST_DESCRIPTION="${line#description|}"
      continue
    fi

    if [[ "${line}" == option\|* ]]; then
      local kind key flag type default_value required description extra
      IFS='|' read -r kind key flag type default_value required description extra <<< "${line}"
      if [ -n "${extra:-}" ]; then
        bazel_gen_die "Invalid manifest option format at ${manifest_file}:${line_number}"
      fi
      if [ -z "${key}" ] || [ -z "${flag}" ]; then
        bazel_gen_die "Invalid manifest option format at ${manifest_file}:${line_number}"
      fi
      [ -n "${type}" ] || type="string"
      [ -n "${required}" ] || required="optional"
      bazel_gen_manifest_upsert_option "${key}" "${flag}" "${type}" "${default_value}" "${required}" "${description}"
      continue
    fi

    bazel_gen_die "Invalid manifest entry at ${manifest_file}:${line_number}"
  done < "${manifest_file}"
}

bazel_gen_manifest_load_layer() {
  local template_dir="$1"
  local meta_file="${template_dir}/template.meta"
  local manifest_file="${template_dir}/template.manifest"

  if [ -f "${meta_file}" ]; then
    local meta_description
    meta_description="$(sed -n 's/^description=//p' "${meta_file}" | head -n 1)"
    if [ -n "${meta_description}" ]; then
      BAZEL_GEN_MANIFEST_DESCRIPTION="${meta_description}"
    fi
  fi

  if [ -f "${manifest_file}" ]; then
    bazel_gen_manifest_load_file "${manifest_file}"
  fi
}

bazel_gen_manifest_apply_defaults() {
  local i
  for ((i = 0; i < ${#BAZEL_GEN_MANIFEST_OPTION_KEYS[@]}; i++)); do
    local type="${BAZEL_GEN_MANIFEST_OPTION_TYPES[${i}]}"
    local default_value="${BAZEL_GEN_MANIFEST_OPTION_DEFAULTS[${i}]}"

    if [ "${type}" = "bool" ] && [ -z "${default_value}" ]; then
      default_value="false"
    fi

    local rendered_default
    rendered_default="$(bazel_gen_replace_builtin_placeholders "${default_value}")"

    if [ "${type}" = "bool" ] && [ -n "${rendered_default}" ]; then
      rendered_default="$(bazel_gen_manifest_normalize_bool "${rendered_default}")" || {
        bazel_gen_die "Invalid default bool value '${default_value}' for ${BAZEL_GEN_MANIFEST_OPTION_FLAGS[${i}]}"
      }
    fi

    bazel_gen_manifest_validate_type "${type}" "${rendered_default}" "${BAZEL_GEN_MANIFEST_OPTION_FLAGS[${i}]}"
    BAZEL_GEN_MANIFEST_OPTION_VALUES[${i}]="${rendered_default}"
  done
}

bazel_gen_manifest_known_flags() {
  local flags=""
  local i
  for ((i = 0; i < ${#BAZEL_GEN_MANIFEST_OPTION_FLAGS[@]}; i++)); do
    if [ -z "${flags}" ]; then
      flags="${BAZEL_GEN_MANIFEST_OPTION_FLAGS[${i}]}"
    else
      flags="${flags} ${BAZEL_GEN_MANIFEST_OPTION_FLAGS[${i}]}"
    fi
  done
  printf "%s" "${flags}"
}

bazel_gen_manifest_parse_cli_args() {
  local -a args=("$@")
  local index=0
  while [ "${index}" -lt "${#args[@]}" ]; do
    local token="${args[${index}]}"
    if [[ "${token}" != -* ]]; then
      bazel_gen_die "Unexpected argument: ${token}"
    fi

    local flag="${token}"
    local inline_value=""
    local has_inline_value=0
    if [[ "${token}" == *=* ]]; then
      flag="${token%%=*}"
      inline_value="${token#*=}"
      has_inline_value=1
    fi

    local option_index
    if ! option_index="$(bazel_gen_manifest_find_flag_index "${flag}")"; then
      local known_flags
      known_flags="$(bazel_gen_manifest_known_flags)"
      if [ -n "${known_flags}" ]; then
        bazel_gen_die "Unknown template option '${flag}'. Supported options: ${known_flags}"
      fi
      bazel_gen_die "Template does not define options but received '${flag}'"
    fi

    local type="${BAZEL_GEN_MANIFEST_OPTION_TYPES[${option_index}]}"
    local value=""
    if [ "${type}" = "bool" ]; then
      if [ "${has_inline_value}" -eq 1 ]; then
        value="$(bazel_gen_manifest_normalize_bool "${inline_value}")" || {
          bazel_gen_die "Invalid value for ${flag}: '${inline_value}' (expected true/false)"
        }
      else
        value="true"
      fi
    else
      if [ "${has_inline_value}" -eq 1 ]; then
        value="${inline_value}"
      else
        index=$((index + 1))
        if [ "${index}" -ge "${#args[@]}" ]; then
          bazel_gen_die "Missing value for ${flag}"
        fi
        value="${args[${index}]}"
      fi
      bazel_gen_manifest_validate_type "${type}" "${value}" "${flag}"
    fi

    BAZEL_GEN_MANIFEST_OPTION_VALUES[${option_index}]="${value}"
    index=$((index + 1))
  done
}

bazel_gen_manifest_validate_required() {
  local i
  for ((i = 0; i < ${#BAZEL_GEN_MANIFEST_OPTION_KEYS[@]}; i++)); do
    if [ "${BAZEL_GEN_MANIFEST_OPTION_REQUIRED[${i}]}" != "required" ]; then
      continue
    fi
    if [ -z "${BAZEL_GEN_MANIFEST_OPTION_VALUES[${i}]}" ]; then
      bazel_gen_die "Missing required template option ${BAZEL_GEN_MANIFEST_OPTION_FLAGS[${i}]}"
    fi
  done
}

bazel_gen_manifest_apply_template_vars() {
  local i
  for ((i = 0; i < ${#BAZEL_GEN_MANIFEST_OPTION_KEYS[@]}; i++)); do
    local key="${BAZEL_GEN_MANIFEST_OPTION_KEYS[${i}]}"
    local value="${BAZEL_GEN_MANIFEST_OPTION_VALUES[${i}]}"
    case "${key}" in
      package)
        if [ -z "${value}" ]; then
          continue
        fi
        if ! bazel_gen_validate_package "${value}"; then
          bazel_gen_die "Invalid package '${value}'. Expected format like: com.example.app"
        fi
        BAZEL_GEN_TMPL_PACKAGE="${value}"
        BAZEL_GEN_TMPL_PACKAGE_PATH="$(bazel_gen_package_path "${value}")"
        ;;
      scala_version)
        if [ -z "${value}" ]; then
          continue
        fi
        if ! bazel_gen_validate_scala_version "${value}"; then
          bazel_gen_die "Invalid scala_version '${value}'. Expected x.y.z"
        fi
        BAZEL_GEN_TMPL_SCALA_VERSION="${value}"
        ;;
      rules_scala_version)
        if [ -z "${value}" ]; then
          continue
        fi
        if ! bazel_gen_validate_scala_version "${value}"; then
          bazel_gen_die "Invalid rules_scala_version '${value}'. Expected x.y.z"
        fi
        BAZEL_GEN_TMPL_RULES_SCALA_VERSION="${value}"
        ;;
      java_version)
        BAZEL_GEN_TMPL_JAVA_VERSION="${value}"
        ;;
      rules_java_version)
        BAZEL_GEN_TMPL_RULES_JAVA_VERSION="${value}"
        ;;
    esac
  done
}

bazel_gen_manifest_print_options() {
  if [ "${#BAZEL_GEN_MANIFEST_OPTION_KEYS[@]}" -eq 0 ]; then
    bazel_gen_info "No template options are defined."
    return 0
  fi

  printf "%-22s %-10s %-10s %-8s %s\n" "FLAG" "TYPE" "REQUIRED" "DEFAULT" "DESCRIPTION"
  local i
  for ((i = 0; i < ${#BAZEL_GEN_MANIFEST_OPTION_KEYS[@]}; i++)); do
    local default_rendered
    default_rendered="$(bazel_gen_replace_builtin_placeholders "${BAZEL_GEN_MANIFEST_OPTION_DEFAULTS[${i}]}")"
    printf "%-22s %-10s %-10s %-8s %s\n" \
      "${BAZEL_GEN_MANIFEST_OPTION_FLAGS[${i}]}" \
      "${BAZEL_GEN_MANIFEST_OPTION_TYPES[${i}]}" \
      "${BAZEL_GEN_MANIFEST_OPTION_REQUIRED[${i}]}" \
      "${default_rendered}" \
      "${BAZEL_GEN_MANIFEST_OPTION_DESCRIPTIONS[${i}]}"
  done
}
