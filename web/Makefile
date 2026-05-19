# Convenience targets for the tgt-web package. Top-level Makefile
# delegates to these via `make -C web …`.

.PHONY: install-dev uninstall test lint clean

install-dev:
	@command -v pipx >/dev/null || { echo "pipx not installed (apt install pipx)"; exit 1; }
	@pipx install --force -e .
	@echo "✓ tgt-web installed (editable) — open a new fish shell to pick up the wrapper"

uninstall:
	@pipx uninstall tgt-web

test:
	@pytest -q

lint:
	@python -m compileall -q tgt_web tests

clean:
	@rm -rf build dist *.egg-info .pytest_cache
	@find . -name __pycache__ -type d -exec rm -rf {} +
