from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.route("/health")
def health():
    return jsonify({"status": "ok", "version": os.getenv("APP_VERSION", "1.0.0")})

@app.route("/")
def index():
    return jsonify({"message": "Flask v1-clean — no findings expected"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=3000)
