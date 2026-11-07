from pydantic import BaseModel, ConfigDict, EmailStr, Field


class UserCreate(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8)


class UserRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    email: str
    is_admin: bool


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"  # noqa: S105 -- an auth scheme name, not a secret


class AuthConfig(BaseModel):
    """What the login screen needs to know before anyone is signed in."""

    registration_enabled: bool


class AdminUserCreate(UserCreate):
    is_admin: bool = False


class AdminSettings(BaseModel):
    """Server-wide options an admin can change (`GET`/`PATCH /admin/settings`)."""

    allow_registration: bool
    # True when `DINATOS_ALLOW_REGISTRATION` is set: `allow_registration` shows
    # its value and cannot be changed here until the variable is cleared.
    allow_registration_locked: bool


class AdminSettingsUpdate(BaseModel):
    allow_registration: bool | None = None
