import os
import time
import threading
import math
from flask import Flask, jsonify, request

app = Flask(__name__)

SERVICE_NAME = "service-orders"
VERSION = "1.0.0"

MOCK_ORDERS = [
    {"id": "ORD-1001", "customer": "alice@example.com", "total": 149.99, "status": "shipped", "items": 3},
    {"id": "ORD-1002", "customer": "bob@example.com", "total": 89.50, "status": "processing", "items": 1},
    {"id": "ORD-1003", "customer": "carol@example.com", "total": 299.00, "status": "delivered", "items": 5},
    {"id": "ORD-1004", "customer": "dave@example.com", "total": 45.00, "status": "pending", "items": 2},
    {"id": "ORD-1005", "customer": "eve@example.com", "total": 520.75, "status": "shipped", "items": 8},
]


@app.route("/health")
def health():
    return jsonify({
        "service": SERVICE_NAME,
        "version": VERSION,
        "status": "healthy",
        "timestamp": time.time(),
    })


@app.route("/orders")
def orders():
    return jsonify({
        "service": SERVICE_NAME,
        "count": len(MOCK_ORDERS),
        "orders": MOCK_ORDERS,
    })


def _cpu_burn(duration_sec):
    """Burn CPU with math operations for the given duration."""
    end = time.time() + duration_sec
    while time.time() < end:
        _ = math.factorial(950)
        _ = sum(math.sin(i) * math.cos(i) for i in range(500))


def _mem_burn(duration_sec, mb):
    """Allocate memory and hold it for the given duration."""
    blocks = []
    try:
        for _ in range(mb):
            blocks.append(bytearray(1024 * 1024))
        time.sleep(duration_sec)
    finally:
        del blocks


@app.route("/stress", methods=["POST", "GET"])
def stress():
    duration = int(request.args.get("duration", 30))
    threads = int(request.args.get("threads", 2))
    mem_mb = int(request.args.get("mem_mb", 0))

    duration = min(duration, 120)
    threads = min(threads, 4)
    mem_mb = min(mem_mb, 256)

    workers = []
    for _ in range(threads):
        t = threading.Thread(target=_cpu_burn, args=(duration,))
        t.start()
        workers.append(t)

    if mem_mb > 0:
        t = threading.Thread(target=_mem_burn, args=(duration, mem_mb))
        t.start()
        workers.append(t)

    for t in workers:
        t.join()

    return jsonify({
        "service": SERVICE_NAME,
        "stress": "completed",
        "duration_seconds": duration,
        "cpu_threads": threads,
        "memory_mb": mem_mb,
    })


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port)
