"""The FastAPI application."""

from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.openapi.docs import get_swagger_ui_html
from fastapi.staticfiles import StaticFiles
from starlette.exceptions import HTTPException as StarletteHTTPException
from starlette.responses import HTMLResponse, Response
from starlette.routing import Route
from starlette.types import Scope

from dinatos_backend import __version__
from dinatos_backend.api.lifespan import lifespan
from dinatos_backend.api.mcp import mcp_gateway
from dinatos_backend.api.routers import (
    activities,
    admin,
    api_keys,
    auth,
    exercises,
    imports,
    intervals_imports,
    measurements,
    profile,
    routines,
)
from dinatos_backend.config import get_settings

app = FastAPI(
    title="Dinatos",
    version=__version__,
    lifespan=lifespan,
    docs_url=None,  # replaced by the themed `/docs` route below
    description=(
        "The Dinatos REST API.\n\n"
        "Everything except `GET /health` needs an "
        "`Authorization: Bearer <token>` header. Call `POST /auth/register` or "
        "`POST /auth/login` to get one -- those two, plus `GET /auth/config`, "
        "work without it (`/auth/me` and `/auth/logout` are themselves "
        "authenticated). `/admin/*` additionally needs an admin account.\n\n"
        "This is a self-hosted service: `/docs` (this page), `/redoc` and the "
        "raw `/openapi.json` are served by the same app, so they are only "
        "reachable to whoever can already reach the API itself."
    ),
    openapi_tags=[
        {"name": "auth", "description": "Registration, login and session revocation."},
        {
            "name": "admin",
            "description": "Account administration and full-server backup/restore (admins only).",
        },
        {"name": "exercises", "description": "The exercise catalog, shared by every user."},
        {"name": "routines", "description": "Routine templates: exercises and sets, no dates."},
        {"name": "activities", "description": "Logged instances of a workout, actually performed."},
        {"name": "measurements", "description": "Body weight, fat percentage and circumferences."},
        {
            "name": "profile",
            "description": "Per-user settings; export and import of one's own data.",
        },
        {
            "name": "imports",
            "description": (
                "One-shot migration of a Hevy CSV export, or of chosen Intervals.icu activities."
            ),
        },
    ],
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=get_settings().cors_allowed_origins,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
    # `X-Total-Count` (GET /exercises' pagination total) is otherwise
    # invisible to browser JS on a cross-origin response -- only headers
    # named here are exposed, regardless of allow_headers above.
    # `Content-Disposition` likewise carries the filename of the backup/export
    # downloads (`GET /admin/backup`, `GET /profile/export`).
    expose_headers=["X-Total-Count", "Content-Disposition"],
)
app.include_router(auth.router)
app.include_router(api_keys.router)
app.include_router(admin.router)
app.include_router(exercises.router)
app.include_router(routines.router)
app.include_router(activities.router)
app.include_router(profile.router)
app.include_router(measurements.router)
app.include_router(imports.router)
app.include_router(intervals_imports.router)
# The MCP server (streamable HTTP), for LLM clients that take a URL and an API
# key. Routes, not a Mount: `/mcp` must answer as itself, not redirect to `/mcp/`.
for _mcp_path in ("/mcp", "/mcp/"):
    app.router.routes.append(
        Route(_mcp_path, endpoint=mcp_gateway, methods=["GET", "POST", "DELETE", "OPTIONS"])
    )


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


