import os

# Settings are read at import time, so the environment must be shaped before
# zino_agents is imported anywhere in the test session.
os.environ.setdefault("ZINO_ENV", "test")
os.environ.setdefault("ZINO_API_KEY", "test-key")
