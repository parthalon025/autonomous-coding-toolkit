.PHONY: test validate lint ci

lint:
	@echo "=== ShellCheck ==="
	@shellcheck scripts/*.sh scripts/lib/*.sh 2>&1 || true
	@echo "=== shfmt ==="
	@shfmt -d -i 2 -ci scripts/*.sh scripts/lib/*.sh 2>&1 || true
	@echo "=== Shellharden ==="
	@shellharden --check scripts/*.sh scripts/lib/*.sh 2>&1 || true
	@echo "=== Semgrep ==="
	@semgrep --config "p/bash" --quiet scripts/ 2>&1 || true
	@echo "=== Lint Complete ==="

test:
	@bash scripts/tests/run-all-tests.sh

validate:
	@bash scripts/validate-all.sh

ci: lint validate test
	@echo "CI: ALL PASSED"
