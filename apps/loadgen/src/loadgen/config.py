from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Loadgen configuration, read from environment variables.

    pydantic-settings maps TARGET_URL -> target_url etc. automatically,
    so the Kubernetes ConfigMap keys stay SCREAMING_SNAKE_CASE.
    """

    target_url: str = "http://obs-sim:8000"
    rps: float = 2.0
    error_rate: float = 0.1
    slow_rate: float = 0.1
    concurrency: int = 5
