#!/usr/bin/env bash

bazel_gen_template_roots() {
  if [ -n "${BAZEL_GEN_TEMPLATE_DIR:-}" ]; then
    printf "%s\n" "${BAZEL_GEN_TEMPLATE_DIR%/}"
  fi
  printf "%s\n" "${HOME}/.bazel-gen/templates"
  printf "%s\n" "${BAZEL_GEN_ROOT_DIR}/templates"
}

bazel_gen_template_description() {
  local template_dir="$1"
  local manifest_file="${template_dir}/template.manifest"
  local meta_file="${template_dir}/template.meta"
  if [ -f "${manifest_file}" ]; then
    local manifest_description
    manifest_description="$(sed -n 's/^description|//p' "${manifest_file}" | head -n 1)"
    if [ -n "${manifest_description}" ]; then
      printf "%s" "${manifest_description}"
      return 0
    fi
  fi

  if [ ! -f "${meta_file}" ]; then
    printf "No description"
    return 0
  fi

  local description
  description="$(sed -n 's/^description=//p' "${meta_file}" | head -n 1)"
  if [ -z "${description}" ]; then
    description="No description"
  fi
  printf "%s" "${description}"
}

bazel_gen_list_templates() {
  local seen=""
  local root
  while IFS= read -r root; do
    [ -d "${root}" ] || continue
    local template_dir
    while IFS= read -r template_dir; do
      local relative
      relative="${template_dir#${root}/}"
      local language
      language="${relative%%/*}"
      local template
      template="${relative#*/}"
      if [ "${template#*/}" != "${template}" ]; then
        continue
      fi
      local key="${language}:${template}"
      case "${seen}" in
        *"|${key}|"*)
          continue
          ;;
      esac
      seen="${seen}|${key}|"
      local description
      description="$(bazel_gen_template_description "${template_dir}")"
      printf "%-10s %-14s %s\n" "${language}" "${template}" "${description}"
    done < <(find "${root}" -mindepth 2 -maxdepth 2 -type d | sort)
  done < <(bazel_gen_template_roots)
}

bazel_gen_find_template() {
  local language="$1"
  local template="$2"
  local root
  while IFS= read -r root; do
    local candidate="${root}/${language}/${template}"
    if [ -d "${candidate}" ]; then
      printf "%s" "${candidate}"
      return 0
    fi
  done < <(bazel_gen_template_roots)
  return 1
}

