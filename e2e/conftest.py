"""One real stack for the whole session: a throwaway Postgres, the backend
serving the built Flutter web app itself (same origin -- exactly how the
Docker image runs it, so no CORS or base-URL wiring to get wrong), and a
Chromium to drive it.

Tests get a fresh browser context each (so, a fresh localStorage and
whatever the app remembers in it), and register their own account, so none
depends on another's state.
"""

from __future__ import annotations

import os
import socket
import subprocess
import time
import urllib.error
import urllib.request
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

import pytest
from playwright.sync_api import Browser, BrowserContext, Page, ViewportSize, sync_playwright

REPO_ROOT = Path(__file__).resolve().parent.parent
BACKEND_DIR = REPO_ROOT / "backend"
FRONTEND_DIR = REPO_ROOT / "frontend"


def _free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port: int = sock.getsockname()[1]
        return port


def _wait_for_health(url: str, process: subprocess.Popen[bytes], timeout: float = 60) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"backend exited with {process.returncode} before {url} came up")
        try:
            with urllib.request.urlopen(url, timeout=2) as response:  # noqa: S310 -- our own localhost server
                if response.status == 200:
                    return
        except (urllib.error.URLError, ConnectionError):
            pass
        time.sleep(0.5)
    raise TimeoutError(f"{url} never came up")


@contextmanager
def _database_url() -> Iterator[str]:
    if existing := os.environ.get("E2E_DATABASE_URL"):
        yield existing
        return
    from testcontainers.community.postgres import PostgresContainer

    with PostgresContainer(
        "postgres:16-alpine", username="dinatos", password="dinatos", dbname="dinatos"
    ) as container:
        yield container.get_connection_url(driver="asyncpg")


def _web_build() -> Path:
    if existing := os.environ.get("E2E_WEB_DIR"):
        return Path(existing).resolve()
    # `--no-web-resources-cdn`: bundle CanvasKit instead of fetching it from
    # Google's CDN at page load, so the suite needs no internet at run time.
    subprocess.run(
        ["flutter", "build", "web", "--release", "--no-web-resources-cdn"],  # noqa: S607
        cwd=FRONTEND_DIR,
        check=True,
    )
    return FRONTEND_DIR / "build" / "web"


@pytest.fixture(scope="session")
def base_url() -> Iterator[str]:
    web_dir = _web_build()
    with _database_url() as database_url:
        env = {
            **os.environ,
            "DINATOS_DATABASE_URL": database_url,
            "DINATOS_WEB_DIR": str(web_dir),
        }
        subprocess.run(  # noqa: S603 -- fixed argv, no shell, `uv` from PATH
            ["uv", "run", "--project", str(BACKEND_DIR), "alembic", "upgrade", "head"],  # noqa: S607
            cwd=BACKEND_DIR,
            env=env,
            check=True,
        )
        port = _free_port()
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
                str(port),
            ],
            cwd=BACKEND_DIR,
            env=env,
        )
        try:
            _wait_for_health(f"http://127.0.0.1:{port}/health", process)
            yield f"http://127.0.0.1:{port}/"
        finally:
            process.terminate()
            process.wait(timeout=10)


@pytest.fixture(scope="session")
def browser() -> Iterator[Browser]:
    with sync_playwright() as playwright:
        # `channel="chromium"`: the full Chromium build, not Playwright's
        # default-for-headless "headless shell", which lacks the GPU/WebGL
        # support CanvasKit (Flutter web's renderer) needs -- the app would
        # load fine and paint a permanently blank page. `--no-sandbox`
        # because CI runs as root, where Chromium's sandbox refuses to start.
        # `E2E_CHROMIUM_PATH`: a Chromium already on the machine, for when
        # the one Playwright wants isn't downloadable (a sandbox with a
        # preinstalled browser of a different revision).
        if executable := os.environ.get("E2E_CHROMIUM_PATH"):
            browser = playwright.chromium.launch(executable_path=executable, args=["--no-sandbox"])
        else:
            browser = playwright.chromium.launch(channel="chromium", args=["--no-sandbox"])
        try:
            yield browser
        finally:
            browser.close()


def enable_semantics(page: Page) -> None:
    """Older Flutter web builds only create their labelled, role-based
    accessibility tree once something clicks the placeholder they render for
    that purpose (`dispatch_event` because it sits off-screen by design);
    newer ones create it up front and have no placeholder at all. Playwright's
    role locators have nothing to find without it, so handle both.
    """
    placeholder = page.locator("flt-semantics-placeholder")
    if placeholder.count():
        placeholder.dispatch_event("click")
    page.wait_for_timeout(300)


@pytest.fixture(params=["desktop", "phone"])
def viewport(request: pytest.FixtureRequest) -> ViewportSize:
    """Both of the app's navigation layouts: a side rail from 900px wide,
    a bottom bar below it -- the tour has to point at the right thing in each.
    """
    sizes: dict[str, ViewportSize] = {
        "desktop": {"width": 1280, "height": 900},
        "phone": {"width": 390, "height": 844},
    }
    return sizes[request.param]


@pytest.fixture
def context(browser: Browser, viewport: ViewportSize) -> Iterator[BrowserContext]:
    context = browser.new_context(viewport=viewport)
    try:
        yield context
    finally:
        context.close()


@pytest.fixture
def page(context: BrowserContext, base_url: str, request: pytest.FixtureRequest) -> Iterator[Page]:
    page = context.new_page()
    page.goto(base_url, wait_until="networkidle")
    page.wait_for_timeout(1500)
    enable_semantics(page)
    yield page
    if request.session.testsfailed:
        # A fixed, predictable path: a debugging aid read by hand (and
        # uploaded by CI) after a failure, not a security-sensitive temp file.
        page.screenshot(path=f"/tmp/dinatos-e2e-{request.node.name}.png")  # noqa: S108
