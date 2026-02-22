.PHONY: test validate ci

test:
	@bash scripts/tests/run-all-tests.sh

validate:
	@bash scripts/validate-all.sh

ci: validate test
	@echo "CI: ALL PASSED"
