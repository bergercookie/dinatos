"""The first-run tour, driven the way a person would: by pressing the very
things it highlights. Run against both layouts (side rail and bottom bar).

Flutter web draws to a canvas, so there is no DOM text to query -- but it
does expose a real accessibility tree, and Playwright's role locators find
things through it (see conftest's `page` fixture for switching it on).
"""

from __future__ import annotations

import contextlib
import re
import uuid

from playwright.sync_api import Locator, Page, expect
from playwright.sync_api import TimeoutError as PlaywrightTimeoutError

from conftest import enable_semantics

PASSWORD = "e2e-password-123"  # a throwaway account on a throwaway database


def _fill(locator: Locator, value: str) -> None:
    """Types like a person does: `Locator.fill()` sets the underlying
    `<input>` in one shot and can lose a race against Flutter mirroring its
    own text-controller state back onto it, leaving the field empty.
    """
    locator.click()
    locator.press("ControlOrMeta+a")
    locator.press("Delete")
    locator.press_sequentially(value, delay=20)
    locator.page.wait_for_timeout(150)


def _register(page: Page) -> None:
    page.get_by_role("button", name="Don't have an account? Register").click()
    page.wait_for_timeout(400)
    _fill(page.get_by_role("textbox", name="Email"), f"{uuid.uuid4().hex[:12]}@example.com")
    _fill(page.get_by_role("textbox", name="Password"), PASSWORD)
    page.get_by_role("button", name="Register").click()


_TABS = ["Exercises", "Routines", "Home", "Body", "Settings"]
_WIDE_LAYOUT_FROM = 900  # px -- mirrors `_wideBreakpoint` in app_shell.dart


def _press_tab(page: Page, name: str, timeout: float = 30_000) -> None:
    """Presses a top-level navigation destination.

    The bottom bar (narrow layout) is a proper accessibility-tree "tab". The
    side rail (wide layout) is not exposed to it at all -- neither a role nor
    a label to find it by -- so there it is pressed where it is drawn: a
    column of equal-height destinations at the left edge, from the top.
    """
    viewport = page.viewport_size
    assert viewport is not None
    if viewport["width"] >= _WIDE_LAYOUT_FROM:
        page.mouse.click(51, 34 + 64 * _TABS.index(name))
    else:
        page.get_by_role("tab", name=name).click(timeout=timeout)
    page.wait_for_timeout(300)


def _step_card(page: Page, title: str) -> Locator:
    """The tour card for the step called [title] -- exposed to assistive tech
    (and so to Playwright) as a group labelled "Tour step N of M: <title>".
    """
    label = re.compile(rf"^Tour step \d+ of \d+: {re.escape(title)}$")
    return page.get_by_role("group", name=label)


def _on_step(page: Page, title: str) -> None:
    """Waits for the tour card showing [title] to appear."""
    expect(_step_card(page, title)).to_be_visible(timeout=10_000)


def test_tour_takes_a_new_user_from_sign_up_to_a_logged_workout(page: Page) -> None:
    _register(page)

    _on_step(page, "Welcome to Dinatos")
    page.get_by_role("button", name="Start tour").click()

    _on_step(page, "Start with Settings")
    _press_tab(page, "Settings")

    _on_step(page, "Pick your units")
    page.get_by_role("button", name="Save").click()

    _on_step(page, "Routines are reusable plans")
    _press_tab(page, "Routines")

    _on_step(page, "Create a routine")
    page.get_by_role("button", name="New routine").click()

    _on_step(page, "Name it and add exercises")
    _fill(page.get_by_role("textbox", name="Name"), "Tour Day")
    page.get_by_role("button", name="Add exercise").click()
    page.wait_for_timeout(800)
    # The built-in catalog is hundreds long and only drawn as far as it
    # scrolls, so search for the one wanted rather than looking for it.
    _fill(page.get_by_role("textbox", name="Search exercises..."), "Bench Press")
    page.get_by_role("button", name="Barbell Bench Press - Medium Grip", exact=True).click()
    page.wait_for_timeout(500)
    page.get_by_role("button", name="Create").click()

    _on_step(page, "Now, go train")
    _press_tab(page, "Home")

    _on_step(page, "Start a live workout")
    page.get_by_role("button", name="Start activity").click()
    page.get_by_role("button", name="From scratch").click()

    _on_step(page, "Add an exercise")
    page.get_by_role("button", name="Next").click()

    _on_step(page, "Finish when you are done")
    page.get_by_role("button", name="Finish workout").click()

    _on_step(page, "You're all set")
    page.get_by_role("button", name="Finish", exact=True).click()
    expect(_step_card(page, "You're all set")).to_have_count(0)

    # Done is remembered: still signed in after a reload, and no second tour.
    page.reload(wait_until="networkidle")
    page.wait_for_timeout(1500)
    enable_semantics(page)
    expect(_step_card(page, "Welcome to Dinatos")).to_have_count(0)


def test_skipping_the_tour_is_remembered_and_it_can_be_replayed(page: Page) -> None:
    _register(page)
    _on_step(page, "Welcome to Dinatos")

    page.get_by_role("button", name="Skip tour").click()
    expect(_step_card(page, "Welcome to Dinatos")).to_have_count(0)

    page.reload(wait_until="networkidle")
    page.wait_for_timeout(1500)
    enable_semantics(page)
    expect(_step_card(page, "Welcome to Dinatos")).to_have_count(0)

    _press_tab(page, "Settings")
    page.get_by_text("Take the tour again").click()
    _on_step(page, "Welcome to Dinatos")


def test_highlighted_step_blocks_everything_else(page: Page) -> None:
    _register(page)
    page.get_by_role("button", name="Start tour").click()
    _on_step(page, "Start with Settings")

    # Only Settings is left pressable; the other tabs sit behind the scrim.
    # On the phone layout the browser itself refuses the press (the scrim
    # intercepts it), on the wide one it lands on the scrim and does nothing.
    with contextlib.suppress(PlaywrightTimeoutError):
        _press_tab(page, "Body", timeout=2_000)
    page.wait_for_timeout(500)
    _on_step(page, "Start with Settings")
    expect(page.get_by_role("heading", name="Exercises")).to_be_visible()

    _press_tab(page, "Settings")
    _on_step(page, "Pick your units")
