"""Generates README.md's screenshots against a real, throwaway backend and
a real frontend build -- not mocked data, not hand-maintained fixtures.

`just screenshots update` overwrites the committed PNGs (and README.md's
embed block) for whichever ones actually changed. `just screenshots check`
(what CI runs) does the same comparison but writes nothing and exits
non-zero if anything is stale, so a UI change that shifts what these
screens look like has to be deliberately re-generated and reviewed, not
silently drift out of sync with what README.md shows.

The "now" the app sees is frozen (see `_FREEZE_DATE_INIT_SCRIPT`) and every
other piece of seed data (emails, exercise names, weights) is a fixed
literal, never a timestamp or random value -- so two runs against
unchanged code produce byte-identical PNGs. That is what makes a plain
byte comparison enough to answer "did anything actually change", and is
also why a change to the current date is never mistaken for a change to
the UI: nothing here reads the real one.
"""

from __future__ import annotations

import argparse
import http.server
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from collections.abc import Iterator
from contextlib import contextmanager
from functools import partial
from pathlib import Path

from playwright.sync_api import Locator, Page, sync_playwright
from testcontainers.community.postgres import PostgresContainer

SCREENSHOTS_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCREENSHOTS_DIR.parent
BACKEND_DIR = REPO_ROOT / "backend"
FRONTEND_DIR = REPO_ROOT / "frontend"
README_PATH = REPO_ROOT / "README.md"

# Distinct from the default dev ports (8000/the frontend's usual 8081) so
# this never collides with a `just docker-up`/`just run` a person already
# has open locally.
BACKEND_PORT = 8100
FRONTEND_PORT = 8180

# What the app believes "now" is, for every screenshot. Any fixed value
# works; this one just reads unambiguously in a "Started" timestamp.
_FROZEN_NOW_MS = 1768467600000  # 2026-01-15T09:00:00Z
_FREEZE_DATE_INIT_SCRIPT = f"""
(() => {{
  const fixed = {_FROZEN_NOW_MS};
  const RealDate = Date;
  class FixedDate extends RealDate {{
    constructor(...args) {{
      if (args.length === 0) {{
        super(fixed);
      }} else {{
        super(...args);
      }}
    }}
    static now() {{
      return fixed;
    }}
  }}
  Date = FixedDate;
}})();
"""

EMAIL = "demo@example.com"
PASSWORD = "demo-password-123"  # noqa: S105 -- a fixture value for a throwaway account, not a secret
EXERCISES = [
    "Barbell Back Squat",
    "Bench Press",
    "Deadlift",
    "Overhead Press",
    "Pull-Up",
    "Barbell Row",
]
ROUTINE_NAME = "Push Day A"
ROUTINE_DESCRIPTION = "Chest, shoulders, triceps"

# name -> (file stem, caption). Order is display order in README.md.
SCREENSHOTS = {
    "login": ("login", "Signing in"),
    "exercise-view": ("exercise-view", "The exercise catalog"),
    "routine-creation": ("routine-creation", "Building a saved routine"),
    "routine-execution": ("routine-execution", "Logging an activity from it"),
}


def _wait_for_health(
    url: str, timeout_seconds: float = 30, process: subprocess.Popen[bytes] | None = None
) -> None:
    deadline = time.monotonic() + timeout_seconds
    last_error: Exception | None = None
    while time.monotonic() < deadline:
        if process is not None and process.poll() is not None:
            raise RuntimeError(f"process exited with {process.returncode} before {url} came up")
        try:
            with urllib.request.urlopen(url, timeout=2) as response:  # noqa: S310 -- always our own localhost server
                if response.status == 200:
                    return
        except (urllib.error.URLError, ConnectionError) as error:
            last_error = error
        time.sleep(0.5)
    raise TimeoutError(f"{url} never came up") from last_error


@contextmanager
def _postgres_database_url() -> Iterator[str]:
    with PostgresContainer(
        "postgres:16-alpine",
        username="dinatos",
        password="dinatos",  # noqa: S106 -- a throwaway testcontainers Postgres credential, not a real secret
        dbname="dinatos",
    ) as container:
        yield container.get_connection_url(driver="asyncpg")


