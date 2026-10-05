"""Market-price event producer for Amazon MSK or Azure Event Hubs.

The same client code runs against both platforms. Only configuration changes:

* ``KAFKA_PLATFORM=msk``: TLS + SASL/OAUTHBEARER using short-lived AWS IAM
  tokens (port 9098).
* ``KAFKA_PLATFORM=eventhubs``: TLS + SASL/PLAIN against the Event Hubs Kafka
  endpoint (port 9093). The username is the literal string ``$ConnectionString``
  and the password is the Event Hubs connection string.

Microsoft Entra ID (OAuth) is the preferred authentication option for Event
Hubs wherever your Kafka client supports it, because it avoids long-lived
shared keys. This sample uses the connection string path because it is the
simplest one to run and verify anywhere. See ../docs/security.md.

Configuration comes from an optional YAML file (``CONFIG_FILE``) and from
environment variables. Environment variables win over the file. Secrets are
read from the environment only and are never logged.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import random
import signal
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

from confluent_kafka import KafkaError, KafkaException, Message, Producer

LOG = logging.getLogger("producer")

PLATFORMS = ("msk", "eventhubs")
REDACTED = "***REDACTED***"
SECRET_KEYS = ("sasl.password", "sasl.oauthbearer.config")

# Base prices used to generate realistic-looking, jittered market data.
BASE_PRICES: Dict[str, float] = {
    "AAPL": 227.31,
    "MSFT": 415.10,
    "GOOG": 178.45,
    "AMZN": 189.80,
    "TSLA": 251.60,
    "NVDA": 120.75,
}


class ConfigError(Exception):
    """Raised when required configuration is missing or invalid."""


@dataclass
class Settings:
    """Resolved runtime settings."""

    platform: str
    topic: str = "market-events"
    bootstrap_servers: str = ""
    aws_region: str = ""
    eventhubs_connection_string: str = field(default="", repr=False)
    client_id: str = "market-producer"
    extra: Dict[str, str] = field(default_factory=dict)


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

    settings = Settings(
        platform=platform,
        topic=pick("KAFKA_TOPIC", "topic", "market-events"),
        bootstrap_servers=pick("KAFKA_BOOTSTRAP_SERVERS", "bootstrap_servers"),
        aws_region=pick("AWS_REGION", "aws_region"),
        eventhubs_connection_string=env.get("EVENTHUBS_CONNECTION_STRING", ""),
        client_id=pick("KAFKA_CLIENT_ID", "client_id", "market-producer"),
    )

    namespace = pick("EVENTHUBS_NAMESPACE", "eventhubs_namespace")
    if platform == "eventhubs" and not settings.bootstrap_servers and namespace:
        settings.bootstrap_servers = f"{namespace}.servicebus.windows.net:9093"

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
        # confluent-kafka expects expiry in seconds since the epoch.
        return token, expiry_ms / 1000.0

    return oauth_cb


def build_kafka_config(settings: Settings) -> Dict[str, Any]:
    """Return the confluent-kafka producer configuration for the platform."""
    config: Dict[str, Any] = {
        "bootstrap.servers": settings.bootstrap_servers,
        "client.id": settings.client_id,
        "security.protocol": "SASL_SSL",
        # Reliability: idempotent producer gives per-partition ordering and
        # no duplicates from retries. It implies acks=all.
        "enable.idempotence": True,
        "acks": "all",
        "retries": 10,
        "retry.backoff.ms": 200,
        "delivery.timeout.ms": 60000,
        "linger.ms": 20,
        "compression.type": "gzip",
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
        # Event Hubs does not support the idempotent producer over the Kafka
        # endpoint in every tier. Disable it and rely on retries; verify in
        # the current Microsoft docs for your tier.
        config["enable.idempotence"] = False
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


def generate_event(rng: random.Random) -> Dict[str, Any]:
    """Create one market-price event with a jittered price."""
    symbol = rng.choice(list(BASE_PRICES))
    price = BASE_PRICES[symbol] * (1 + rng.uniform(-0.01, 0.01))
    return {
        "event_type": "market-price",
        "symbol": symbol,
        "price": round(price, 2),
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }


class DeliveryStats:
    """Track delivery outcomes reported by the delivery callback."""

    def __init__(self) -> None:
        self.delivered = 0
        self.failed = 0

    def callback(self, err: Optional[KafkaError], msg: Message) -> None:
        """Delivery report callback invoked from ``poll``/``flush``."""
        if err is not None:
            self.failed += 1
            log(
                logging.ERROR,
                "delivery failed",
                error=str(err),
                topic=msg.topic(),
                key=msg.key().decode() if msg.key() else None,
            )
            return
        self.delivered += 1
        log(
            logging.INFO,
            "delivered",
            topic=msg.topic(),
            partition=msg.partition(),
            offset=msg.offset(),
            key=msg.key().decode() if msg.key() else None,
        )


def produce_one(
    producer: Producer, topic: str, event: Dict[str, Any], stats: DeliveryStats
) -> None:
    """Serialize and enqueue an event, keyed by symbol.

    Handles a full local queue by serving callbacks and retrying once.
    """
    value = json.dumps(event, separators=(",", ":")).encode("utf-8")
    key = event["symbol"].encode("utf-8")
    for attempt in (1, 2):
        try:
            producer.produce(topic, value=value, key=key, on_delivery=stats.callback)
            return
        except BufferError:
            log(logging.WARNING, "local queue full, waiting", attempt=attempt)
            producer.poll(1.0)
    raise KafkaException(KafkaError(KafkaError._QUEUE_FULL, "local queue full"))


def run(settings: Settings, count: int, rate: float, seed: Optional[int]) -> int:
    """Produce ``count`` events (0 = until interrupted) at ``rate`` per second."""
    config = build_kafka_config(settings)
    log(
        logging.INFO,
        "starting producer",
        platform=settings.platform,
        topic=settings.topic,
        config=redact(config),
    )
    config["error_cb"] = lambda err: log(logging.ERROR, "client error", error=str(err))
    producer = Producer(config)
    stats = DeliveryStats()
    rng = random.Random(seed)
    stop = {"flag": False}

    def handle_signal(signum: int, _frame: Any) -> None:
        log(logging.INFO, "shutdown requested", signal=signum)
        stop["flag"] = True

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    interval = 1.0 / rate if rate > 0 else 0.0
    sent = 0
    try:
        while not stop["flag"] and (count == 0 or sent < count):
            try:
                produce_one(producer, settings.topic, generate_event(rng), stats)
                sent += 1
            except KafkaException as exc:
                log(logging.ERROR, "produce failed", error=str(exc))
                time.sleep(1.0)
            producer.poll(0)
            if interval:
                time.sleep(interval)
    finally:
        log(logging.INFO, "flushing", pending=len(producer))
        remaining = producer.flush(30)
        log(
            logging.INFO,
            "producer stopped",
            enqueued=sent,
            delivered=stats.delivered,
            failed=stats.failed,
            undelivered=remaining,
        )
    return 0 if stats.failed == 0 and remaining == 0 else 1


def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description="Market-price event producer")
    parser.add_argument(
        "--count", type=int, default=20, help="events to send, 0 = run until stopped"
    )
    parser.add_argument(
        "--rate", type=float, default=5.0, help="events per second, 0 = unthrottled"
    )
    parser.add_argument("--seed", type=int, default=None, help="random seed")
    parser.add_argument(
        "--log-level", default=os.environ.get("LOG_LEVEL", "INFO"), help="log level"
    )
    return parser.parse_args(argv)


def main(argv: Optional[List[str]] = None) -> int:
    """Entry point."""
    args = parse_args(argv)
    setup_logging(args.log_level)
    try:
        settings = load_settings()
    except ConfigError as exc:
        print(f"Configuration error: {exc}", file=sys.stderr)
        return 2
    return run(settings, args.count, args.rate, args.seed)


if __name__ == "__main__":
    sys.exit(main())
