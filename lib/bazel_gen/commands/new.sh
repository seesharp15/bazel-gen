#!/usr/bin/env bash

bazel_gen_new_usage() {
  cat <<EOF
Usage:
  bazel-gen new <language> <template> <app-name> [options]
  bazel-gen gen new <language> <template> <app-name> [options]
  bazel-gen new --list

Examples:
  bazel-gen new scala console my-app
  bazel-gen new scala console my-app --package com.example.myapp
  bazel-gen new scala console my-app --dest ./projects
  bazel-gen new --list

Options:
  --package <name>               Scala package name (default: derived from app name).
  --scala-version <version>      Scala version (default: 2.13.17 for built-in scala/console).
  --rules-scala-version <ver>    rules_scala BCR version (default: 7.2.1).
  --dest <path>                  Parent directory where the project will be created.
  --force                        Overwrite generated files when target exists.
  --dry-run                      Print actions without writing files.
  --list                         List available templates.
  -h, --help                     Show this help.

Template resolution order:
  1. \$BAZEL_GEN_TEMPLATE_DIR/<language>/<template>
  2. ~/.bazel-gen/templates/<language>/<template>
  3. Built-in templates in this repository
Higher-priority templates override lower-priority files.

Template placeholders (for *.tmpl files and path names):
  __APP_NAME__ __APP_SLUG__ __MODULE_NAME__ __PACKAGE__ __PACKAGE_PATH__
  __SCALA_VERSION__ __RULES_SCALA_VERSION__ __YEAR__
EOF
}

bazel_gen_cmd_new() {
  local language=""
  local template=""
  local app_name=""
  local package_name=""
  local scala_version="2.13.17"
  local rules_scala_version="7.2.1"
  local destination="."
  local force=0
  local dry_run=0

  if [ "${1:-}" = "--list" ]; then
    printf "%-10s %-14s %s\n" "LANGUAGE" "TEMPLATE" "DESCRIPTION"
    bazel_gen_list_templates
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
      --package)
        [ "$#" -ge 2 ] || bazel_gen_die "Missing value for --package"
        package_name="$2"
        shift 2
        ;;
      --scala-version)
        [ "$#" -ge 2 ] || bazel_gen_die "Missing value for --scala-version"
        scala_version="$2"
        shift 2
        ;;
      --rules-scala-version)
        [ "$#" -ge 2 ] || bazel_gen_die "Missing value for --rules-scala-version"
        rules_scala_version="$2"
        shift 2
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
        break
        ;;
      -*)
        bazel_gen_die "Unknown option for new: $1"
        ;;
      *)
        if [ -z "${language}" ]; then
          language="$1"
        elif [ -z "${template}" ]; then
          template="$1"
        elif [ -z "${app_name}" ]; then
          app_name="$1"
        else
          bazel_gen_die "Unexpected argument: $1"
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

  if [ -z "${package_name}" ]; then
    package_name="$(bazel_gen_default_package "${app_name}")"
  fi
  if ! bazel_gen_validate_package "${package_name}"; then
    bazel_gen_die "Invalid package '${package_name}'. Expected format like: com.example.app"
  fi

  if ! bazel_gen_validate_scala_version "${scala_version}"; then
    bazel_gen_die "Invalid --scala-version '${scala_version}'. Expected x.y.z"
  fi

  if ! bazel_gen_validate_scala_version "${rules_scala_version}"; then
    bazel_gen_die "Invalid --rules-scala-version '${rules_scala_version}'. Expected x.y.z"
  fi

  # rules_scala builtin toolchains currently pin Scala 2.13.17 for this template.
  if [ "${language}" = "scala" ] && [ "${template}" = "console" ] && [ "${scala_version}" != "2.13.17" ]; then
    bazel_gen_die "Built-in template scala/console currently supports --scala-version 2.13.17 only."
  fi

  local template_layers
  template_layers="$(bazel_gen_template_layers "${language}" "${template}")" || {
    bazel_gen_error "Template not found: ${language}/${template}"
    bazel_gen_info "Available templates:"
    printf "%-10s %-14s %s\n" "LANGUAGE" "TEMPLATE" "DESCRIPTION"
    bazel_gen_list_templates
    return 1
  }

  local target_dir
  target_dir="$(bazel_gen_join_path "${destination}" "${app_name}")"

  BAZEL_GEN_DRY_RUN="${dry_run}"
  bazel_gen_prepare_target_dir "${target_dir}" "${force}"

  export BAZEL_GEN_TMPL_APP_NAME="${app_name}"
  export BAZEL_GEN_TMPL_APP_SLUG
  BAZEL_GEN_TMPL_APP_SLUG="$(bazel_gen_slug_to_identifier "${app_name}")"
  export BAZEL_GEN_TMPL_MODULE_NAME
  BAZEL_GEN_TMPL_MODULE_NAME="$(bazel_gen_module_name_from_app "${app_name}")"
  export BAZEL_GEN_TMPL_PACKAGE="${package_name}"
  export BAZEL_GEN_TMPL_PACKAGE_PATH
  BAZEL_GEN_TMPL_PACKAGE_PATH="$(bazel_gen_package_path "${package_name}")"
  export BAZEL_GEN_TMPL_SCALA_VERSION="${scala_version}"
  export BAZEL_GEN_TMPL_RULES_SCALA_VERSION="${rules_scala_version}"
  export BAZEL_GEN_TMPL_YEAR
  BAZEL_GEN_TMPL_YEAR="$(date +%Y)"

  local template_layer
  while IFS= read -r template_layer; do
    [ -n "${template_layer}" ] || continue
    bazel_gen_render_template_dir "${template_layer}" "${target_dir}"
  done <<< "${template_layers}"

  if [ "${dry_run}" -eq 1 ]; then
    bazel_gen_info "dry-run complete for ${target_dir}"
    return 0
  fi

  bazel_gen_info "Generated ${language} ${template} project: ${target_dir}"
  bazel_gen_info "Next steps:"
  bazel_gen_info "  cd ${target_dir}"
  bazel_gen_info "  bazel run //:app"
}
