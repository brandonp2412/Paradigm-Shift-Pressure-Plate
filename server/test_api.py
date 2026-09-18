#!/usr/bin/env python3
"""Minimal FloorSense WebSocket smoke test.

The script deliberately avoids printing credentials, tokens, reservation IDs,
PINs, bank names, or raw private API responses.
"""

from __future__ import annotations

import hashlib
import json
import os
import time
from pathlib import Path

import websocket


DEFAULT_CREDS_PATH = Path(__file__).resolve().parent.parent / "credentials.json"
CREDS_PATH = Path(os.environ.get("FLOORSENSE_CREDENTIALS", DEFAULT_CREDS_PATH))


def load_credentials() -> dict[str, str]:
    if not CREDS_PATH.is_file():
        raise SystemExit(
            "Missing local credentials file. Copy credentials.example.json to "
            "credentials.json, populate it locally, and never commit it."
        )

    with CREDS_PATH.open(encoding="utf-8") as handle:
        creds = json.load(handle)

    required = ("socketURI", "controller_token", "uid", "uidToken")
    missing = [key for key in required if not creds.get(key)]
    if missing:
        raise SystemExit(f"Credentials file is missing required fields: {', '.join(missing)}")

    return creds


def receive_json(ws: websocket.WebSocket) -> dict:
    raw = ws.recv()
    if isinstance(raw, bytes):
        raw = raw.decode("utf-8")
    payload = json.loads(raw.rstrip("\r\n"))
    if not isinstance(payload, dict):
        raise RuntimeError("Unexpected non-object response from service")
    return payload


def main() -> None:
    creds = load_credentials()

    ws = websocket.WebSocket()
    ws.connect(
        creds["socketURI"],
        header={"Authorization": f"Bearer {creds['controller_token']}"},
    )

    try:
        auth_hash = hashlib.md5(str(int(time.time())).encode()).hexdigest()
        request = (
            "POST /auth\r\n"
            + json.dumps(
                {
                    "uid": creds["uid"],
                    "uidtoken": creds["uidToken"],
                    "auth": auth_hash,
                }
            )
            + "\r\n"
        )
        ws.send(request)
        response = receive_json(ws)

        if response.get("result") is not True:
            raise RuntimeError("Authentication was rejected")

        info = response.get("info")
        if not isinstance(info, dict):
            info = {}

        reservations = info.get("res")
        banks = info.get("bk")

        print("WebSocket authentication succeeded")
        print(f"Lockers enabled: {bool(info.get('lockers'))}")
        print(f"Desks enabled: {bool(info.get('desks'))}")
        print(f"Reservation count: {len(reservations) if isinstance(reservations, list) else 0}")
        print(f"Bank count: {len(banks) if isinstance(banks, list) else 0}")
    finally:
        ws.close()


if __name__ == "__main__":
    main()