@contextmanager
def _running_backend(database_url: str) -> Iterator[None]:
    env = {
        "DINATOS_DATABASE_URL": database_url,
        # Otherwise the exercise-view screenshot below shows the full
        # standard catalog (see services/exercise.py) instead of just the
        # small, curated `EXERCISES` list this script creates itself.
        "DINATOS_SEED_DEFAULT_EXERCISES": "false",
    }
    subprocess.run(  # noqa: S603 -- fixed argv, no shell, `uv` resolved from PATH like every other justfile recipe
        ["uv", "run", "--project", str(BACKEND_DIR), "alembic", "upgrade", "head"],  # noqa: S607
        cwd=BACKEND_DIR,
        env={**_inherited_env(), **env},
        check=True,
    )
    process = subprocess.Popen(  # noqa: S603 -- fixed argv, no shell, `uv` from PATH
        [  # noqa: S607
            "uv",
            "run",
            "--project",
            str(BACKEND_DIR),
            "uvicorn",
            "dinatos_backend.main:app",
            "--host",
            "127.0.0.1",
            "--port",
            str(BACKEND_PORT),
        ],
        cwd=BACKEND_DIR,
        env={**_inherited_env(), **env},
    )
    try:
        _wait_for_health(f"http://127.0.0.1:{BACKEND_PORT}/health", process=process)
        yield
    finally:
        process.terminate()
        process.wait(timeout=10)


def _inherited_env() -> dict[str, str]:
    return dict(os.environ)


def _build_frontend() -> Path:
    subprocess.run(  # noqa: S603 -- fixed argv, no shell, `flutter` from PATH
        [  # noqa: S607
            "flutter",
            "build",
            "web",
            "--release",
            f"--dart-define=API_BASE_URL=http://127.0.0.1:{BACKEND_PORT}",
        ],
        cwd=FRONTEND_DIR,
        check=True,
    )
    return FRONTEND_DIR / "build" / "web"


@contextmanager
def _serving_frontend(web_dir: Path) -> Iterator[None]:
    handler = partial(http.server.SimpleHTTPRequestHandler, directory=str(web_dir))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", FRONTEND_PORT), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        _wait_for_health(f"http://127.0.0.1:{FRONTEND_PORT}/")
        yield
    finally:
        server.shutdown()
        server.server_close()


def _fill(locator: Locator, value: str) -> None:
    """`Locator.fill()` sets the underlying `<input>`'s value in one shot and
    dispatches a single DOM `input` event. Flutter's web engine mirrors its
    own `TextEditingController` state back onto that same `<input>` on every
    rebuild it does (e.g. to run a validator), and a bulk `.fill()` can lose
    the race against that mirroring -- the rebuild overwrites the DOM value
    back to empty before Flutter's JS<->Dart channel has processed our input
    event, which is what a "Name is required" error on a field we just filled
    means. Typing character-by-character via real key events, like a person
    would, avoids this: each keystroke is processed by Flutter's own
    key/text-input handling as it happens, rather than needing to survive an
    async round trip in a single bulk update. Select-all-then-delete first so
    this also works to *replace* a field's existing value (e.g. a set copied
    from a saved routine), not just to fill an empty one.
    """
    locator.click()
    locator.press("ControlOrMeta+a")
    locator.press("Delete")
    locator.press_sequentially(value, delay=20)
    locator.page.wait_for_timeout(150)


def _enable_semantics(page: Page) -> None:
    """Older Flutter web builds only create their real (labelled, role-based)
    accessibility tree after something clicks the placeholder button they
    render for exactly this purpose -- until then, Playwright's role/label
    locators have nothing to find. `dispatch_event` rather than `.click()`
    because the placeholder sits off-screen by design. Newer builds create
    the tree up front and have no placeholder at all, so only click one that
    exists (a bare dispatch_event would wait out its 30s timeout).
    """
    placeholder = page.locator("flt-semantics-placeholder")
    if placeholder.count():
        placeholder.dispatch_event("click")
    page.wait_for_timeout(300)


def _register(page: Page) -> None:
    page.get_by_role("button", name="Don't have an account? Register").click()
    page.wait_for_timeout(400)
    _fill(page.get_by_role("textbox", name="Email"), EMAIL)
    _fill(page.get_by_role("textbox", name="Password"), PASSWORD)
    page.get_by_role("button", name="Register").click()
    page.wait_for_timeout(1000)
    # A brand-new account is offered the first-run tour, whose dimmed overlay
    # would block everything below (and show up in every screenshot).
    page.get_by_role("button", name="Skip tour").click()
    page.wait_for_timeout(300)


def _create_exercise(page: Page, name: str) -> None:
    page.get_by_role("button", name="New exercise").click()
    page.wait_for_timeout(400)
    _fill(page.get_by_role("textbox", name="Name"), name)
    page.get_by_role("button", name="Create").click()
    page.wait_for_timeout(500)


# Top-level destinations, in the order the shell draws them.
_TABS = ["Exercises", "Routines", "Home", "Measurements", "Settings"]


