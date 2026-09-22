# Makefile for the StormFS OpenRC book
#
# Targets:
#   make            - build the no-chunks HTML book (default)
#   make html       - build html/index.html and the single-file html/book.html
#   make nochunks   - explicitly build the single-file HTML book
#   make chunks     - build separate HTML pages for each chapter
#   make pdf        - build a PDF via pandoc (requires pandoc + a PDF engine)
#   make wget-list  - regenerate the wget-list from the ports tree
#   make clean      - remove generated output
#
# Requires: python3 with the "markdown" package (python3 -m pip install markdown)

BOOK_TITLE  := StormFS Linux OpenRC Book
BOOK_SUBTITLE := BLFS-style OpenRC guide for StormFS Linux

PYTHON      ?= $(shell command -v python3 2>/dev/null || which python3 2>/dev/null || echo python3)
TOOLS_DIR   := $(abspath ../book-tools)
BUILDER     := $(TOOLS_DIR)/build.py
CHAPTERS    := $(sort $(wildcard chapters/*.md))
HTML_DIR    := html
STAMP       := $(HTML_DIR)/.built
CHUNKS_STAMP := $(HTML_DIR)/.chunks-built
PANDOC      := $(shell command -v pandoc 2>/dev/null || which pandoc 2>/dev/null)

.PHONY: all html nochunks chunks pdf wget-list check clean help

all: nochunks

html: nochunks

nochunks: $(STAMP)

$(STAMP): README.md $(CHAPTERS) $(BUILDER)
	$(PYTHON) $(BUILDER) --mode nochunks --title "$(BOOK_TITLE)" --subtitle "$(BOOK_SUBTITLE)" \
		--out $(HTML_DIR) --stamp $@ README.md chapters

chunks: README.md $(CHAPTERS) $(BUILDER)
	$(PYTHON) $(BUILDER) --mode chunks --title "$(BOOK_TITLE)" --subtitle "$(BOOK_SUBTITLE)" \
		--out $(HTML_DIR) --stamp $(CHUNKS_STAMP) README.md chapters

pdf: README.md $(CHAPTERS)
ifdef PANDOC
	pandoc --standalone --toc --metadata title="$(BOOK_TITLE)" \
		-o stormfs-openrc-book.pdf README.md $(CHAPTERS)
else
	$(error pandoc not found. Install pandoc (plus e.g. texlive for the PDF engine) or use 'make html')
endif

wget-list:
	$(PYTHON) gen-wget-list.py --output wget-list

check: wget-list
	@echo "verifying wget-list URL syntax..."
	@$(PYTHON) -c "import sys; urls=[l.strip() for l in open('wget-list', encoding='utf-8') if l.strip()]; bad=[u for u in urls if not u.startswith(('http://','https://','ftp://'))]; sys.exit('bad URLs: %s' % bad if bad else print('%d URLs OK' % len(urls)))"

clean:
	rm -rf $(HTML_DIR) *.pdf

help:
	@echo "Targets: all | html | nochunks | chunks | pdf | wget-list | check | clean"
