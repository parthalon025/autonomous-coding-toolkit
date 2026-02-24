# Bash Policies

Positive patterns for shell scripts. Derived from lessons #51, #58, #74, #75.

## Strict Mode

**Start every script with `set -euo pipefail`.**
Without strict mode, failed commands are silently ignored and undefined variables expand to empty strings.

```bash
#!/usr/bin/env bash
set -euo pipefail
```

## Quote Variables

**Always quote variable expansions.**
Unquoted variables undergo word splitting and glob expansion, breaking on filespace names and special characters.

```bash
# Pattern: double-quote all expansions
cp "$source_file" "$dest_dir/"
if [[ -f "$config_path" ]]; then
```

## Subshell for Directory Changes

**Use a subshell when `cd` is temporary.**
Forgetting to `cd` back breaks all subsequent relative paths. A subshell automatically restores the working directory.

```bash
# Pattern: subshell isolates cd
(
    cd "$build_dir"
    make install
)
# Back to original directory automatically
```

## Temp File Cleanup

**Use `trap` to clean up temporary files.**
Early exits from `set -e` skip manual cleanup. A trap ensures cleanup runs regardless of exit path.

```bash
tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

# Use $tmpfile safely — cleanup guaranteed
```

## Redirect Then Move

**Write to a temp file, then `mv` to the target.**
Writing directly to the target risks corruption on failure — a partial write leaves an invalid file. `mv` is atomic on the same filesystem.

```bash
# Pattern: write to tmp, then atomic move
jq '.count += 1' "$state_file" > "$tmp" && mv "$tmp" "$state_file"
```

## Arithmetic Evaluation

**Use `$(( ))` for arithmetic, not bare expressions.**
Shell arithmetic needs explicit evaluation context. Without it, expressions are treated as strings.

```bash
# Pattern: explicit arithmetic
delta=$(( end_time - start_time ))
if [[ $count -gt 0 ]]; then
```
