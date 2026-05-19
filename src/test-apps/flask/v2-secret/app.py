from flask import Flask, jsonify
import os

app = Flask(__name__)

# TC-04: hardcoded AWS credential — Semgrep p/secrets will flag this
AWS_ACCESS_KEY_ID     = "AKIAIOSFODNN7EXAMPLE"
AWS_SECRET_ACCESS_KEY = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"

@app.route("/health")
def health():
    return jsonify({"status": "ok"})

@app.route("/")
def index():
    return jsonify({"message": "Flask v2-secret — expect PUSH BLOCKED"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=3000)
