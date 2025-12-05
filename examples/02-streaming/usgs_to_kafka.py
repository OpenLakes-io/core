#!/usr/bin/env python3
"""
Fetch real-time USGS earthquake events and push them into a Kafka topic.
This script is triggered by Airflow so the ingest path is fully orchestrated.
"""
import argparse
import json
import sys
import time
from datetime import datetime, timezone

import requests
from kafka import KafkaProducer


def fetch_events(feed_url: str):
    response = requests.get(feed_url, timeout=20)
    response.raise_for_status()
    payload = response.json()
    return payload.get("features", [])


def main():
    parser = argparse.ArgumentParser(description="Stream USGS earthquake feed into Kafka")
    parser.add_argument("--feed-url", default="https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_hour.geojson")
    parser.add_argument("--bootstrap-servers", default="infrastructure-kafka.openlakes.svc.cluster.local:9092")
    parser.add_argument("--topic", default="usgs_quakes")
    parser.add_argument("--duration", type=int, default=300, help="Duration to stream in seconds")
    parser.add_argument("--poll-interval", type=int, default=30, help="Seconds between polls")

    args = parser.parse_args()

    producer = KafkaProducer(
        bootstrap_servers=args.bootstrap_servers,
        value_serializer=lambda v: json.dumps(v).encode("utf-8"),
    )

    end_time = time.time() + args.duration
    seen_ids = set()

    print(f"[{datetime.now(timezone.utc)}] Streaming USGS events from {args.feed_url} into topic '{args.topic}'")
    try:
        while time.time() < end_time:
            features = fetch_events(args.feed_url)
            sent = 0
            for feature in features:
                quake_id = feature.get("id")
                if not quake_id or quake_id in seen_ids:
                    continue
                seen_ids.add(quake_id)
                properties = feature.get("properties", {})
                geometry = feature.get("geometry", {})
                coords = geometry.get("coordinates", [None, None, None])

                payload = {
                    "event_id": quake_id,
                    "place": properties.get("place"),
                    "magnitude": properties.get("mag"),
                    "ts": properties.get("time"),
                    "longitude": coords[0],
                    "latitude": coords[1],
                    "depth_km": coords[2],
                }
                producer.send(args.topic, payload)
                sent += 1

            producer.flush()
            print(f"[{datetime.now(timezone.utc)}] Sent {sent} new events")
            time.sleep(args.poll_interval)
    except KeyboardInterrupt:
        print("Interrupted; shutting down gracefully...")
    finally:
        producer.close()
        print("Kafka producer closed.")


if __name__ == "__main__":
    sys.exit(main())
