#!/usr/bin/env python3
"""Minimal SignDemo gRPC server on TCP 5445. Does not replace Flask :5443."""

from __future__ import annotations

import os
import sys
import time
from concurrent import futures

import grpc

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(ROOT, "proto"))

import signdemo_pb2
import signdemo_pb2_grpc


class SignDemoService(signdemo_pb2_grpc.SignDemoServicer):
    def Ping(self, request, context):
        print(f"gRPC Ping user_id={request.user_id!r} timestamp={request.timestamp}")
        return signdemo_pb2.PingReply(
            ok=True,
            service="SignDemo",
            time=int(time.time()),
        )


def _cert_bytes(name: str) -> bytes:
    path = os.path.join(ROOT, "certs", name)
    with open(path, "rb") as handle:
        return handle.read()


def serve() -> None:
    port = os.getenv("SIGNDEMO_GRPC_PORT", "5445")
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=4))
    signdemo_pb2_grpc.add_SignDemoServicer_to_server(SignDemoService(), server)
    credentials = grpc.ssl_server_credentials(
        [(_cert_bytes("server.key"), _cert_bytes("server.crt"))]
    )
    bind = f"[::]:{port}"
    server.add_secure_port(bind, credentials)
    server.start()
    print(f"SignDemo gRPC https://0.0.0.0:{port}  (Ping)")
    print("字段编号：PingRequest.user_id=1 timestamp=2；PingReply.ok=1 service=2 time=3")
    server.wait_for_termination()


if __name__ == "__main__":
    serve()