# Swagger UI ships a light-only stylesheet, and the Flutter app embeds this page
# in an iframe -- so in dark mode (the app follows the OS setting) the docs were
# a white sheet inside a navy app. Same palette as `frontend/lib/core/theme.dart`.
_SWAGGER_DARK_CSS = """
<style>
:root { color-scheme: light dark; }
@media (prefers-color-scheme: dark) {
  html, body { background: #17252b; }
  .swagger-ui, .swagger-ui .info .title, .swagger-ui .info li, .swagger-ui .info p,
  .swagger-ui .info table, .swagger-ui .opblock-tag,
  .swagger-ui .opblock .opblock-summary-description,
  .swagger-ui .opblock .opblock-section-header h4, .swagger-ui .opblock-description-wrapper p,
  .swagger-ui .opblock-external-docs-wrapper p, .swagger-ui .opblock-title_normal p,
  .swagger-ui .parameter__name, .swagger-ui .parameter__type, .swagger-ui .parameter__in,
  .swagger-ui table thead tr th, .swagger-ui table thead tr td, .swagger-ui .tab li,
  .swagger-ui .response-col_status, .swagger-ui .response-col_links, .swagger-ui label,
  .swagger-ui .model, .swagger-ui .model-title, .swagger-ui section.models h4,
  .swagger-ui .responses-inner h4, .swagger-ui .responses-inner h5,
  .swagger-ui .scheme-container .schemes > label, .swagger-ui .dialog-ux .modal-ux-header h3,
  .swagger-ui .dialog-ux .modal-ux-content p, .swagger-ui .dialog-ux .modal-ux-content h4,
  .swagger-ui .markdown p,
  .swagger-ui .renderedMarkdown p, .swagger-ui .prop-type { color: #e3e6e7; }
  .swagger-ui .info a,
  .swagger-ui .info .base-url, .swagger-ui .opblock-tag small { color: #72d6b0; }
  .swagger-ui .scheme-container { background: #1f2f36; box-shadow: 0 1px 2px rgba(0,0,0,.4); }
  .swagger-ui .opblock-tag { border-bottom-color: #3b4a50; }
  .swagger-ui .opblock .opblock-section-header { background: #1f2f36; box-shadow: none; }
  .swagger-ui .opblock .opblock-summary-path,
  .swagger-ui .opblock .opblock-summary-path__deprecated { color: #e3e6e7; }
  .swagger-ui .opblock.opblock-get { background: rgba(97,175,254,.10); }
  .swagger-ui .opblock.opblock-post { background: rgba(73,204,144,.10); }
  .swagger-ui .opblock.opblock-put { background: rgba(252,161,48,.10); }
  .swagger-ui .opblock.opblock-delete { background: rgba(249,62,62,.10); }
  .swagger-ui .opblock.opblock-patch { background: rgba(80,227,194,.10); }
  .swagger-ui .opblock-body pre.microlight { background: #0f1a1f !important; }
  .swagger-ui input[type=text], .swagger-ui input[type=password], .swagger-ui input[type=search],
  .swagger-ui input[type=email], .swagger-ui textarea, .swagger-ui select {
    background: #1f2f36; color: #e3e6e7; border-color: #3b4a50; }
  .swagger-ui .btn { color: #e3e6e7; border-color: #72d6b0; background: transparent; }
  .swagger-ui .btn.authorize { color: #72d6b0; }
  .swagger-ui .btn.authorize svg { fill: #72d6b0; }
  .swagger-ui .model-box, .swagger-ui section.models, .swagger-ui .dialog-ux .modal-ux {
    background: #1f2f36; border-color: #3b4a50; }
  .swagger-ui section.models.is-open h4 { border-bottom-color: #3b4a50; }
  .swagger-ui .opblock-tag svg, .swagger-ui .opblock .opblock-summary-control svg,
  .swagger-ui .expand-methods svg, .swagger-ui .model-toggle:after { fill: #e3e6e7; }
  .swagger-ui table tbody tr td { border-bottom-color: #3b4a50; color: #e3e6e7; }
  .swagger-ui .info code, .swagger-ui .markdown code, .swagger-ui .renderedMarkdown code {
    background: #0f1a1f; color: #72d6b0; }
  .swagger-ui .topbar, .swagger-ui .loading-container .loading:after { color: #e3e6e7; }
}
</style>
"""


@app.get("/docs", include_in_schema=False)
async def swagger_ui() -> HTMLResponse:
    page = get_swagger_ui_html(openapi_url="/openapi.json", title=f"{app.title} - Swagger UI")
    html = bytes(page.body).decode().replace("</head>", f"{_SWAGGER_DARK_CSS}</head>", 1)
    return HTMLResponse(html)


class _WebApp(StaticFiles):
    """Serves a built Flutter web app, falling back to `index.html` for any
    path that doesn't resolve to an actual file.

    Flutter web's default (hash-based) routing never sends its client-side
    routes to the server at all -- a browser on `/#/routines/1` only ever
    requests `/` -- so in practice this fallback is a safety net for the odd
    direct request to a path that isn't a real asset, not something the app
    relies on to navigate.
    """

    async def get_response(self, path: str, scope: Scope) -> Response:
        try:
            return await super().get_response(path, scope)
        except StarletteHTTPException as exc:
            if exc.status_code == 404:
                return await super().get_response("index.html", scope)
            raise


def _mount_web_ui(app: FastAPI, web_dir: Path) -> None:
    """Serves a built Flutter web app under `/`, mounted last and
    deliberately not itself an included router -- every path above
    (including `/health`) is matched first, so this only ever serves what
    nothing else claimed. A no-op when `web_dir` doesn't exist, which is the
    common case outside the Docker image (`just backend run`, these tests)
    -- see `Settings.web_dir`.
    """
    if web_dir.is_dir():
        app.mount("/", _WebApp(directory=web_dir, html=True), name="web-ui")


_mount_web_ui(app, Path(get_settings().web_dir))