bazel_gen_template_layers() {
  local language="$1"
  local template="$2"
  local found=1
  local roots=()
  local root
  while IFS= read -r root; do
    roots+=("${root}")
  done < <(bazel_gen_template_roots)

  local index
  for ((index=${#roots[@]} - 1; index>=0; index--)); do
    local candidate="${roots[${index}]}/${language}/${template}"
    if [ -d "${candidate}" ]; then
      printf "%s\n" "${candidate}"
      found=0
    fi
  done

  return "${found}"
}

bazel_gen_render_path() {
  local template_relative_path="$1"
  local rendered
  rendered="$(bazel_gen_replace_builtin_placeholders "${template_relative_path}")"

  local i
  for ((i = 0; i < ${#BAZEL_GEN_MANIFEST_OPTION_KEYS[@]}; i++)); do
    local option_key_upper
    option_key_upper="$(bazel_gen_to_upper "${BAZEL_GEN_MANIFEST_OPTION_KEYS[${i}]}")"
    rendered="${rendered//__OPT_${option_key_upper}__/${BAZEL_GEN_MANIFEST_OPTION_VALUES[${i}]}}"
  done

  case "${rendered}" in
    *.tmpl)
      rendered="${rendered%.tmpl}"
      ;;
  esac
  printf "%s" "${rendered}"
}

bazel_gen_render_template_file() {
  local template_source_file="$1"
  local output_file="$2"
  local should_render=0

  case "${template_source_file}" in
    *.tmpl)
      should_render=1
      ;;
  esac

  if [ "${should_render}" -eq 0 ]; then
    bazel_gen_copy_file "${template_source_file}" "${output_file}"
    bazel_gen_set_executable_like "${template_source_file}" "${output_file}"
    return 0
  fi

  local app_name_escaped
  app_name_escaped="$(bazel_gen_escape_sed_replacement "${BAZEL_GEN_TMPL_APP_NAME}")"
  local app_slug_escaped
  app_slug_escaped="$(bazel_gen_escape_sed_replacement "${BAZEL_GEN_TMPL_APP_SLUG}")"
  local module_name_escaped
  module_name_escaped="$(bazel_gen_escape_sed_replacement "${BAZEL_GEN_TMPL_MODULE_NAME}")"
  local package_escaped
  package_escaped="$(bazel_gen_escape_sed_replacement "${BAZEL_GEN_TMPL_PACKAGE}")"
  local package_path_escaped
  package_path_escaped="$(bazel_gen_escape_sed_replacement "${BAZEL_GEN_TMPL_PACKAGE_PATH}")"
  local scala_version_escaped
  scala_version_escaped="$(bazel_gen_escape_sed_replacement "${BAZEL_GEN_TMPL_SCALA_VERSION}")"
  local rules_scala_version_escaped
  rules_scala_version_escaped="$(bazel_gen_escape_sed_replacement "${BAZEL_GEN_TMPL_RULES_SCALA_VERSION}")"
  local java_version_escaped
  java_version_escaped="$(bazel_gen_escape_sed_replacement "${BAZEL_GEN_TMPL_JAVA_VERSION}")"
  local rules_java_version_escaped
  rules_java_version_escaped="$(bazel_gen_escape_sed_replacement "${BAZEL_GEN_TMPL_RULES_JAVA_VERSION}")"
  local year_escaped
  year_escaped="$(bazel_gen_escape_sed_replacement "${BAZEL_GEN_TMPL_YEAR}")"

  local -a sed_args
  sed_args=(
    -e "s|__APP_NAME__|${app_name_escaped}|g"
    -e "s|__APP_SLUG__|${app_slug_escaped}|g"
    -e "s|__MODULE_NAME__|${module_name_escaped}|g"
    -e "s|__PACKAGE__|${package_escaped}|g"
    -e "s|__PACKAGE_PATH__|${package_path_escaped}|g"
    -e "s|__SCALA_VERSION__|${scala_version_escaped}|g"
    -e "s|__RULES_SCALA_VERSION__|${rules_scala_version_escaped}|g"
    -e "s|__JAVA_VERSION__|${java_version_escaped}|g"
    -e "s|__RULES_JAVA_VERSION__|${rules_java_version_escaped}|g"
    -e "s|__YEAR__|${year_escaped}|g"
  )

  local i
  for ((i = 0; i < ${#BAZEL_GEN_MANIFEST_OPTION_KEYS[@]}; i++)); do
    local option_key_upper
    option_key_upper="$(bazel_gen_to_upper "${BAZEL_GEN_MANIFEST_OPTION_KEYS[${i}]}")"
    local option_value_escaped
    option_value_escaped="$(bazel_gen_escape_sed_replacement "${BAZEL_GEN_MANIFEST_OPTION_VALUES[${i}]}")"
    sed_args+=(-e "s|__OPT_${option_key_upper}__|${option_value_escaped}|g")
  done

  sed "${sed_args[@]}" "${template_source_file}" | bazel_gen_write_file "${output_file}"

  bazel_gen_set_executable_like "${template_source_file}" "${output_file}"
}

bazel_gen_render_template_dir() {
  local template_dir="$1"
  local target_dir="$2"
  local source_file

  while IFS= read -r -d '' source_file; do
    local relative_path
    relative_path="${source_file#${template_dir}/}"
    case "$(basename "${relative_path}")" in
      template.meta|template.manifest|.DS_Store)
        continue
        ;;
    esac
    local rendered_path
    rendered_path="$(bazel_gen_render_path "${relative_path}")"
    local output_path
    output_path="${target_dir}/${rendered_path}"
    bazel_gen_render_template_file "${source_file}" "${output_path}"
  done < <(find "${template_dir}" -type f -print0)
}
