"""Optional local configuration reference.

The running service reads environment variables. Copy values into your shell
or use the defaults in app.py for the first experiment.
"""

SIGNDEMO_HOST = "0.0.0.0"
SIGNDEMO_PORT = 5000
SIGNDEMO_HTTPS_PORT = 5443
SIGNDEMO_TLS = "1"
SIGNDEMO_SECRET = "local-demo-secret-v1"
SIGNDEMO_TIME_WINDOW = 300
SIGNDEMO_WS_INTERVAL = 5
SIGNDEMO_GRPC_PORT = 5445
