"""Market-price event consumer for Amazon MSK or Azure Event Hubs.

The same client code runs against both platforms. Only configuration changes.
See ``producer/producer.py`` for the authentication notes: MSK uses TLS plus
SASL/OAUTHBEARER (AWS IAM), Event Hubs uses TLS plus SASL/PLAIN with the
connection string. Microsoft Entra ID (OAuth) is the preferred option for Event
Hubs wherever your client supports it.

Consumer group behaviour: all members that share ``KAFKA_GROUP_ID`` split the
partitions of the topic between them. With 4 partitions and 4 members, each
member owns exactly one partition. A 5th member would sit idle. The
``on_assign`` and ``on_revoke`` callbacks log which partitions this member owns.

Offsets are committed manually, only after an event has been processed
(at-least-once delivery). Processing must therefore be idempotent.
"""

from __future__ import annotations

import json
import logging
import os
import signal
import socket
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

from confluent_kafka import (
    Consumer,
    KafkaError,
    KafkaException,
    Message,
    TopicPartition,
)

LOG = logging.getLogger("consumer")

PLATFORMS = ("msk", "eventhubs")
REDACTED = "***REDACTED***"
SECRET_KEYS = ("sasl.password", "sasl.oauthbearer.config")


class ConfigError(Exception):
    """Raised when required configuration is missing or invalid."""


def _load_file(path: Optional[str]) -> Dict[str, Any]:
    """Load an optional YAML config file. Returns an empty dict if unset."""
    if not path:
        return {}
    file = Path(path)
    if not file.is_file():
        raise ConfigError(f"CONFIG_FILE points to a missing file: {path}")
    try:
        import yaml
    except ImportError as exc:  # pragma: no cover - depends on environment
        raise ConfigError("CONFIG_FILE needs PyYAML: pip install pyyaml") from exc
    with file.open("r", encoding="utf-8") as handle:
        data = yaml.safe_load(handle) or {}
    if not isinstance(data, dict):
        raise ConfigError(f"{path} must contain a YAML mapping at the top level")
    return data


class Settings:
    """Resolved runtime settings (secrets are excluded from ``repr``)."""

    def __init__(
        self,
        platform: str,
        topic: str,
        group_id: str,
        bootstrap_servers: str,
        aws_region: str,
        eventhubs_connection_string: str,
        client_id: str,
        auto_offset_reset: str,
    ) -> None:
        self.platform = platform
        self.topic = topic
        self.group_id = group_id
        self.bootstrap_servers = bootstrap_servers
        self.aws_region = aws_region
        self.eventhubs_connection_string = eventhubs_connection_string
        self.client_id = client_id
        self.auto_offset_reset = auto_offset_reset

    def __repr__(self) -> str:
        return (
            f"Settings(platform={self.platform!r}, topic={self.topic!r}, "
            f"group_id={self.group_id!r}, bootstrap_servers="
            f"{self.bootstrap_servers!r})"
        )