def _goto_tab(page: Page, name: str) -> None:
    """The wide layout's side rail is not in the accessibility tree at all (no
    role, no label), so it is pressed where it is drawn: equal-height
    destinations down the left edge. Same workaround as e2e/test_onboarding.py;
    this viewport is wide, so the bottom bar's `tab` role is never an option.
    """
    page.mouse.click(51, 34 + 64 * _TABS.index(name))
    page.wait_for_timeout(300)


def _fill_set(card: Locator, index: int, kg: str, reps: str) -> None:
    _fill(card.get_by_role("textbox", name="kg").nth(index), kg)
    _fill(card.get_by_role("textbox", name="reps").nth(index), reps)


def _set_type(card: Locator, current: str, new: str) -> None:
    """Opens the first set row still showing `current` as its type and
    picks `new`. Only meaningful while at most one row needs changing at a
    time -- exactly the shape this script's own data needs.
    """
    card.get_by_role("button", name=current).first.click()
    card.page.get_by_role("menuitem", name=new).click()


def run_browser_flow(base_url: str, output_dir: Path) -> dict[str, Path]:
    saved: dict[str, Path] = {}

    with sync_playwright() as playwright:
        # `channel="chromium"` forces the full Chromium build rather than
        # Playwright's default-for-headless "headless shell" variant, which
        # doesn't support the GPU/WebGL features CanvasKit (Flutter web's
        # renderer) needs -- with headless shell, the app fetches and runs
        # fine but paints nothing, a blank page forever, no error anywhere.
        # `--no-sandbox` because CI (like most container-based CI) runs as
        # root, where Chromium's sandbox refuses to start at all.
        browser = playwright.chromium.launch(channel="chromium", args=["--no-sandbox"])
        page = browser.new_page(viewport={"width": 1280, "height": 900})
        page.add_init_script(_FREEZE_DATE_INIT_SCRIPT)
        page.goto(base_url, wait_until="networkidle")
        page.wait_for_timeout(1500)
        try:
            _enable_semantics(page)

            path = output_dir / f"{SCREENSHOTS['login'][0]}.png"
            page.screenshot(path=path)
            saved["login"] = path

            _register(page)
            for name in EXERCISES:
                _create_exercise(page, name)
            page.mouse.move(10, 10)  # away from whatever was last hovered/focused

            path = output_dir / f"{SCREENSHOTS['exercise-view'][0]}.png"
            page.screenshot(path=path)
            saved["exercise-view"] = path

            _goto_tab(page, "Routines")
            page.get_by_role("button", name="New routine").click()
            page.wait_for_timeout(400)
            _fill(page.get_by_role("textbox", name="Name"), ROUTINE_NAME)
            _fill(page.get_by_role("textbox", name="Description (optional)"), ROUTINE_DESCRIPTION)

            page.get_by_role("button", name="Add exercise").click()
            page.wait_for_timeout(300)
            page.get_by_role("button", name="Bench Press", exact=True).click()
            page.wait_for_timeout(300)
            bench = page.get_by_role("group", name="Bench Press")
            for _ in range(3):
                bench.get_by_role("button", name="Add set").dispatch_event("click")
                page.wait_for_timeout(250)
            _fill_set(bench, 0, "40", "10")
            _fill_set(bench, 1, "60", "8")
            _fill_set(bench, 2, "60", "8")
            _set_type(bench, "normal", "warmup")

            page.get_by_role("button", name="Add exercise").click()
            page.wait_for_timeout(300)
            page.get_by_role("button", name="Overhead Press", exact=True).click()
            page.wait_for_timeout(300)
            overhead = page.get_by_role("group", name="Overhead Press")
            for _ in range(2):
                overhead.get_by_role("button", name="Add set").dispatch_event("click")
                page.wait_for_timeout(250)
            _fill_set(overhead, 0, "40", "8")
            _fill_set(overhead, 1, "45", "6")

            path = output_dir / f"{SCREENSHOTS['routine-creation'][0]}.png"
            page.screenshot(path=path)
            saved["routine-creation"] = path

            page.get_by_role("button", name="Create").click()
            page.wait_for_timeout(1000)

            _goto_tab(page, "Home")
            page.get_by_role("button", name="Log a past activity").click()
            page.wait_for_timeout(400)
            _fill(page.get_by_role("textbox", name="Title"), ROUTINE_NAME)
            page.get_by_role("button", name="Start from a saved routine").click()
            page.wait_for_timeout(300)
            page.get_by_role("button", name=ROUTINE_NAME, exact=True).click()
            page.wait_for_timeout(400)

            # A realistic tweak: the last Overhead Press set went a little
            # heavier than planned that day.
            # The form is taller than the viewport now; the field sits at its very
            # bottom edge, where the click lands on the wrong set. Scroll it
            # comfortably into view first.
            page.mouse.move(690, 500)
            page.mouse.wheel(0, 250)
            page.wait_for_timeout(500)
            activity_overhead = page.get_by_role("group", name="Overhead Press")
            _fill(activity_overhead.get_by_role("textbox", name="kg").nth(1), "47.5")

            path = output_dir / f"{SCREENSHOTS['routine-execution'][0]}.png"
            page.screenshot(path=path)
            saved["routine-execution"] = path

            # Finish the flow for real -- not needed for any screenshot, but
            # confirms the whole path this script exercises still actually works.
            page.get_by_role("button", name="Create").click()
            page.wait_for_timeout(800)
        except Exception:
            # A fixed, predictable path is the point -- this is a debugging
            # aid a person checks by hand after a local failure, not a
            # security-sensitive temp file.
            page.screenshot(path="/tmp/dinatos-screenshot-debug.png")  # noqa: S108
            raise
        finally:
            browser.close()

    return saved


