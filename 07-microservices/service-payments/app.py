import os
import time
from flask import Flask, jsonify

app = Flask(__name__)

SERVICE_NAME = "service-payments"
VERSION = "1.0.0"

MOCK_PAYMENTS = [
    {"id": "PAY-5001", "order_id": "ORD-1001", "amount": 149.99, "method": "credit_card", "status": "completed"},
    {"id": "PAY-5002", "order_id": "ORD-1002", "amount": 89.50, "method": "paypal", "status": "completed"},
    {"id": "PAY-5003", "order_id": "ORD-1003", "amount": 299.00, "method": "credit_card", "status": "refunded"},
]


@app.route("/health")
def health():
    return jsonify({
        "service": SERVICE_NAME,
        "version": VERSION,
        "status": "healthy",
        "timestamp": time.time(),
    })


@app.route("/payments")
def payments():
    return jsonify({
        "service": SERVICE_NAME,
        "count": len(MOCK_PAYMENTS),
        "payments": MOCK_PAYMENTS,
    })


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port)
