#!/usr/bin/env bash

bazel_gen_new_usage() {
  cat <<EOF
Usage:
  bazel-gen new <language> <template> <app-name> [options]
  bazel-gen gen new <language> <template> <app-name> [options]
  bazel-gen new --list
  bazel-gen new --list-options <language> <template>

Examples:
  bazel-gen new scala console my-app --package com.example.myapp
  bazel-gen new java console my-app --package com.example.myapp --java-version 21
  bazel-gen new --list
  bazel-gen new --list-options scala console

Global options:
  --dest <path>                  Parent directory where the project will be created.
  --force                        Overwrite generated files when target exists.
  --dry-run                      Print actions without writing files.
  --list                         List available templates.
  --list-options <lang> <tmpl>   Show template-specific options from template.manifest.
  -h, --help                     Show this help.

Template resolution order:
  1. \$BAZEL_GEN_TEMPLATE_DIR/<language>/<template>
  2. ~/.bazel-gen/templates/<language>/<template>
  3. Built-in templates in this repository

Higher-priority templates override lower-priority files.
EOF
}

bazel_gen_new_list_options() {
  local language="${1:-}"
  local template="${2:-}"
  if [ -z "${language}" ] || [ -z "${template}" ]; then
    bazel_gen_die "Expected: bazel-gen new --list-options <language> <template>"
  fi

  language="$(bazel_gen_to_lower "${language}")"
  template="$(bazel_gen_to_lower "${template}")"

  local template_layers
  template_layers="$(bazel_gen_template_layers "${language}" "${template}")" || {
    bazel_gen_die "Template not found: ${language}/${template}"
  }

  # Use a stable sample context for displaying rendered defaults.
  BAZEL_GEN_TMPL_APP_NAME="sample-app"
  BAZEL_GEN_TMPL_APP_SLUG="sample_app"
  BAZEL_GEN_TMPL_MODULE_NAME="sample_app"
  BAZEL_GEN_TMPL_PACKAGE="com.example.sample_app"
  BAZEL_GEN_TMPL_PACKAGE_PATH="com/example/sample_app"
  BAZEL_GEN_TMPL_SCALA_VERSION="2.13.17"
  BAZEL_GEN_TMPL_RULES_SCALA_VERSION="7.2.1"
  BAZEL_GEN_TMPL_JAVA_VERSION="21"
  BAZEL_GEN_TMPL_RULES_JAVA_VERSION="9.5.0"
  BAZEL_GEN_TMPL_YEAR="$(date +%Y)"

  bazel_gen_manifest_reset
  local layer
  while IFS= read -r layer; do
    [ -n "${layer}" ] || continue
    bazel_gen_manifest_load_layer "${layer}"
  done <<< "${template_layers}"
  bazel_gen_manifest_apply_defaults

  if [ -n "${BAZEL_GEN_MANIFEST_DESCRIPTION}" ]; then
    bazel_gen_info "${language}/${template}: ${BAZEL_GEN_MANIFEST_DESCRIPTION}"
  else
    bazel_gen_info "${language}/${template}"
  fi
  bazel_gen_manifest_print_options
}

