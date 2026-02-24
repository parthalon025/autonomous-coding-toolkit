---
id: 19
title: "systemd EnvironmentFile ignores `export` keyword"
severity: should-fix
languages: [shell]
scope: [framework:systemd]
category: silent-failures
pattern:
  type: syntactic
  regex: "EnvironmentFile="
  description: "systemd EnvironmentFile silently ignores lines with export prefix"
fix: "Use a bash wrapper (ExecStart=/bin/bash -c '. ~/.env && exec binary') or strip export from the file"
example:
  bad: |
    # ~/.env file
    export API_KEY=secret123
    export DEBUG=true

    # systemd service
    [Service]
    EnvironmentFile=~/.env
    # systemd ignores export prefix, loads nothing
  good: |
    # Either: strip export from the file
    # ~/.env
    API_KEY=secret123
    DEBUG=true

    # Or: use bash wrapper
    [Service]
    ExecStart=/bin/bash -c '. ~/.env && exec /usr/bin/myapp'
---

## Observation
A systemd service uses `EnvironmentFile=~/.env` with a `.env` file that contains `export VAR=value` syntax. The service starts without error but has empty environment variables. The `export` prefix is silently ignored by systemd's EnvironmentFile parser.

## Insight
systemd `EnvironmentFile` expects the format `KEY=value` only. The `export` keyword is shell syntax, not systemd syntax. When systemd sees `export KEY=value`, it either ignores the entire line or only parses the part after the `=`, leaving the variable unset. No error is logged — the service just runs with an incomplete environment.

## Lesson
systemd `EnvironmentFile` requires `KEY=value` format without `export`. Either: (1) maintain two files — one for shell-sourcing (with `export`) and one for systemd (without `export`), or (2) use a bash wrapper (`ExecStart=/bin/bash -c '. ~/.env && exec myapp'`) that sources the shell-format file. Never mix systemd EnvironmentFile with shell export syntax.
