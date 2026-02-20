#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${ROOT_DIR}/bin/bazel-gen"
INSTALLER="${ROOT_DIR}/scripts/install.sh"
UNINSTALLER="${ROOT_DIR}/scripts/uninstall.sh"

fail() {
  printf "FAIL: %s\n" "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  printf "%s" "${haystack}" | grep -F -- "${needle}" >/dev/null || fail "expected output to contain: ${needle}"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if printf "%s" "${haystack}" | grep -F -- "${needle}" >/dev/null; then
    fail "expected output to NOT contain: ${needle}"
  fi
}

test_help() {
  local output
  output="$("${CLI}" new --help)"
  assert_contains "${output}" "bazel-gen new <language> <template> <app-name>"
}

test_list_templates() {
  local output
  output="$("${CLI}" new --list)"
  assert_contains "${output}" "scala"
  assert_contains "${output}" "java"
  assert_contains "${output}" "console"
}

test_list_options() {
  local output
  output="$("${CLI}" new --list-options scala console)"
  assert_contains "${output}" "--package"
  assert_contains "${output}" "--scala-version"
}

test_dry_run() {
  local tmp
  tmp="$(mktemp -d)"
  local output
  output="$("${CLI}" new scala console sample --dest "${tmp}" --dry-run)"
  assert_contains "${output}" "[dry-run] write"
  if [ -d "${tmp}/sample" ]; then
    fail "dry-run should not create target directory"
  fi
  rm -rf "${tmp}"
}

test_generate_scala_scaffold() {
  local tmp
  tmp="$(mktemp -d)"
  "${CLI}" new scala console sample --dest "${tmp}" --package com.acme.sample >/dev/null

  [ -f "${tmp}/sample/MODULE.bazel" ] || fail "MODULE.bazel not generated"
  [ -f "${tmp}/sample/BUILD.bazel" ] || fail "BUILD.bazel not generated"
  [ -f "${tmp}/sample/.bazelversion" ] || fail ".bazelversion not generated"
  [ -f "${tmp}/sample/src/main/scala/com/acme/sample/Main.scala" ] || fail "Main.scala not generated in package path"
  [ -f "${tmp}/sample/src/test/scala/com/acme/sample/MainTest.scala" ] || fail "MainTest.scala not generated in package path"

  local module_content
  module_content="$(cat "${tmp}/sample/MODULE.bazel")"
  assert_contains "${module_content}" "rules_scala"

  rm -rf "${tmp}"
}

test_generate_java_scaffold() {
  local tmp
  tmp="$(mktemp -d)"
  "${CLI}" new java console japp --dest "${tmp}" --package com.acme.japp --java-version 17 >/dev/null

  [ -f "${tmp}/japp/MODULE.bazel" ] || fail "MODULE.bazel not generated for java"
  [ -f "${tmp}/japp/BUILD.bazel" ] || fail "BUILD.bazel not generated for java"
  [ -f "${tmp}/japp/src/main/java/com/acme/japp/Main.java" ] || fail "Main.java not generated in package path"

  local bazelrc_content
  bazelrc_content="$(cat "${tmp}/japp/.bazelrc")"
  assert_contains "${bazelrc_content}" "--java_language_version=17"

  rm -rf "${tmp}"
}

test_manifest_option_placeholder_rendering() {
  local tmp
  tmp="$(mktemp -d)"
  local custom_templates="${tmp}/custom-templates"
  mkdir -p "${custom_templates}/java/greeter/src/main/java/__PACKAGE_PATH__"

  cat >"${custom_templates}/java/greeter/template.manifest" <<EOF
description|Custom greeter
option|package|--package|string|com.example.__APP_SLUG__|optional|Package
option|greeting|--greeting|string|Hello|optional|Greeting text
EOF

  cat >"${custom_templates}/java/greeter/MODULE.bazel.tmpl" <<EOF
module(name = "__MODULE_NAME__", version = "0.1.0")
EOF

  cat >"${custom_templates}/java/greeter/BUILD.bazel.tmpl" <<EOF
java_binary(
    name = "app",
    srcs = glob(["src/main/java/**/*.java"]),
    main_class = "__PACKAGE__.Main",
)
EOF

  cat >"${custom_templates}/java/greeter/src/main/java/__PACKAGE_PATH__/Main.java.tmpl" <<EOF
package __PACKAGE__;
public class Main { public static void main(String[] args) { System.out.println("__OPT_GREETING__, world"); } }
EOF

  BAZEL_GEN_TEMPLATE_DIR="${custom_templates}" "${CLI}" new java greeter appx --dest "${tmp}" --greeting "Hi" >/dev/null
  local main_content
  main_content="$(cat "${tmp}/appx/src/main/java/com/example/appx/Main.java")"
  assert_contains "${main_content}" "Hi, world"

  rm -rf "${tmp}"
}