def load_settings(env: Optional[Dict[str, str]] = None) -> Settings:
    """Build :class:`Settings` from the config file and environment.

    Environment variables override values from the YAML file. Secrets are only
    accepted from the environment.

    Raises:
        ConfigError: if a required value is missing or invalid.
    """
    env = dict(os.environ) if env is None else env
    file_cfg = _load_file(env.get("CONFIG_FILE"))

    def pick(env_name: str, file_key: str, default: str = "") -> str:
        value = env.get(env_name)
        if value:
            return value
        return str(file_cfg.get(file_key, default) or default)

    platform = pick("KAFKA_PLATFORM", "platform").lower()
    if platform not in PLATFORMS:
        raise ConfigError(
            f"KAFKA_PLATFORM must be one of {', '.join(PLATFORMS)} (got '{platform}')"
        )

    bootstrap = pick("KAFKA_BOOTSTRAP_SERVERS", "bootstrap_servers")
    namespace = pick("EVENTHUBS_NAMESPACE", "eventhubs_namespace")
    if platform == "eventhubs" and not bootstrap and namespace:
        bootstrap = f"{namespace}.servicebus.windows.net:9093"

    settings = Settings(
        platform=platform,
        topic=pick("KAFKA_TOPIC", "topic", "market-events"),
        group_id=pick("KAFKA_GROUP_ID", "group_id", "search-service"),
        bootstrap_servers=bootstrap,
        aws_region=pick("AWS_REGION", "aws_region"),
        eventhubs_connection_string=env.get("EVENTHUBS_CONNECTION_STRING", ""),
        client_id=pick("KAFKA_CLIENT_ID", "client_id", socket.gethostname()),
        auto_offset_reset=pick(
            "KAFKA_AUTO_OFFSET_RESET", "auto_offset_reset", "earliest"
        ),
    )

    missing: List[str] = []
    if not settings.bootstrap_servers:
        hint = "KAFKA_BOOTSTRAP_SERVERS"
        if platform == "eventhubs":
            hint += " (or EVENTHUBS_NAMESPACE)"
        missing.append(hint)
    if platform == "msk" and not settings.aws_region:
        missing.append("AWS_REGION")
    if platform == "eventhubs" and not settings.eventhubs_connection_string:
        missing.append("EVENTHUBS_CONNECTION_STRING")
    if missing:
        raise ConfigError("Missing required configuration: " + ", ".join(missing))
    return settings


def make_msk_oauth_cb(region: str) -> Callable[[str], tuple]:
    """Return an ``oauth_cb`` that fetches short-lived MSK IAM tokens."""
    from aws_msk_iam_sasl_signer import MSKAuthTokenProvider

    def oauth_cb(_config: str) -> tuple:
        token, expiry_ms = MSKAuthTokenProvider.generate_auth_token(region)
        return token, expiry_ms / 1000.0

    return oauth_cb


def build_kafka_config(settings: Settings) -> Dict[str, Any]:
    """Return the confluent-kafka consumer configuration for the platform."""
    config: Dict[str, Any] = {
        "bootstrap.servers": settings.bootstrap_servers,
        "client.id": settings.client_id,
        "group.id": settings.group_id,
        "security.protocol": "SASL_SSL",
        "enable.auto.commit": False,
        "auto.offset.reset": settings.auto_offset_reset,
        "session.timeout.ms": 30000,
    }
    if settings.platform == "msk":
        config["sasl.mechanism"] = "OAUTHBEARER"
        config["oauth_cb"] = make_msk_oauth_cb(settings.aws_region)
    else:
        # Preferred for production: Microsoft Entra ID (OAuth) where your
        # client supports it. Connection string (SAS) is used here for
        # simplicity.
        config["sasl.mechanism"] = "PLAIN"
        config["sasl.username"] = "$ConnectionString"
        config["sasl.password"] = settings.eventhubs_connection_string
    return config


def redact(config: Dict[str, Any]) -> Dict[str, Any]:
    """Return a log-safe copy of ``config`` with secrets masked."""
    safe: Dict[str, Any] = {}
    for key, value in config.items():
        if key in SECRET_KEYS:
            safe[key] = REDACTED
        elif callable(value):
            safe[key] = "<callable>"
        else:
            safe[key] = value
    return safe


