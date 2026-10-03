"""A password-manager extension (Bitwarden et al.) filling the login form.

An extension fills a field by setting `input.value` through the native setter
and dispatching synthetic `input`/`change` events -- no key events, which is
what `Locator.fill()` and `press_sequentially()` (used everywhere else in this
suite) would send. Flutter web on its own drops that on the floor and mirrors
its own empty state back over the DOM value; `core/widgets/web_autofill_bridge_web.dart`
is the fix, and this is the test that it keeps working.
"""

from __future__ import annotations

import json
import re
import urllib.request
import uuid

from playwright.sync_api import Page, expect

PASSWORD = "e2e-password-123"  # a throwaway account on a throwaway database

# What an extension does to a field: native value setter + synthetic events.
_EXTENSION_FILL = """([label, value]) => {
    const input = [...document.querySelectorAll('input')]
        .find((i) => i.getAttribute('aria-label') === label);
    const setValue = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    input.focus();
    setValue.call(input, value);
    for (const type of ['keydown', 'keypress', 'input', 'keyup', 'change']) {
        input.dispatchEvent(new Event(type, { bubbles: true }));
    }
}"""


def test_extension_style_fill_logs_in(page: Page, base_url: str) -> None:
    email = f"{uuid.uuid4().hex[:12]}@example.com"
    request = urllib.request.Request(  # noqa: S310 -- our own localhost server
        f"{base_url}auth/register",
        data=json.dumps({"email": email, "password": PASSWORD}).encode(),
        headers={"Content-Type": "application/json"},
    )
    urllib.request.urlopen(request, timeout=10).close()  # noqa: S310

    # What the extension's heuristics look at: standard autocomplete tokens.
    expect(page.locator("input[aria-label='Email']")).to_have_attribute("autocomplete", "username")
    expect(page.locator("input[aria-label='Password']")).to_have_attribute(
        "autocomplete", "current-password"
    )

    page.evaluate(_EXTENSION_FILL, ["Email", email])
    page.evaluate(_EXTENSION_FILL, ["Password", PASSWORD])
    page.wait_for_timeout(500)

    # Still there after Flutter has had time to rebuild, not reverted to empty.
    expect(page.locator("input[aria-label='Email']")).to_have_value(email)
    expect(page.locator("input[aria-label='Password']")).to_have_value(PASSWORD)

    page.get_by_role("button", name="Log in").click()
    welcome = re.compile(r"^Tour step \d+ of \d+: Welcome to Dinatos$")
    expect(page.get_by_role("group", name=welcome)).to_be_visible(timeout=10_000)