test_scala_version_guardrail() {
  local tmp
  tmp="$(mktemp -d)"
  if "${CLI}" new scala console badver --dest "${tmp}" --scala-version 3.3.3 >/dev/null 2>&1; then
    fail "expected unsupported scala version to fail for built-in scala/console template"
  fi
  rm -rf "${tmp}"
}

test_custom_template_override() {
  local tmp
  tmp="$(mktemp -d)"
  local custom_templates="${tmp}/custom-templates"
  mkdir -p "${custom_templates}/scala/console"

  cat >"${custom_templates}/scala/console/template.meta" <<EOF
description=Custom console template
EOF

  cat >"${custom_templates}/scala/console/README.md.tmpl" <<EOF
# custom __APP_NAME__
EOF

  BAZEL_GEN_TEMPLATE_DIR="${custom_templates}" "${CLI}" new scala console appx --dest "${tmp}" >/dev/null
  [ -f "${tmp}/appx/README.md" ] || fail "custom template output missing"
  [ -f "${tmp}/appx/MODULE.bazel" ] || fail "base template files should still exist when using override"
  local readme_content
  readme_content="$(cat "${tmp}/appx/README.md")"
  assert_contains "${readme_content}" "# custom appx"

  rm -rf "${tmp}"
}

test_template_init_skeleton() {
  local tmp
  tmp="$(mktemp -d)"
  "${CLI}" template init scala mycustom --dest "${tmp}" >/dev/null
  [ -f "${tmp}/scala/mycustom/template.manifest" ] || fail "template init should create template.manifest"
  [ -f "${tmp}/scala/mycustom/README.md.tmpl" ] || fail "template init should create README.md.tmpl"
  rm -rf "${tmp}"
}

test_template_init_from_builtin() {
  local tmp
  tmp="$(mktemp -d)"
  "${CLI}" template init scala console-clone --from scala/console --dest "${tmp}" >/dev/null
  [ -f "${tmp}/scala/console-clone/MODULE.bazel.tmpl" ] || fail "template init --from should copy template files"
  [ -f "${tmp}/scala/console-clone/template.manifest" ] || fail "template init --from should copy manifest"
  rm -rf "${tmp}"
}

test_install_and_uninstall() {
  local tmp
  tmp="$(mktemp -d)"
  local test_home="${tmp}/home"
  mkdir -p "${test_home}"

  SHELL="/bin/zsh" HOME="${test_home}" "${INSTALLER}" >/dev/null

  local launcher="${test_home}/.local/bin/bazel-gen"
  local payload="${test_home}/.local/share/bazel-gen/app"
  local state_file="${test_home}/.bazel-gen/install-state"
  local zshrc="${test_home}/.zshrc"

  [ -x "${launcher}" ] || fail "installer should create executable launcher"
  [ -f "${payload}/bin/bazel-gen" ] || fail "installer should copy payload"
  [ -f "${state_file}" ] || fail "installer should create state file"
  [ -f "${zshrc}" ] || fail "installer should create zshrc when adding PATH block"

  local launcher_help
  launcher_help="$("${launcher}" --help)"
  assert_contains "${launcher_help}" "bazel-gen <command>"

  local zshrc_content
  zshrc_content="$(cat "${zshrc}")"
  assert_contains "${zshrc_content}" "# >>> bazel-gen installer >>>"

  mkdir -p "${test_home}/.bazel-gen/templates/custom/template"
  touch "${test_home}/.bazel-gen/templates/custom/template/template.manifest"

  SHELL="/bin/zsh" HOME="${test_home}" "${UNINSTALLER}" >/dev/null

  [ ! -e "${launcher}" ] || fail "uninstaller should remove launcher"
  [ ! -d "${payload}" ] || fail "uninstaller should remove payload"
  [ ! -d "${test_home}/.bazel-gen" ] || fail "uninstaller should remove ~/.bazel-gen"

  local zshrc_after
  zshrc_after="$(cat "${zshrc}")"
  assert_not_contains "${zshrc_after}" "# >>> bazel-gen installer >>>"

  rm -rf "${tmp}"
}

run() {
  test_help
  test_list_templates
  test_list_options
  test_dry_run
  test_generate_scala_scaffold
  test_generate_java_scaffold
  test_manifest_option_placeholder_rendering
  test_scala_version_guardrail
  test_custom_template_override
  test_template_init_skeleton
  test_template_init_from_builtin
  test_install_and_uninstall
  printf "All tests passed\n"
}

run "$@"
