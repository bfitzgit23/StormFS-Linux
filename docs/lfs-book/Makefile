# Makefile for the StormFS LFS book
PYTHON ?= $(shell command -v python3 2>/dev/null || which python3 2>/dev/null || echo python3)
BUILDER := $(abspath ../book-tools/build.py)
CHAPTERS := $(sort $(wildcard chapters/*.md))
HTML_DIR := html
STAMP := $(HTML_DIR)/.built

.PHONY: all html nochunks chunks wget-list clean

all: nochunks
html: nochunks
nochunks: $(STAMP)

$(STAMP): README.md $(CHAPTERS) $(BUILDER)
	$(PYTHON) $(BUILDER) --mode nochunks --title "StormFS Linux LFS Book" \
		--subtitle "LFS 13.1 multilib build with OpenRC and Emerald" \
		--out $(HTML_DIR) --stamp $@ README.md chapters

chunks: README.md $(CHAPTERS) $(BUILDER)
	$(PYTHON) $(BUILDER) --mode chunks --title "StormFS Linux LFS Book" \
		--subtitle "LFS 13.1 multilib build with OpenRC and Emerald" \
		--out $(HTML_DIR) README.md chapters

wget-list:
	$(PYTHON) gen-wget-list.py --output wget-list

clean:
	rm -rf $(HTML_DIR)
