# bazel-gen

`bazel-gen` is a Bash CLI for scaffolding Bazel projects from filesystem templates.

## Quick start

```bash
./bin/bazel-gen new scala console my-app
./bin/bazel-gen new java console my-java-app
```

## Install globally

Install from this repo:

```bash
./scripts/install.sh
```

This installs:

- CLI payload to `~/.local/share/bazel-gen/app`
- launcher to `~/.local/bin/bazel-gen`
- PATH block to your shell rc files (`.zshrc`/`.zprofile` or `.bashrc`/`.bash_profile`, plus `.profile`)
- install state file at `~/.bazel-gen/install-state`

Common install options:

- `--install-base <path>`
- `--bin-dir <path>`
- `--state-file <path>`
- `--no-path-update`
- `--dry-run`

Uninstall and wipe traces:

```bash
./scripts/uninstall.sh
```

`uninstall.sh` removes:

- launcher (`~/.local/bin/bazel-gen` by default)
- installed payload (`~/.local/share/bazel-gen/app` by default)
- PATH block injected by installer
- `~/.bazel-gen` directory (including custom templates and install state)

Common uninstall options:

- `--install-base <path>`
- `--bin-dir <path>`
- `--state-file <path>`
- `--rc-file <path>`
- `--dry-run`

## Commands

```bash
bazel-gen new <language> <template> <app-name> [options]
bazel-gen template init <language> <template-name> [options]
```

`gen` aliases are also supported:

```bash
bazel-gen gen new scala console my-app
bazel-gen gen template init scala console-custom --from scala/console
```

## Built-in templates

- `scala/console`
- `java/console`

## Template-specific options

Template options are defined by each template in `template.manifest`.

List all templates:

```bash
bazel-gen new --list
```

List options for a specific template:

```bash
bazel-gen new --list-options scala console
```

Common generation options:

- `--dest <path>`
- `--force`
- `--dry-run`

## Template system

Templates are loaded in this order:

1. `$BAZEL_GEN_TEMPLATE_DIR/<language>/<template>`
2. `~/.bazel-gen/templates/<language>/<template>`
3. Built-in templates at `templates/<language>/<template>`

Lower-priority templates are rendered first and higher-priority templates overlay them file-by-file.

### Manifest format

Manifest file: `template.manifest`

```text
description|A short template description
option|<key>|<flag>|<type>|<default>|<required|optional>|<description>
```

Supported option types:

- `string`
- `version` (`x.y.z`)
- `int`
- `bool`

Example:

```text
description|Runnable custom template
option|package|--package|string|com.example.__APP_SLUG__|optional|Base package name
option|java_version|--java-version|string|21|optional|Java language version
```

### Placeholders

Built-in placeholders:

- `__APP_NAME__`
- `__APP_SLUG__`
- `__MODULE_NAME__`
- `__PACKAGE__`
- `__PACKAGE_PATH__`
- `__SCALA_VERSION__`
- `__RULES_SCALA_VERSION__`
- `__JAVA_VERSION__`
- `__RULES_JAVA_VERSION__`
- `__YEAR__`

Manifest option placeholders:

- `__OPT_<OPTION_KEY_UPPERCASE>__`

Example: `option|java_version|--java-version|...` becomes `__OPT_JAVA_VERSION__`.

## Bootstrapping custom templates

Create a local template skeleton:

```bash
bazel-gen template init scala service
```

Clone from an existing template:

```bash
bazel-gen template init scala service --from scala/console
```
