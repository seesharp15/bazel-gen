#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${ROOT_DIR}/bin/bazel-gen"

fail() {
  printf "FAIL: %s\n" "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  printf "%s" "${haystack}" | grep -F "${needle}" >/dev/null || fail "expected output to contain: ${needle}"
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
  assert_contains "${output}" "console"
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

test_generate_scaffold() {
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

run() {
  test_help
  test_list_templates
  test_dry_run
  test_generate_scaffold
  test_scala_version_guardrail
  test_custom_template_override
  printf "All tests passed\n"
}

run "$@"