class JsonFormatter(logging.Formatter):
    """Format log records as one JSON object per line."""

    def format(self, record: logging.LogRecord) -> str:
        payload: Dict[str, Any] = {
            "ts": datetime.fromtimestamp(record.created, timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
        }
        payload.update(getattr(record, "ctx", {}))
        if record.exc_info:
            payload["exc"] = self.formatException(record.exc_info)
        return json.dumps(payload, default=str)


def setup_logging(level: str = "INFO") -> None:
    """Configure structured (JSON) logging to stdout."""
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    logging.basicConfig(level=level.upper(), handlers=[handler], force=True)


def log(level: int, msg: str, **ctx: Any) -> None:
    """Log ``msg`` with structured context fields."""
    LOG.log(level, msg, extra={"ctx": ctx})


def on_assign(consumer: Consumer, partitions: List[TopicPartition]) -> None:
    """Log the partitions this member now owns."""
    log(
        logging.INFO,
        "partitions assigned",
        owned=sorted(p.partition for p in partitions),
        topic=partitions[0].topic if partitions else None,
    )


def on_revoke(consumer: Consumer, partitions: List[TopicPartition]) -> None:
    """Commit processed offsets, then log the partitions being given up."""
    try:
        consumer.commit(asynchronous=False)
    except KafkaException as exc:
        # NO_OFFSET means nothing was consumed yet, which is fine.
        if exc.args[0].code() != KafkaError._NO_OFFSET:
            log(logging.ERROR, "commit on revoke failed", error=str(exc))
    log(
        logging.INFO,
        "partitions revoked",
        released=sorted(p.partition for p in partitions),
    )


def process(event: Dict[str, Any], msg: Message) -> None:
    """Handle one event. Replace with real downstream work (index, store, ...).

    Must be idempotent: after a crash or rebalance an event can be redelivered.
    """
    log(
        logging.INFO,
        "received",
        partition=msg.partition(),
        offset=msg.offset(),
        key=msg.key().decode() if msg.key() else None,
        symbol=event.get("symbol"),
        price=event.get("price"),
    )


def handle_message(msg: Message) -> None:
    """Decode and process a message. Poison messages are logged and skipped."""
    try:
        event = json.loads(msg.value().decode("utf-8"))
    except (ValueError, UnicodeDecodeError, AttributeError) as exc:
        log(
            logging.ERROR,
            "undecodable message skipped",
            partition=msg.partition(),
            offset=msg.offset(),
            error=str(exc),
        )
        return
    process(event, msg)


# Errors that will not fix themselves: stop instead of looping forever.
FATAL_CODES = (
    KafkaError._AUTHENTICATION,
    KafkaError.TOPIC_AUTHORIZATION_FAILED,
    KafkaError.GROUP_AUTHORIZATION_FAILED,
    KafkaError._ALL_BROKERS_DOWN,
)


def run(settings: Settings) -> int:
    """Consume until SIGINT/SIGTERM, committing after each processed event."""
    config = build_kafka_config(settings)
    log(
        logging.INFO,
        "starting consumer",
        platform=settings.platform,
        topic=settings.topic,
        group_id=settings.group_id,
        config=redact(config),
    )
    consumer = Consumer(config)
    stop = {"flag": False}

    def handle_signal(signum: int, _frame: Any) -> None:
        log(logging.INFO, "shutdown requested", signal=signum)
        stop["flag"] = True

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    exit_code = 0
    processed = 0
    try:
        consumer.subscribe([settings.topic], on_assign=on_assign, on_revoke=on_revoke)
        while not stop["flag"]:
            msg = consumer.poll(1.0)
            if msg is None:
                continue
            err = msg.error()
            if err is not None:
                if err.code() == KafkaError._PARTITION_EOF:
                    continue
                if err.code() in FATAL_CODES:
                    log(logging.CRITICAL, "fatal consumer error", error=str(err))
                    exit_code = 1
                    break
                log(logging.WARNING, "consumer error", error=str(err))
                continue
            handle_message(msg)
            # Commit only after processing succeeded (at-least-once).
            consumer.commit(message=msg, asynchronous=False)
            processed += 1
    except KafkaException as exc:
        log(logging.ERROR, "kafka exception", error=str(exc))
        exit_code = 1
    finally:
        log(logging.INFO, "closing consumer", processed=processed)
        try:
            consumer.commit(asynchronous=False)
        except KafkaException:
            pass  # nothing new to commit
        consumer.close()
    return exit_code


def main() -> int:
    """Entry point."""
    setup_logging(os.environ.get("LOG_LEVEL", "INFO"))
    try:
        settings = load_settings()
    except ConfigError as exc:
        print(f"Configuration error: {exc}", file=sys.stderr)
        return 2
    return run(settings)


if __name__ == "__main__":
    sys.exit(main())