bazel_gen_cmd_new() {
  local language=""
  local template=""
  local app_name=""
  local destination="."
  local force=0
  local dry_run=0
  local -a template_option_args=()

  if [ "${1:-}" = "--list" ]; then
    printf "%-10s %-14s %s\n" "LANGUAGE" "TEMPLATE" "DESCRIPTION"
    bazel_gen_list_templates
    return 0
  fi

  if [ "${1:-}" = "--list-options" ]; then
    shift
    bazel_gen_new_list_options "${1:-}" "${2:-}"
    return 0
  fi

  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help)
        bazel_gen_new_usage
        return 0
        ;;
      --list)
        printf "%-10s %-14s %s\n" "LANGUAGE" "TEMPLATE" "DESCRIPTION"
        bazel_gen_list_templates
        return 0
        ;;
      --list-options)
        shift
        bazel_gen_new_list_options "${1:-}" "${2:-}"
        return 0
        ;;
      --dest)
        [ "$#" -ge 2 ] || bazel_gen_die "Missing value for --dest"
        destination="$2"
        shift 2
        ;;
      --force)
        force=1
        shift
        ;;
      --dry-run)
        dry_run=1
        shift
        ;;
      --)
        shift
        while [ "$#" -gt 0 ]; do
          template_option_args+=("$1")
          shift
        done
        break
        ;;
      -*)
        template_option_args+=("$1")
        shift
        ;;
      *)
        if [ -z "${language}" ]; then
          language="$1"
        elif [ -z "${template}" ]; then
          template="$1"
        elif [ -z "${app_name}" ]; then
          app_name="$1"
        else
          template_option_args+=("$1")
        fi
        shift
        ;;
    esac
  done

  if [ -z "${language}" ] || [ -z "${template}" ] || [ -z "${app_name}" ]; then
    bazel_gen_new_usage
    bazel_gen_die "Expected: bazel-gen new <language> <template> <app-name>"
  fi

  language="$(bazel_gen_to_lower "${language}")"
  template="$(bazel_gen_to_lower "${template}")"

  if ! bazel_gen_validate_app_name "${app_name}"; then
    bazel_gen_die "Invalid app name '${app_name}'. Use letters/numbers/_/- and start with a letter."
  fi

  local template_layers
  template_layers="$(bazel_gen_template_layers "${language}" "${template}")" || {
    bazel_gen_error "Template not found: ${language}/${template}"
    bazel_gen_info "Available templates:"
    printf "%-10s %-14s %s\n" "LANGUAGE" "TEMPLATE" "DESCRIPTION"
    bazel_gen_list_templates
    return 1
  }

  local -a template_layer_dirs=()
  local template_layer
  while IFS= read -r template_layer; do
    [ -n "${template_layer}" ] || continue
    template_layer_dirs+=("${template_layer}")
  done <<< "${template_layers}"

  BAZEL_GEN_TMPL_APP_NAME="${app_name}"
  BAZEL_GEN_TMPL_APP_SLUG="$(bazel_gen_slug_to_identifier "${app_name}")"
  BAZEL_GEN_TMPL_MODULE_NAME="$(bazel_gen_module_name_from_app "${app_name}")"
  BAZEL_GEN_TMPL_PACKAGE="$(bazel_gen_default_package "${app_name}")"
  BAZEL_GEN_TMPL_PACKAGE_PATH="$(bazel_gen_package_path "${BAZEL_GEN_TMPL_PACKAGE}")"
  BAZEL_GEN_TMPL_SCALA_VERSION="2.13.17"
  BAZEL_GEN_TMPL_RULES_SCALA_VERSION="7.2.1"
  BAZEL_GEN_TMPL_JAVA_VERSION="21"
  BAZEL_GEN_TMPL_RULES_JAVA_VERSION="9.5.0"
  BAZEL_GEN_TMPL_YEAR="$(date +%Y)"

  bazel_gen_manifest_reset
  local i
  for ((i = 0; i < ${#template_layer_dirs[@]}; i++)); do
    bazel_gen_manifest_load_layer "${template_layer_dirs[${i}]}"
  done
  bazel_gen_manifest_apply_defaults
  if [ "${#template_option_args[@]}" -gt 0 ]; then
    bazel_gen_manifest_parse_cli_args "${template_option_args[@]}"
  else
    bazel_gen_manifest_parse_cli_args
  fi
  bazel_gen_manifest_validate_required
  bazel_gen_manifest_apply_template_vars

  # rules_scala builtin toolchains currently pin Scala 2.13.17 for this template.
  if [ "${language}" = "scala" ] && [ "${template}" = "console" ] && [ "${BAZEL_GEN_TMPL_SCALA_VERSION}" != "2.13.17" ]; then
    bazel_gen_die "Built-in template scala/console currently supports --scala-version 2.13.17 only."
  fi

  destination="$(bazel_gen_expand_home "${destination}")"
  local target_dir
  target_dir="$(bazel_gen_join_path "${destination}" "${app_name}")"

  BAZEL_GEN_DRY_RUN="${dry_run}"
  bazel_gen_prepare_target_dir "${target_dir}" "${force}"

  for ((i = 0; i < ${#template_layer_dirs[@]}; i++)); do
    bazel_gen_render_template_dir "${template_layer_dirs[${i}]}" "${target_dir}"
  done

  if [ "${dry_run}" -eq 1 ]; then
    bazel_gen_info "dry-run complete for ${target_dir}"
    return 0
  fi

  bazel_gen_info "Generated ${language} ${template} project: ${target_dir}"
  bazel_gen_info "Next steps:"
  bazel_gen_info "  cd ${target_dir}"
  bazel_gen_info "  bazel run //:app"
}
