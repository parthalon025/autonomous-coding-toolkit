# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.0.x   | Yes       |
| < 1.0   | No        |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

1. **Do not** open a public issue
2. Email parthalon025@gmail.com with:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
3. You will receive a response within 48 hours

## Scope

This toolkit executes shell commands as part of its quality gate pipeline. Security considerations:

- **`eval` usage:** PRD acceptance criteria use `eval` to run shell commands. Only run PRDs you trust.
- **Headless execution:** `run-plan.sh` executes `claude -p` with plan content. Only run plans from trusted sources.
- **Ollama integration:** `auto-compound.sh` sends report content to a local Ollama instance. No data leaves your machine.
- **Telegram notifications:** Optional. Credentials read from `~/.env`. Never logged or committed.
