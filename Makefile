.PHONY: install uninstall test

REPO     := $(shell pwd)
FISH_DIR := $(or $(XDG_CONFIG_HOME),$(HOME)/.config)/fish
LOADER   := $(FISH_DIR)/conf.d/tgt-loader.fish

install:
	@mkdir -p $(FISH_DIR)/conf.d
	@ln -sf $(REPO)/conf.d/tgt-loader.fish $(LOADER)
	@echo "✓ installed: $(LOADER)"

uninstall:
	@rm -f $(LOADER)
	@echo "✓ removed $(LOADER)"

test:
	@fishtape */test/test_*.fish
