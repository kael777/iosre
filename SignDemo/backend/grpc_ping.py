#!/usr/bin/env python3
"""Call SignDemo.Ping and print field numbers from the proto."""

from __future__ import annotations

import os
import sys
import time

import grpc

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(ROOT, "proto"))

import signdemo_pb2
import signdemo_pb2_grpc


def main() -> int:
    host = os.getenv("SIGNDEMO_GRPC_HOST", "127.0.0.1")
    port = os.getenv("SIGNDEMO_GRPC_PORT", "5445")
    target = f"{host}:{port}"
    ca_path = os.path.join(ROOT, "certs", "ca.crt")
    with open(ca_path, "rb") as handle:
        ca = handle.read()

    credentials = grpc.ssl_channel_credentials(root_certificates=ca)
    options = (("grpc.ssl_target_name_override", "localhost"),)
    request = signdemo_pb2.PingRequest(
        user_id="demo-user-001",
        timestamp=int(time.time()),
    )
    serialized = request.SerializeToString()

    with grpc.secure_channel(target, credentials, options=options) as channel:
        stub = signdemo_pb2_grpc.SignDemoStub(channel)
        reply = stub.Ping(request, timeout=5)

    print("target:", target)
    print("request user_id field number:", 1, "value:", request.user_id)
    print("request timestamp field number:", 2, "value:", request.timestamp)
    print("serialized protobuf bytes:", serialized.hex())
    print("reply ok field number:", 1, "value:", reply.ok)
    print("reply service field number:", 2, "value:", reply.service)
    print("reply time field number:", 3, "value:", reply.time)
    return 0 if reply.ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
