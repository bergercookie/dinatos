"""Sphinx configuration. See https://www.sphinx-doc.org/en/master/usage/configuration.html"""

from __future__ import annotations

project = "Dinatos"
copyright = "2026, Dinatos contributors"
author = "Dinatos contributors"

extensions = ["myst_parser"]
myst_enable_extensions = ["colon_fence"]

# Every .md file in the repo is a doc source, read in place rather than
# copied, so the docs render the same content you see browsing the repo.
source_suffix = {".md": "markdown"}

exclude_patterns = ["_build", "Thumbs.db", ".DS_Store"]

html_theme = "furo"
