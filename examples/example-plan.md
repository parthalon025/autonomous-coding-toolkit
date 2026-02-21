# Example Implementation Plan

> This is an example plan file that `run-plan.sh` can parse and execute.
> The parser looks for `## Batch N:` headers to split batches and `### Task M:` for individual tasks.

## Batch 1: Project Setup

### Task 1: Initialize project structure

Create the basic directory layout:
- `src/` — source code
- `tests/` — test files
- `pyproject.toml` with pytest configuration

### Task 2: Add configuration module

Create `src/config.py`:
- Load settings from environment variables
- Provide defaults for development
- Add `tests/test_config.py` with basic tests

## Batch 2: Core Implementation

### Task 3: Implement data parser

Create `src/parser.py`:
- Parse CSV input files into structured records
- Handle malformed rows gracefully (log + skip, don't crash)
- Add `tests/test_parser.py` covering: valid input, empty input, malformed rows

### Task 4: Implement transformer

Create `src/transformer.py`:
- Transform parsed records into output format
- Support configurable field mapping
- Add `tests/test_transformer.py`

## Batch 3: Integration and CLI

### Task 5: Wire components together

Create `src/pipeline.py`:
- Connect parser → transformer → output writer
- Add end-to-end test: CSV in → transformed output verified

### Task 6: Add CLI entry point

Create `src/cli.py`:
- Accept input file and output file arguments
- Report progress to stderr
- Add `tests/test_cli.py` testing argument parsing and error cases
