"""Sphinx configuration. See https://www.sphinx-doc.org/en/master/usage/configuration.html"""

from __future__ import annotations

import re
from typing import TYPE_CHECKING, ClassVar

from docutils import nodes
from sphinx.transforms import SphinxTransform

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


class GitHubAlerts(SphinxTransform):
    """Renders GitHub's alert syntax as Sphinx admonitions.

    The docs write callouts the GitHub way, so they also render on github.com:

        > [!WARNING]
        > This deletes your data.

    MyST has no support for this syntax, and shows it as a quote that starts
    with the literal text "[!WARNING]". This turns such a quote into the
    matching admonition. It runs on the parsed document, so it also covers
    the files that index pages include from outside docs/ (README.md,
    CONTRIBUTING.md, SECURITY.md), and it never touches code blocks.
    """

    default_priority = 200
    _KINDS: ClassVar[dict[str, type[nodes.Admonition]]] = {
        "NOTE": nodes.note,
        "TIP": nodes.tip,
        "IMPORTANT": nodes.important,
        "WARNING": nodes.warning,
        "CAUTION": nodes.caution,
    }
    _MARKER = re.compile(r"^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*")

    def apply(self, **_kwargs: object) -> None:
        for quote in list(self.document.findall(nodes.block_quote)):
            first = quote.children[0] if quote.children else None
            if not isinstance(first, nodes.paragraph) or not first.children:
                continue
            text = first.children[0]
            if not isinstance(text, nodes.Text):
                continue
            match = self._MARKER.match(text.astext())
            if match is None:
                continue
            rest = text.astext()[match.end() :]
            if rest:
                first.replace(text, nodes.Text(rest))
            else:
                first.remove(text)
            # The line break after the marker: drop it, and the paragraph if
            # nothing else was on the marker's line.
            while first.children and not first.children[0].astext().strip():
                first.remove(first.children[0])
            if not first.children:
                quote.remove(first)
            admonition = self._KINDS[match.group(1)]("", *quote.children)
            admonition.source, admonition.line = quote.source, quote.line
            quote.replace_self(admonition)


def setup(app: Sphinx) -> None:
    app.connect("build-finished", _copy_screenshots)
    app.add_transform(GitHubAlerts)
