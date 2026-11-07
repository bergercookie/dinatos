"""Sphinx configuration. See https://www.sphinx-doc.org/en/master/usage/configuration.html"""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from sphinx.application import Sphinx

project = "Dinatos"
copyright = "2026, Nikos Koukis"
author = "Nikos Koukis"

extensions = ["myst_parser"]
myst_enable_extensions = ["colon_fence"]
# Lets a link like `backend.md#authentication` resolve to a heading anywhere
# up to this depth, from any other page -- used throughout for cross-section
# references (e.g. deploy/ pointing at the design rationale in architecture/).
myst_heading_anchors = 3

# Every .md file in the repo is a doc source, read in place rather than
# copied, so the docs render the same content you see browsing the repo.
source_suffix = {".md": "markdown"}

exclude_patterns = ["_build", "Thumbs.db", ".DS_Store"]

html_theme = "furo"


def _copy_screenshots(app: Sphinx, exception: Exception | None) -> None:
    """index.md includes README.md, whose raw-HTML <img src="screenshots/...">
    tags Sphinx does not track as assets: copy the PNGs next to the page."""
    if exception is None and app.builder.format == "html":
        import shutil
        from pathlib import Path

        src = Path(__file__).resolve().parent.parent / "screenshots"
        dest = Path(app.outdir) / "screenshots"
        dest.mkdir(exist_ok=True)
        for png in src.glob("*.png"):
            shutil.copy2(png, dest / png.name)


def setup(app: Sphinx) -> None:
    app.connect("build-finished", _copy_screenshots)
