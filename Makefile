# Convenience targets; each underlying Python/Node command is also documented.
# Python uses its standard library. The JavaScript tests require no npm packages.
PYTHON ?= python3
NODE ?= node

.PHONY: build test audit verify-db package
build:
	$(PYTHON) dashboard/tools/build_queries.py
	$(PYTHON) scripts/refresh_report.py --output dashboard/report/Infrastructure_Overview.fvs

test:
	$(NODE) --test dashboard/scene/test_*.mjs
	$(PYTHON) -m unittest discover -s tests -v

audit:
	$(PYTHON) scripts/check_repository.py

verify-db:
	$(PYTHON) scripts/verify_database.py

package: audit
	$(PYTHON) scripts/package_release.py