def _readme_block(names: list[str]) -> str:
    cells = []
    for name in names:
        stem, caption = SCREENSHOTS[name]
        cells.append(
            f'<td align="center" width="50%">\n'
            f'<img alt="{caption}" src="screenshots/{stem}.png" width="380"><br>\n'
            f"<sub>{caption}</sub>\n"
            f"</td>"
        )
    rows = [cells[i : i + 2] for i in range(0, len(cells), 2)]
    table_rows = "\n".join("<tr>\n" + "\n".join(row) + "\n</tr>" for row in rows)
    return (
        "<!-- screenshots:start -- generated by screenshots/generate.py, do not edit by hand -->\n"
        "<table>\n"
        f"{table_rows}\n"
        "</table>\n"
        "<!-- screenshots:end -->"
    )


def _rendered_readme(names: list[str]) -> str:
    """README.md with its screenshots block replaced by what it should be
    right now -- callers compare this against the file on disk (`--check`)
    or write it back (`--update`); either way this is the one place that
    block's exact text gets produced, so the two modes can't drift apart.
    """
    text = README_PATH.read_text()
    start_marker = "<!-- screenshots:start"
    end_marker = "<!-- screenshots:end -->"
    start = text.find(start_marker)
    end = text.find(end_marker)
    if start == -1 or end == -1:
        raise RuntimeError(f"{README_PATH} has no <!-- screenshots:start/end --> block to fill in")
    end += len(end_marker)
    return text[:start] + _readme_block(names) + text[end:]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument(
        "--check", action="store_true", help="compare only; write nothing; exit 1 if stale"
    )
    mode.add_argument(
        "--update", action="store_true", help="overwrite committed PNGs/README with what changed"
    )
    args = parser.parse_args()

    frontend_web_dir = _build_frontend()

    with tempfile.TemporaryDirectory(prefix="dinatos-screenshots-") as scratch:
        scratch_dir = Path(scratch)
        with (
            _postgres_database_url() as database_url,
            _running_backend(database_url),
            _serving_frontend(frontend_web_dir),
        ):
            generated = run_browser_flow(f"http://127.0.0.1:{FRONTEND_PORT}/", scratch_dir)

        changed = []
        for name, generated_path in generated.items():
            stem, _caption = SCREENSHOTS[name]
            committed_path = SCREENSHOTS_DIR / f"{stem}.png"
            is_new_or_different = (
                not committed_path.exists()
                or committed_path.read_bytes() != generated_path.read_bytes()
            )
            if is_new_or_different:
                changed.append(name)
            if args.update:
                shutil.copyfile(generated_path, committed_path)
        # scratch (and everything generated into it) is removed once this
        # `with` block exits -- nothing generated ever lingers outside it.

    current_readme = README_PATH.read_text()
    new_readme = _rendered_readme(list(SCREENSHOTS))
    readme_stale = new_readme != current_readme

    if args.update:
        if readme_stale:
            README_PATH.write_text(new_readme)
        if changed:
            print("Updated: " + ", ".join(changed))
        if readme_stale:
            print(f"Updated {README_PATH.relative_to(REPO_ROOT)}'s screenshots block.")
        if not changed and not readme_stale:
            print("Nothing changed.")
        return 0

    # --check: report, write nothing.
    problems = list(changed)
    if readme_stale:
        problems.append("README.md's screenshots block")
    if problems:
        print("Stale (run `just screenshots update` and commit the result): " + ", ".join(problems))
        return 1
    print("All screenshots and README.md match.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
