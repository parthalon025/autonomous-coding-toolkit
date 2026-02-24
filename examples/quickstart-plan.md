# Quickstart Plan: Hello World with Quality Gate

A minimal 2-batch plan demonstrating the toolkit's core loop: write test → implement → quality gate → next batch.

## Batch 1: Setup and first test

### Task 1: Create project structure

Create the following files:

- `src/hello.sh` — a bash script that prints "Hello, World!"
- `tests/test-hello.sh` — a test that verifies the output

```bash
# src/hello.sh
#!/usr/bin/env bash
echo "Hello, World!"
```

```bash
# tests/test-hello.sh
#!/usr/bin/env bash
set -euo pipefail

output=$(bash src/hello.sh)
if [[ "$output" == "Hello, World!" ]]; then
    echo "PASS: hello output correct"
else
    echo "FAIL: expected 'Hello, World!', got '$output'"
    exit 1
fi
```

Make both executable: `chmod +x src/hello.sh tests/test-hello.sh`

Run: `bash tests/test-hello.sh` — expect PASS.

## Batch 2: Add parameterized greeting

### Task 2: Accept a name argument

Update `src/hello.sh` to accept an optional name argument:
- `bash src/hello.sh` → "Hello, World!"
- `bash src/hello.sh Alice` → "Hello, Alice!"

### Task 3: Add test for parameterized greeting

Add a second test case to `tests/test-hello.sh` that verifies `bash src/hello.sh Alice` outputs "Hello, Alice!".

Run: `bash tests/test-hello.sh` — expect both PASS.

## Running This Plan

```bash
# Headless (fully autonomous)
scripts/run-plan.sh examples/quickstart-plan.md

# In-session (with review between batches)
/run-plan examples/quickstart-plan.md

# Resume if interrupted
scripts/run-plan.sh --resume
```
