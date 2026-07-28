from functools import lru_cache

from pydantic import PostgresDsn, RedisDsn
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_name: str = "NovaShop API"
    app_version: str = "0.1.0"
    environment: str = "development"
    database_url: PostgresDsn = PostgresDsn(
        "postgresql://novashop:novashop@postgres:5432/novashop"
    )
    redis_url: RedisDsn = RedisDsn("redis://redis:6379/0")


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
