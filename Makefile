.PHONY: dev undev install uninstall test demo demo-clean

REPO := $(shell pwd)
FISH_DIR := $(or $(XDG_CONFIG_HOME),$(HOME)/.config)/fish
FISH_FUNCTIONS := $(FISH_DIR)/functions
FISH_CONFD := $(FISH_DIR)/conf.d
FISH_COMPLETIONS := $(FISH_DIR)/completions

# Symlink-based local-development install. Edits in this repo are
# picked up immediately by new fish shells — no re-install needed.
dev:
	@mkdir -p $(FISH_FUNCTIONS) $(FISH_CONFD) $(FISH_COMPLETIONS)
	@for f in $(REPO)/functions/*.fish; do \
		ln -sf "$$f" "$(FISH_FUNCTIONS)/$$(basename $$f)"; \
	done
	@if [ -d "$(REPO)/conf.d" ]; then \
		for f in $(REPO)/conf.d/*.fish; do \
			[ -f "$$f" ] && ln -sf "$$f" "$(FISH_CONFD)/$$(basename $$f)"; \
		done; \
	fi
	@if [ -d "$(REPO)/completions" ]; then \
		for f in $(REPO)/completions/*.fish; do \
			[ -f "$$f" ] && ln -sf "$$f" "$(FISH_COMPLETIONS)/$$(basename $$f)"; \
		done; \
	fi
	@echo "✓ dev symlinks installed; open a new shell to pick them up"

# Remove the symlinks created by `make dev`. Only removes symlinks
# that point into this repo — never touches user-owned files.
undev:
	@for f in $(REPO)/functions/*.fish; do \
		t="$(FISH_FUNCTIONS)/$$(basename $$f)"; \
		[ -L "$$t" ] && [ "$$(readlink "$$t")" = "$$f" ] && rm "$$t" || true; \
	done
	@if [ -d "$(REPO)/conf.d" ]; then \
		for f in $(REPO)/conf.d/*.fish; do \
			t="$(FISH_CONFD)/$$(basename $$f)"; \
			[ -L "$$t" ] && [ "$$(readlink "$$t")" = "$$f" ] && rm "$$t" || true; \
		done; \
	fi
	@if [ -d "$(REPO)/completions" ]; then \
		for f in $(REPO)/completions/*.fish; do \
			t="$(FISH_COMPLETIONS)/$$(basename $$f)"; \
			[ -L "$$t" ] && [ "$$(readlink "$$t")" = "$$f" ] && rm "$$t" || true; \
		done; \
	fi
	@echo "✓ dev symlinks removed"

# Production install via Fisher. Copies (not symlinks) — re-run after
# changes if you're using this path for development.
install:
	@fish -c 'fisher install $(REPO)'

uninstall:
	@fish -c 'fisher remove pentest-fish-functions' || true

test:
	@fish -c 'fishtape test/test_*.fish'

# ── termtosvg-recorded demos ───────────────────────────────────
# Each demos/<name>.fish is recorded in an 80x25 PTY and rendered
# straight to SVG. Add a new demo by dropping a fish script in
# demos/ — `make demo` picks it up automatically.

TERMTOSVG ?= termtosvg
ASSETS    := assets

DEMO_SCRIPTS := $(filter-out demos/_%.fish,$(wildcard demos/*.fish))
DEMO_SVGS    := $(patsubst demos/%.fish,$(ASSETS)/%.svg,$(DEMO_SCRIPTS))

demo: $(DEMO_SVGS)

$(ASSETS):
	@mkdir -p $@

$(ASSETS)/%.svg: demos/%.fish | $(ASSETS)
	@command -v $(TERMTOSVG) >/dev/null || { echo "termtosvg not installed (apt: termtosvg, or pacman -S termtosvg on Arch)"; exit 1; }
	@echo "→ recording $@"
	@$(TERMTOSVG) -g 80x25 -c "fish $<" $@

demo-clean:
	@rm -rf $(ASSETS)/*.svg
