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

# ── Recorded demos ─────────────────────────────────────────────
# Two pipelines:
#
#   demos/<name>.fish  → assets/<name>.svg   via termtosvg
#                        for non-interactive output. Single Python
#                        tool, in apt: `apt install termtosvg`.
#
#   demos/<name>.tape  → assets/<name>.gif   via vhs
#                        for interactive flows that need keystroke
#                        driving (gum, fzf, the wizard). Needs
#                        `vhs` (charm.sh apt repo) + `ttyd` (binary
#                        from github.com/tsl0922/ttyd).
#
# Add a new demo by dropping a script (or tape) in demos/ — both
# rules pick up automatically. Files prefixed with `_` are ignored
# (helpers, smoke tests).

TERMTOSVG ?= termtosvg
VHS       ?= vhs
ASSETS    := assets

DEMO_SCRIPTS := $(filter-out demos/_%.fish,$(wildcard demos/*.fish))
DEMO_SVGS    := $(patsubst demos/%.fish,$(ASSETS)/%.svg,$(DEMO_SCRIPTS))

DEMO_TAPES   := $(filter-out demos/_%.tape,$(wildcard demos/*.tape))
DEMO_GIFS    := $(patsubst demos/%.tape,$(ASSETS)/%.gif,$(DEMO_TAPES))

demo: $(DEMO_SVGS) $(DEMO_GIFS)

$(ASSETS):
	@mkdir -p $@

$(ASSETS)/%.svg: demos/%.fish | $(ASSETS)
	@command -v $(TERMTOSVG) >/dev/null || { echo "termtosvg not installed (apt: termtosvg, or pacman -S termtosvg on Arch)"; exit 1; }
	@echo "→ recording $@"
	@$(TERMTOSVG) -g 80x25 -D 5000 -c "fish $<" $@

$(ASSETS)/%.gif: demos/%.tape | $(ASSETS)
	@command -v $(VHS) >/dev/null || { echo "vhs not installed (charm.sh apt repo) — also needs ttyd"; exit 1; }
	@command -v ttyd >/dev/null || { echo "ttyd not installed (https://github.com/tsl0922/ttyd/releases)"; exit 1; }
	@echo "→ recording $@"
	@$(VHS) $<

demo-clean:
	@rm -rf $(ASSETS)/*.svg $(ASSETS)/*.gif
