from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """All configuration comes from environment variables (12-factor).

    In Kubernetes, MONGO_URI is injected from a Secret created by the MongoDB chart.
    """

    model_config = SettingsConfigDict(env_prefix="", case_sensitive=False)

    mongo_uri: str = "mongodb://localhost:27017"
    mongo_db: str = "articles"
    mongo_collection: str = "articles"
    mongo_timeout_ms: int = 3000
    log_level: str = "INFO"
    app_version: str = "1.0.0"


settings = Settings()
