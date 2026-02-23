# Research: Bash Expert Claude Code Agent

**Date:** 2026-02-23
**Status:** Complete
**Confidence:** High on tooling landscape and rules; High on agent structure (strong existing reference from 0xfurai)
**Cynefin domain:** Complicated — knowable with synthesis of existing patterns

---

## BLUF

A bash expert agent for this toolkit should be built as a **review-mode Claude Code subagent** that wraps the same pattern as `python-expert.md`. The 0xfurai `bash-expert.md` agent is the strongest reference available — its rule set is well-synthesized from ShellCheck, Google Shell Style Guide, and BashPitfalls. The agent's value-add over raw ShellCheck is contextual judgment: detecting architectural anti-patterns (silent failure, unsafe temp handling, injection vectors) that static analysis misses. Build as `.claude/agents/bash-expert.md` with tools `Read, Grep, Glob, Bash`.

**Recommended structure:** Focus area checklist (20 rules) → scan workflow (grep patterns) → output format (findings by severity). Use `model: sonnet` — judgment is needed but not at opus depth for most script review.

---

## Section 1: Claude Code Custom Agents for Bash/Shell

### Sources

- [0xfurai/claude-code-subagents](https://github.com/0xfurai/claude-code-subagents) — 100+ production subagents; contains `bash-expert.md`
- [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents) — 100+ subagents; no bash-specific agent, has `devops-engineer.md`
- [wshobson/agents](https://github.com/wshobson/agents) — 112 agents in 72 plugins; DevOps/infrastructure category present but prompts not publicly inspectable
- [Anthropic subagent docs](https://code.claude.com/docs/en/sub-agents) — official YAML frontmatter schema

### Key Findings

**0xfurai bash-expert.md — Best existing reference.**

Full frontmatter and system prompt retrieved:

```yaml
---
name: bash-expert
description: Master of defensive Bash scripting for production automation, CI/CD
  pipelines, and system utilities. Expert in safe, portable, and testable shell scripts.
model: claude-sonnet-4-20250514
---
```

Focus areas it claims:
- Defensive programming with strict error handling
- POSIX compliance and cross-platform portability
- Safe argument parsing and input validation
- Robust file operations and temporary resource management
- Process orchestration and pipeline safety
- Production-grade logging and error reporting
- Comprehensive testing with Bats framework
- Static analysis with ShellCheck and formatting with shfmt

Approach rules (verbatim, these are the operational patterns):
- Always use strict mode with `set -Eeuo pipefail` and proper error trapping
- Quote all variable expansions to prevent word splitting and globbing
- Prefer arrays over unsafe `for f in $(ls)` patterns
- Use `[[ ]]` for Bash conditionals, fall back to `[ ]` for POSIX compliance
- Implement comprehensive argument parsing with `getopts` and usage functions
- Create temp files/dirs safely with `mktemp` and cleanup traps
- Prefer `printf` over `echo` for predictable output
- Use `$()` instead of backticks
- Use `shopt -s inherit_errexit` for better error propagation in Bash 4.4+
- Use `IFS=$'\n\t'` to prevent unwanted word splitting on spaces
- Validate inputs with `: "${VAR:?message}"` for required env vars
- End option parsing with `--` and use `rm -rf -- "$dir"` for safe ops
- Support `--trace` with `set -x` opt-in for debugging
- Use `xargs -0` with NUL boundaries for safe subprocess orchestration
- Use `readarray`/`mapfile` for safe array population from command output
- Implement reliable script directory detection: `SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"`
- Use NUL-safe patterns: `find -print0 | while IFS= read -r -d '' file; do ...; done`

Quality checklist (what it outputs):
- Scripts pass ShellCheck with minimal suppressions
- Formatted with shfmt `-i 2 -ci -bn -sr -kp`
- Bats test coverage including edge cases
- All variable expansions quoted
- Error handling covers all failure modes with meaningful messages
- Temp resources cleaned up with EXIT traps
- `--help` and clear usage information
- Input validation prevents injection attacks
- Portable across Linux and macOS
- Performance adequate for expected workloads

Advanced techniques it references:
- Error context via `trap 'echo "Error at line $LINENO: exit $?" >&2' ERR`
- Safe temp: `trap 'rm -rf "$tmpdir"' EXIT; tmpdir=$(mktemp -d)`
- Version checking: `(( BASH_VERSINFO[0] >= 5 ))` before modern features
- Binary-safe arrays: `readarray -d '' files < <(find . -print0)`
- Function return via `declare -g result` for complex data

**What it does well:** Operational specificity. Every rule is a concrete pattern, not advice. References the right authoritative sources. Correctly identifies ShellCheck + shfmt + Bats as the toolchain.

**What it lacks:** No project-specific scan patterns, no grep-based detection workflow, no severity classification of rules. The description is too generic — "production automation, CI/CD pipelines" will cause it to be invoked for too broad a set of tasks.

**VoltAgent devops-engineer.md — Generic, not adopting.**

The devops-engineer agent covers container orchestration, Kubernetes, cloud IaC, CI/CD pipeline design — scope is too broad and not bash-specific. Checklist-driven but no concrete bash patterns. Not adopting.

**Structural pattern (adopted from both sources):**

```yaml
---
name: bash-expert
description: "Use this agent when reviewing, writing, or debugging bash/shell scripts.
  Triggers on: script creation, CI shell steps, hook scripts, systemd ExecStart lines,
  Makefile shell targets, and any .sh file review."
tools: Read, Grep, Glob, Bash
model: sonnet
---
```

Description specificity matters: the description field drives automatic dispatch. Too broad = false invocations. The description above names concrete trigger contexts.

---

## Section 2: Bash Code Review Bots and Automated Reviewers

### Sources

- [reviewdog/reviewdog](https://github.com/reviewdog/reviewdog) — Automated code review tool, integrates with any analysis tool
- [reviewdog/action-shellcheck](https://github.com/reviewdog/action-shellcheck) — ShellCheck as GitHub Actions PR review
- [Microsoft Engineering Playbook — Bash Code Reviews](https://microsoft.github.io/code-with-engineering-playbook/code-reviews/recipes/bash/)
- [qiniu/reviewbot](https://github.com/qiniu/reviewbot) — AI-powered self-hosted review

### Key Findings

**reviewdog/action-shellcheck — Primary CI integration pattern.**

Configuration options:
- `shellcheck_flags: --external-sources` (default) — follows sourced files
- `level`: info | warning | error — controls PR comment severity threshold
- `pattern: "*.sh"` — extend to `*.bash` and files with shebangs via `check_all_files_with_shebangs: true`
- `fail_level: error` — only block PRs on errors, warnings annotate only
- `reporter: github-pr-review` — inline PR comments with links to ShellCheck wiki

Recommended `.github/workflows/shellcheck.yml` pattern:
```yaml
permissions:
  contents: read
  pull-requests: write
  checks: write

- uses: reviewdog/action-shellcheck@v1
  with:
    shellcheck_flags: "--external-sources --enable=all"
    reporter: github-pr-review
    fail_level: error
    check_all_files_with_shebangs: true
```

**What to adopt:** The `--enable=all` flag activates ShellCheck's optional checks (not on by default). Worth enabling in the agent's quality checklist.

**Microsoft Engineering Playbook — Review checklist source.**

Checklist items extracted:
- Does the code pass ShellCheck?
- Does the code follow the Google Shell Style Guide?
- Is `set -o errexit`, `set -o nounset`, `set -o pipefail` present?
- Are all variables quoted?
- Are temporary files cleaned up?
- Are error messages going to stderr?
- Are return codes checked after unpiped commands?

**What to adopt:** The playbook's review checklist maps directly to what the agent should emit as findings. Use these as the severity-HIGH category.

---

## Section 3: Shell Script Best Practices in CI

### Sources

- [codica2/script-best-practices](https://github.com/codica2/script-best-practices) — Clean-code-influenced bash rules
- [ralish/bash-script-template](https://github.com/ralish/bash-script-template) — Production template with `set -eu`, `parse_params()`, `main()`
- [SixArm/unix-shell-script-tactics](https://github.com/SixArm/unix-shell-script-tactics) — Comprehensive tactics reference
- [gist: Shell scripting best practices](https://gist.github.com/quangkeu95/31b4b7a7a73cb7543962773b5d0de9ee)

### Key Findings

**ralish/bash-script-template — Structural template worth adopting.**

Patterns:
- `set -e` (errexit) + `set -u` (nounset) at minimum
- `parse_params()` function separates argument parsing from business logic
- `script_usage()` heredoc for help text
- Modular structure: `source.sh` (stable library functions) + `script.sh` (customizable logic) + `build.sh` (combine)
- `main()` called at end of file — enables sourcing for testing

**SixArm/unix-shell-script-tactics — High density of specific patterns.**

Key tactics extracted:
- `printf` over `echo` — predictable behavior across shells
- `trap trap_exit EXIT` — guaranteed cleanup
- `mktemp` for temp files — never predictable names
- `find -print0 | xargs -0` — NUL-safe file operations
- Follow XDG base dirs: `$XDG_DATA_HOME`, `$XDG_CONFIG_HOME`, `$XDG_CACHE_HOME`
- Semantic versioning for scripts with `--version` flag
- `${VAR:?error}` for required variable validation
- `set -x` then `set +x` (without logging the disable) for targeted trace
- Boolean values: use `true`/`false` commands, not 0/1
- `$()` not backticks — readability and nesting
- `realpath` or `cd + $BASH_SOURCE` for script directory detection
- UTC + ISO8601 for timestamps: `$(date -u +%Y-%m-%dT%H:%M:%SZ)`
- Respect `NO_COLOR` and `TERM=dumb` in color output

**codica2/script-best-practices — Clean code application to bash.**

Adds:
- `readonly` for static variables — enforces immutability
- `local` for all function variables — prevents scope leakage
- Never hardcode credentials — use `$ENV_VAR` or external vaults
- `.sh`/`.bash` extension only for sourceable libraries, not executables
- `$HOME`/`$PWD` over `~` in scripts — tilde expansion not always reliable
- `[[ ]]` over `[ ]` — avoids POSIX portability at the cost of reliability

**What to adopt:** The combination of `ralish` structure + `SixArm` tactics gives a complete defensive pattern vocabulary. The agent should check for violations of the top-20 highest-frequency items.

---

## Section 4: ShellCheck — Rule Configuration and Key Checks

### Sources

- [koalaman/shellcheck](https://github.com/koalaman/shellcheck) — Primary static analysis tool
- [shellcheck.net/wiki](https://www.shellcheck.net/wiki/) — Full rule documentation
- [shellcheck.1.md](https://github.com/koalaman/shellcheck/blob/master/shellcheck.1.md) — Man page with all flags

### Key Rules by Category

**Quoting (highest frequency violations):**
- SC2086 — Double quote variable to prevent globbing/word splitting: `$var` → `"$var"`
- SC2046 — Quote command substitution to prevent word splitting: `$(cmd)` → `"$(cmd)"`
- SC2048 — Use `"$@"` not `$*` when passing all arguments
- SC2206 — Quote to prevent splitting: use array assignment instead

**Command substitution:**
- SC2006 — Use `$(...)` not backtick notation
- SC2005 — Useless `echo`: `echo $(cmd)` → just `cmd` or `printf '%s\n' "$(cmd)"`

**Conditional expressions:**
- SC2166 — Prefer `[ p ] && [ q ]` over `[ p -a q ]` in `[ ]`
- SC2039 — In POSIX sh, `[[ ]]` is undefined behavior
- SC2015 — `A && B || C` is not if-then-else; use proper `if/then/else`

**Loops and iteration:**
- SC2045 — Iterating over `ls` output: use `for f in ./*` instead
- SC2044 — `for f in $(find ...)`: use `find -exec` or process substitution
- SC2043 — Loop only runs once; check for missing glob or array

**Error handling:**
- SC2164 — Use `cd ... || exit` to handle failure
- SC2181 — Check exit code directly: `if cmd; then` not `cmd; if [ $? -eq 0 ]`
- SC2317 — Command appears unreachable after `exit`/`return`

**Variable usage:**
- SC2034 — Unused variable (often a typo)
- SC2155 — Declare and assign separately: `local var; var=$(cmd)` — masks exit codes
- SC2030/SC2031 — Variable modified in subshell not visible to parent

**Security-adjacent:**
- SC2094 — Make sure not to read and write the same file in the same pipeline
- SC2235 — Use `{ ..; }` or `(..)` to group conditions
- SC1090/SC1091 — Source file not found (use `--external-sources` to follow them)

**Optional checks (enabled with `--enable=all`):**
- `avoid-nullary-conditions` — `[[ -n $var ]]` over `[[ $var ]]`
- `check-extra-masked-returns` — detect masked return codes
- `check-set-e-suppressed` — warn where `set -e` is inadvertently suppressed
- `deprecate-which` — use `command -v` over `which`

**Configuration (`.shellcheckrc`):**
```ini
enable=all
external-sources=true
shell=bash
```

**What to adopt:** The agent should explicitly reference the `enable=all` flag and recommend `.shellcheckrc` in projects. The top-priority rules for manual review (because ShellCheck catches them mechanically but engineers override them without understanding): SC2155 (masked exit code on local+assign), SC2030/SC2031 (subshell variable visibility), SC2015 (false if-then-else via `&&/||`).

---

## Section 5: Google Shell Style Guide

### Source

- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- [GitHub source](https://github.com/google/styleguide/blob/gh-pages/shellguide.md)

### Key Rules

**When to use shell (scope gate):**
- Scripts > 100 lines or with non-trivial control flow: rewrite in Python
- Mostly calling other utilities with little data manipulation: shell is appropriate
- All executables must be `#!/bin/bash` — no other shell

**File conventions:**
- Libraries: `.sh` extension, non-executable
- Executables: no extension (or `.sh` if deployment requires it)
- Never set SUID/SGID on shell scripts

**Error handling:**
- All error messages to STDERR (not stdout):
  ```bash
  err() { echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2; }
  ```
- Check return values: use `if cmd; then` or `cmd || { err "failed"; exit 1; }`

**Variable naming:**
- Functions and local variables: `lowercase_underscore`
- Constants and environment exports: `UPPER_CASE`
- Local variables: declare with `local`

**Function structure:**
- All function variables: `local`
- Functions with globals, args, outputs, or return values: require header comment
- Scripts with multiple functions: require `main()` called at file end

**Formatting:**
- Indentation: 2 spaces (never tabs outside heredocs)
- Line length: 80 chars max
- `; then` and `; do` on same line as `if`/`for`/`while`

**Conditionals:**
- Prefer `[[ ]]` over `[ ]` — more predictable
- Numeric comparisons: `(( ))` not `[[ ]]`
- Test strings: always quote: `[[ "${my_var}" == "some_string" ]]`

**Arrays:**
- Use arrays for lists and command arguments (not space-delimited strings)
- Never use arrays for complex data structures — use Python instead

**Prohibited:**
- `eval` — mangles input, complicates variable assignment
- Aliases in scripts — use functions
- Wildcard without path prefix — always use `./` prefix

**What to adopt:** The scope gate ("when to use shell" rule) is valuable for the agent to surface when reviewing a script. If it exceeds 100 lines with complex control flow, the agent should flag it. The `err()` function pattern is the standard to recommend.

---

## Section 6: BashPitfalls — Wooledge Wiki

### Source

- [BashPitfalls — mywiki.wooledge.org](http://mywiki.wooledge.org/BashPitfalls)

### Top Pitfalls by Impact

These are the patterns most likely to cause silent bugs in production. Ordered by consequence severity:

**Silent data corruption / wrong results:**
1. `for f in $(ls *.mp3)` — word splitting on filenames with spaces; use `for f in ./*.mp3`
2. `cmd1 && cmd2 || cmd3` — not if-then-else; cmd3 runs if cmd2 fails
3. `somecmd 2>&1 >>logfile` — wrong order; should be `>>logfile 2>&1`
4. `[[ $foo = $bar ]]` — unquoted RHS does pattern matching; quote for equality: `[[ $foo = "$bar" ]]`
5. `grep foo bar | while read; do ((count++)); done` — counter modified in subshell, invisible to parent

**Resource / file safety:**
6. `cat file | sed s/foo/bar/ > file` — reads and writes same file via pipeline; data loss; use temp file
7. `cp $file $target` — unquoted; breaks on spaces; use `cp -- "$file" "$target"`
8. `cd /foo; bar` — cd failure not checked; use `cd /foo && bar` or `cd /foo || exit 1`

**Array / variable safety:**
9. `local var=$(cmd)` — `local` swallows exit code; declare separately: `local var; var=$(cmd)`
10. `hosts=( $(aws ...) )` — unsafe array population; use `readarray -t hosts < <(aws ...)`
11. `for arg in $*` — loses quoting; use `for arg in "$@"`
12. `OIFS="$IFS"; ...; IFS="$OIFS"` — use `local IFS` in functions instead

**Arithmetic / numeric:**
13. `[[ $foo > 7 ]]` — string comparison; use `(( foo > 7 ))`
14. `for i in {1..$n}` — brace expansion doesn't work with variables; use `for ((i=1; i<=n; i++))`

**Signal / environment:**
15. `export CDPATH=.:~/myProject` — never export CDPATH; causes surprising behavior in subshells
16. `find . -exec sh -c 'echo {}'` — injection via filename; separate: `sh -c 'echo "$1"' x {}`
17. `sudo mycmd > /myfile` — redirection runs as user not root; use `sudo sh -c 'mycmd > /myfile'`

**What to adopt:** Pitfalls 1, 2, 3, 6, 7, 8, 9 are the highest-yield grep targets for a detection scan. The agent should grep for these patterns explicitly, not rely on the user to run ShellCheck separately.

---

## Synthesis: Best Patterns to Adopt

### Priority 1 — Blocking Issues (agent must flag, high severity)

These patterns cause silent failures, data corruption, or security vulnerabilities:

| Pattern | Detection grep | Fix |
|---------|---------------|-----|
| Missing strict mode | `^#!/` without `set -Eeuo pipefail` nearby | Add to script header |
| Unquoted variable expansion | `\$[a-zA-Z_]` outside quotes (not in `[[ ]]`) | Quote: `"$var"` |
| `local var=$(cmd)` | `local [a-z_]+=\$\(` | `local var; var=$(cmd)` |
| `cd` without error check | `cd ` not followed by `&&` or `\|\|` | `cd /path || exit 1` |
| `for f in $(ls` | `for .* in \$\(ls` | `for f in ./*` |
| Same-file pipe read/write | `> file` after `cat file \|` or `< file` | Use temp file + mv |
| `2>&1 >>` order | `2>&1 >>` | Reverse to `>>file 2>&1` |
| `eval` usage | `\beval\b` | Replace with named variable or array |
| `&&` / `\|\|` as if-else | `\w && .* \|\| ` | Use proper `if/then/else` |

### Priority 2 — Quality Issues (agent should flag, medium severity)

These patterns reduce reliability and maintainability:

| Pattern | Detection | Fix |
|---------|-----------|-----|
| Missing `mktemp` for temp files | `/tmp/` literal in script | `tmpfile=$(mktemp)` + trap |
| Missing EXIT trap | `mktemp` without `trap ... EXIT` | Add `trap 'rm -rf "$tmpdir"' EXIT` |
| Backtick command substitution | `` ` `` | Use `$()` |
| `echo` for data output | `^echo \$` | `printf '%s\n' "$var"` |
| Hardcoded credentials | `(password\|token\|secret\|key)=` | Use env vars |
| Missing `--` before args | `rm -rf \$` | `rm -rf -- "$var"` |
| `$*` instead of `"$@"` | `\$\*` | `"$@"` |
| Arithmetic with `[[ ]]` | `\[\[ .* [><] [0-9]` | Use `(( ))` |
| `for f in $(find` | `for .* in \$\(find` | `find -print0 \| while IFS= read -r -d ''` |
| Missing `local` in functions | `function` body without `local` | Declare all function vars with `local` |

### Priority 3 — Style (agent notes, low severity)

| Pattern | Rule |
|---------|------|
| No `main()` function | Add for any script >30 lines |
| Error messages to stdout | Redirect to `>&2` |
| No `--help` flag | Add usage function |
| No `.shellcheckrc` | Create with `enable=all` |
| UPPERCASE for local vars | Rename to `lowercase_underscore` |
| 100+ line script with complex logic | Flag: consider Python rewrite |

---

## Recommended Agent Structure

### File: `.claude/agents/bash-expert.md`

```yaml
---
name: bash-expert
description: "Use this agent when reviewing, writing, or debugging bash or shell
  scripts. Invoke for: .sh files, CI pipeline shell steps, hook scripts, systemd
  ExecStart shell commands, Makefile shell targets, and heredoc-heavy scripts. Do
  not invoke for Python, Ruby, or other scripted languages."
tools: Read, Grep, Glob, Bash
model: sonnet
---
```

**System prompt structure:**

1. **Role statement** — Expert in defensive bash for production automation and CI/CD. Canonical references: Google Shell Style Guide, BashPitfalls, ShellCheck wiki.

2. **Scan workflow** — When invoked to review, run in order:
   - Read the target file(s)
   - Grep for Priority 1 blocking patterns (from synthesis table above)
   - Grep for Priority 2 quality patterns
   - Check for missing tooling configuration (`.shellcheckrc`, shfmt config)
   - Run `shellcheck --enable=all --external-sources <file>` if Bash tool available
   - Check scope: is the script > 100 lines with complex control flow?

3. **Output format** — Structured finding report:
   ```
   BLOCKING (must fix before merge):
   - Line 12: Unquoted variable $USER_INPUT — SC2086
   - Line 34: Missing error check on cd — BashPitfalls #19

   QUALITY (should fix):
   - Line 8: Backtick substitution; use $() instead — SC2006
   - No EXIT trap for temp files created at line 45

   STYLE (consider):
   - Script exceeds 100 lines with subprocess orchestration; evaluate Python rewrite
   - Missing --help flag

   TOOLING:
   - No .shellcheckrc found; recommend: enable=all, external-sources=true
   ```

4. **Generation mode** — When writing new scripts, apply:
   - Header: `#!/usr/bin/env bash` + `set -Eeuo pipefail`
   - `IFS=$'\n\t'` after strict mode
   - `SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"`
   - Error logging function: `err() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >&2; }`
   - `die()` function: `die() { err "$@"; exit 1; }`
   - `trap 'rm -rf "${tmpdir:-}"' EXIT` before any `mktemp` calls
   - `main()` function called at end
   - `--help` flag via `usage()` heredoc
   - All function variables declared `local`

5. **Essential toolchain** — Reference these in generated configs:
   - ShellCheck: `shellcheck --enable=all --external-sources`
   - shfmt: `shfmt -i 2 -ci -bn -sr -kp`
   - Bats: for unit testing shell functions
   - reviewdog/action-shellcheck: for CI PR integration

6. **Scope gate** — Always check: if the script exceeds 100 lines with complex control flow, non-trivial data manipulation, or object-like structures, flag it explicitly: "Consider Python rewrite (Google Shell Style Guide threshold)."

### Model selection rationale

`sonnet` is correct for this agent. Bash review requires:
- Pattern matching against known anti-patterns (grep-level reasoning)
- Contextual judgment on whether a pattern is actually risky in context
- Code generation following established rules

It does not require deep architectural reasoning (that's `opus` territory). Haiku is insufficient — the pattern vocabulary is large and the contextual judgment for edge cases (e.g., "is this eval safe?") needs mid-tier reasoning.

---

## What to Adopt vs. Skip

| Source | Adopt | Skip |
|--------|-------|------|
| 0xfurai bash-expert.md | All approach rules verbatim; quality checklist; advanced techniques | Description (too generic) |
| Google Shell Style Guide | Scope gate (100-line rule); `err()` pattern; naming conventions; prohibited list | POSIX portability rules (Justin's stack is bash-only) |
| BashPitfalls | Top 17 pitfalls as grep detection patterns | Obscure edge cases (#38-#65) — add only if they appear in codebase |
| ShellCheck | `enable=all`; `.shellcheckrc`; SC2155, SC2030/31, SC2015 as manual focus | None — use all |
| ralish/bash-script-template | `main()` pattern; `parse_params()`; modular structure | Build system (overkill for this stack) |
| SixArm/unix-shell-script-tactics | XDG dirs; UTC timestamps; `NO_COLOR`; `${VAR:?}` | PostgreSQL helpers; platform-specific macOS tactics |
| reviewdog/action-shellcheck | `--enable=all`; inline PR comments; `check_all_files_with_shebangs` | Not applicable (Justin's repos don't use GitHub PRs for shell review) |
| VoltAgent devops-engineer.md | Nothing bash-specific | Entire agent — wrong scope |
| Microsoft Engineering Playbook | The 7-item checklist as the agent's severity-HIGH category | Nothing |

---

## Related Files

- Sister research: `docs/plans/2026-02-23-research-python-expert-agent.md`
- Existing agents: `~/.claude/agents/lesson-scanner.md`, `~/.claude/agents/security-reviewer.md`
- Security reviewer overlap: bash security hardening (injection, credential exposure) partially covered by `security-reviewer.md` — coordinate scopes to avoid duplicate findings

---

## References

- [0xfurai/claude-code-subagents — bash-expert.md](https://github.com/0xfurai/claude-code-subagents)
- [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents)
- [wshobson/agents](https://github.com/wshobson/agents)
- [reviewdog/action-shellcheck](https://github.com/reviewdog/action-shellcheck)
- [reviewdog/reviewdog](https://github.com/reviewdog/reviewdog)
- [koalaman/shellcheck](https://github.com/koalaman/shellcheck)
- [ShellCheck wiki](https://www.shellcheck.net/wiki/)
- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- [BashPitfalls — Wooledge Wiki](http://mywiki.wooledge.org/BashPitfalls)
- [Microsoft Engineering Playbook — Bash Code Reviews](https://microsoft.github.io/code-with-engineering-playbook/code-reviews/recipes/bash/)
- [ralish/bash-script-template](https://github.com/ralish/bash-script-template)
- [SixArm/unix-shell-script-tactics](https://github.com/SixArm/unix-shell-script-tactics)
- [codica2/script-best-practices](https://github.com/codica2/script-best-practices)
- [Anthropic subagent docs](https://code.claude.com/docs/en/sub-agents)
