# bazel-gen

`bazel-gen` is a Bash CLI for scaffolding Bazel projects from filesystem templates.

## Quick start

```bash
./bin/bazel-gen new scala console my-app
```

This creates `./my-app` with a runnable Scala app:

```bash
cd my-app
bazel run //:app
```

## Command shape

```bash
bazel-gen new <language> <template> <app-name> [options]
```

`gen new` is also supported:

```bash
bazel-gen gen new scala console my-app
```

## Options

- `--package <name>`
- `--scala-version <version>` (built-in `scala/console` currently supports `2.13.17`)
- `--rules-scala-version <version>`
- `--dest <path>`
- `--force`
- `--dry-run`
- `--list`

## Template system

Templates are loaded in this order:

1. `$BAZEL_GEN_TEMPLATE_DIR/<language>/<template>`
2. `~/.bazel-gen/templates/<language>/<template>`
3. Built-in templates at `templates/<language>/<template>`

Lower-priority templates are rendered first and higher-priority templates overlay them file-by-file.

### Built-in example

- `templates/scala/console`

### Create your own template

Create a folder like `~/.bazel-gen/templates/scala/console-web` and place files in it.
Files ending with `.tmpl` are rendered with placeholders and written without the `.tmpl` suffix.
Other files are copied as-is.

Available placeholders:

- `__APP_NAME__`
- `__APP_SLUG__`
- `__MODULE_NAME__`
- `__PACKAGE__`
- `__PACKAGE_PATH__`
- `__SCALA_VERSION__`
- `__RULES_SCALA_VERSION__`
- `__YEAR__`

Optional template metadata:

- `template.meta` with one line: `description=...`
