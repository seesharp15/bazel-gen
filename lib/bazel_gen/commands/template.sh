#!/usr/bin/env bash

bazel_gen_template_usage() {
  cat <<EOF
Usage:
  bazel-gen template <subcommand> [args]
  bazel-gen gen template <subcommand> [args]

Subcommands:
  init      Bootstrap a local template directory.
  help      Show this help.

Examples:
  bazel-gen template init scala console-custom
  bazel-gen template init scala console-custom --from scala/console
  bazel-gen template init java service --dest ./local-templates
EOF
}

bazel_gen_template_init_usage() {
  cat <<EOF
Usage:
  bazel-gen template init <language> <template-name> [options]

Options:
  --from <language/template>   Copy files from an existing template as a starting point.
  --dest <path>                Template root directory (default: ~/.bazel-gen/templates).
  --force                      Allow writing into a non-empty target template directory.
  --dry-run                    Print actions without writing files.
  -h, --help                   Show this help.

Notes:
  - If --from is omitted and a built-in template exists with the same name, it is copied.
  - Files are created under <dest>/<language>/<template-name>.
EOF
}

bazel_gen_template_copy_dir() {
  local source_dir="$1"
  local target_dir="$2"
  local source_file
  while IFS= read -r -d '' source_file; do
    local relative_path
    relative_path="${source_file#${source_dir}/}"
    case "$(basename "${relative_path}")" in
      .DS_Store)
        continue
        ;;
    esac
    local destination="${target_dir}/${relative_path}"
    bazel_gen_copy_file "${source_file}" "${destination}"
    bazel_gen_set_executable_like "${source_file}" "${destination}"
  done < <(find "${source_dir}" -type f -print0)
}

bazel_gen_cmd_template_init() {
  local language=""
  local template_name=""
  local from_ref=""
  local destination_root="~/.bazel-gen/templates"
  local force=0
  local dry_run=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help)
        bazel_gen_template_init_usage
        return 0
        ;;
      --from)
        [ "$#" -ge 2 ] || bazel_gen_die "Missing value for --from"
        from_ref="$2"
        shift 2
        ;;
      --dest)
        [ "$#" -ge 2 ] || bazel_gen_die "Missing value for --dest"
        destination_root="$2"
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
      -*)
        bazel_gen_die "Unknown option for template init: $1"
        ;;
      *)
        if [ -z "${language}" ]; then
          language="$1"
        elif [ -z "${template_name}" ]; then
          template_name="$1"
        else
          bazel_gen_die "Unexpected argument: $1"
        fi
        shift
        ;;
    esac
  done

  if [ -z "${language}" ] || [ -z "${template_name}" ]; then
    bazel_gen_template_init_usage
    bazel_gen_die "Expected: bazel-gen template init <language> <template-name>"
  fi

  language="$(bazel_gen_to_lower "${language}")"
  template_name="$(bazel_gen_to_lower "${template_name}")"

  case "${language}" in
    [a-z][a-z0-9_-]*)
      ;;
    *)
      bazel_gen_die "Invalid language '${language}'"
      ;;
  esac

  case "${template_name}" in
    [a-z][a-z0-9_-]*)
      ;;
    *)
      bazel_gen_die "Invalid template name '${template_name}'"
      ;;
  esac

  destination_root="$(bazel_gen_expand_home "${destination_root}")"
  local target_template_dir
  target_template_dir="${destination_root}/${language}/${template_name}"

  local previous_dry_run="${BAZEL_GEN_DRY_RUN}"
  BAZEL_GEN_DRY_RUN="${dry_run}"
  bazel_gen_prepare_target_dir "${target_template_dir}" "${force}"

  local source_template_dir=""
  if [ -n "${from_ref}" ]; then
    local from_language="${from_ref%%/*}"
    local from_template="${from_ref#*/}"
    if [ -z "${from_language}" ] || [ -z "${from_template}" ] || [ "${from_language}" = "${from_template}" ]; then
      bazel_gen_die "Invalid --from value '${from_ref}'. Expected <language>/<template>"
    fi
    source_template_dir="$(bazel_gen_find_template "$(bazel_gen_to_lower "${from_language}")" "$(bazel_gen_to_lower "${from_template}")")" || {
      bazel_gen_die "Template not found for --from: ${from_ref}"
    }
  else
    local built_in_same
    built_in_same="${BAZEL_GEN_ROOT_DIR}/templates/${language}/${template_name}"
    if [ -d "${built_in_same}" ]; then
      source_template_dir="${built_in_same}"
    fi
  fi

  if [ -n "${source_template_dir}" ] && [ "${source_template_dir}" = "${target_template_dir}" ]; then
    bazel_gen_die "Source and destination template directories are the same: ${target_template_dir}"
  fi

  if [ -n "${source_template_dir}" ]; then
    bazel_gen_template_copy_dir "${source_template_dir}" "${target_template_dir}"
    if [ "${dry_run}" -eq 1 ]; then
      bazel_gen_info "dry-run complete for ${target_template_dir}"
    else
      bazel_gen_info "Bootstrapped template from ${source_template_dir} -> ${target_template_dir}"
    fi
    BAZEL_GEN_DRY_RUN="${previous_dry_run}"
    return 0
  fi

  local description
  description="Custom ${language}/${template_name} template"

  bazel_gen_write_file "${target_template_dir}/template.manifest" <<EOF
description|${description}
# option|key|flag|type|default|required|description
# option|package|--package|string|com.example.__APP_SLUG__|optional|Base package name
EOF

  bazel_gen_write_file "${target_template_dir}/README.md.tmpl" <<'EOF'
# __APP_NAME__

Generated from custom template `__MODULE_NAME__`.
EOF

  if [ "${dry_run}" -eq 1 ]; then
    bazel_gen_info "dry-run complete for ${target_template_dir}"
  else
    bazel_gen_info "Initialized template scaffold at ${target_template_dir}"
  fi

  BAZEL_GEN_DRY_RUN="${previous_dry_run}"
}

bazel_gen_cmd_template() {
  local subcommand="${1:-}"
  case "${subcommand}" in
    ""|-h|--help|help)
      bazel_gen_template_usage
      ;;
    init)
      shift
      bazel_gen_cmd_template_init "$@"
      ;;
    *)
      bazel_gen_die "Unknown template subcommand: ${subcommand}"
      ;;
  esac
}
