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
templates_path = ["_templates"]
# Furo has no option for a custom header icon, but each entry of
# top_of_page_buttons includes a component template. _templates/ overrides
# the "view" one with a link to the repository (the only button enabled here),
# so it sits next to the theme toggle with Furo's own styling.
_REPOSITORY_URL = "https://github.com/bergercookie/dinatos"
# The GitHub mark (Octicons, MIT), shared by the header and footer links.
_GITHUB_ICON_PATH = (
    "M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-."
    "82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-."
    "01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78"
    "-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21"
    " 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1."
    "1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.5"
    "4 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0 0 16 8c0-4.42-3"
    ".58-8-8-8z"
)
html_theme_options = {
    "top_of_page_buttons": ["view"],
    # The same link in the footer, through Furo's own option.
    "footer_icons": [
        {
            "name": "GitHub",
            "url": _REPOSITORY_URL,
            "html": (
                '<svg stroke="currentColor" fill="currentColor" stroke-width="0" '
                'viewBox="0 0 16 16">'
                f'<path fill-rule="evenodd" d="{_GITHUB_ICON_PATH}"></path></svg>'
            ),
            "class": "",
        },
    ],
}
html_context = {"repository_url": _REPOSITORY_URL, "github_icon_path": _GITHUB_ICON_PATH}


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
