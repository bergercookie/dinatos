from importlib.metadata import PackageNotFoundError, version

# The installed package's own version, so a release build (which stamps its
# version into pyproject.toml, see the Dockerfile) reports it, not a constant.
try:
    __version__ = version("dinatos-backend")
except PackageNotFoundError:  # run from a source tree that was never installed
    __version__ = "0.1.0"
