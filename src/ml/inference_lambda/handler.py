"""
Anomaly Detection Inference Lambda.

Trigger: EventBridge Schedule (repeat N minute)
Flow:
  1. Caculate time window 
  2. Read logs from S3 in window 
  3. Load model S3
  4. Extract features + score
  5. If anomaly → invoke Rollback Lambda + send SNS alert
"""

import boto3
import gzip
import json
import io
import os
import pickle
import numpy as np
from collections import defaultdict
from datetime import datetime, timezone, timedelta

# ── Config from env vars (set trong Terraform) ──────────────────────────────────
S3_BUCKET        = os.environ["S3_BUCKET"]           # zt-devsecops-logs
MODEL_KEY        = os.environ["MODEL_KEY"]            # model/auth_anomaly_detector.pkl
META_KEY         = os.environ["META_KEY"]             # model/auth_anomaly_metadata.json
WINDOW_MINUTES   = int(os.environ.get("WINDOW_MINUTES", "60"))
ROLLBACK_LAMBDA  = os.environ.get("ROLLBACK_LAMBDA_ARN", "")
SNS_TOPIC_ARN    = os.environ.get("SNS_TOPIC_ARN", "")
AWS_REGION       = os.environ.get("AWS_DEFAULT_REGION", "ap-southeast-1")
PREFIX           = os.environ.get("PREFIX", "network_aws")
APPS             = os.environ.get("APPS", "app2").split(",")  # comma-separated

s3_client     = boto3.client("s3",     region_name=AWS_REGION)
lambda_client = boto3.client("lambda", region_name=AWS_REGION)
sns_client    = boto3.client("sns",    region_name=AWS_REGION)
ssm_client    = boto3.client("ssm",    region_name=AWS_REGION)

# Cache model in Lambda execution context (warm start)
_model_cache = {}


# ── Model loading ─────────────────────────────────────────────────────────────

def load_model() -> tuple:
    """Load model + scaler + metadata from S3. Cache for reuse."""
    if "model" in _model_cache:
        return _model_cache["model"], _model_cache["scaler"], _model_cache["meta"]

    payload = s3_client.get_object(Bucket=S3_BUCKET, Key=MODEL_KEY)["Body"].read()
    obj     = pickle.loads(payload)

    meta_raw = s3_client.get_object(Bucket=S3_BUCKET, Key=META_KEY)["Body"].read()
    meta     = json.loads(meta_raw)

    _model_cache["model"]  = obj["model"]
    _model_cache["scaler"] = obj["scaler"]
    _model_cache["meta"]   = meta

    print(f"Model loaded (trained at {meta['trained_at']}, threshold={meta['threshold']:.4f})")
    return obj["model"], obj["scaler"], meta


# ── S3 data reading ───────────────────────────────────────────────────────────

def list_files_for_window(window_start: datetime, window_end: datetime) -> list[str]:
    """List S3 files can in  time window."""
    keys = []
    # Take files today (and yesterday if window over midnight)
    dates = {window_start.date(), window_end.date()}
    for d in dates:
        prefix = f"logs/{d.year}/{d.month:02d}/{d.day:02d}/"
        paginator = s3_client.get_paginator("list_objects_v2")
        for page in paginator.paginate(Bucket=S3_BUCKET, Prefix=prefix):
            for obj in page.get("Contents", []):
                if obj["Key"].endswith(".txt.gz"):
                    keys.append(obj["Key"])
    return keys


def read_records_in_window(keys: list[str],
                           window_start: datetime,
                           window_end: datetime) -> list[dict]:
    """Download files và filter records trong time window."""
    records = []
    for key in keys:
        try:
            compressed = s3_client.get_object(Bucket=S3_BUCKET, Key=key)["Body"].read()
            with gzip.open(io.BytesIO(compressed), "rt", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        rec = json.loads(line)
                    except json.JSONDecodeError:
                        continue

                    ts_str = rec.get("@timestamp", "")
                    if not ts_str:
                        continue
                    try:
                        ts = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
                    except ValueError:
                        continue

                    if window_start <= ts < window_end:
                        records.append(rec)
        except Exception as e:
            print(f"SKIP {key}: {e}")
    return records


# ── Feature extraction ────────────────────────────────────────────────────────

def extract_single_window_features(records: list[dict]) -> dict | None:
    """
    Extract features from records in 1 window.
    Return dict features or None if no data.
    """
    login_count = 0
    users       = set()
    source_ips  = set()
    machine_acc = 0
    ipv6_count  = 0
    failed      = 0

    for rec in records:
        if "winlog" not in rec:
            continue

        event_id = str(rec.get("winlog", {}).get("event_id", ""))
        result   = rec.get("auth", {}).get("result", "success")

        if event_id == "4625" or result == "failure":
            failed += 1
            continue
        if event_id != "4624":
            continue

        login_count += 1

        user = rec.get("user", {}).get("name", "")
        if user:
            users.add(user)
            if user.endswith("$"):
                machine_acc += 1

        src_ip = rec.get("source", {}).get("ip", "")
        if src_ip:
            source_ips.add(src_ip)
            if ":" in src_ip:
                ipv6_count += 1

    if login_count == 0 and failed == 0:
        return None

    total = max(login_count, 1)
    now   = datetime.now(timezone.utc)

    return {
        "login_count":           login_count,
        "unique_users":          len(users),
        "unique_source_ips":     len(source_ips),
        "machine_account_ratio": machine_acc / total,
        "ipv6_ratio":            ipv6_count / total,
        "failed_login_count":    failed,
        "hour_of_day":           now.hour,
        "day_of_week":           now.weekday(),
        "minute_of_hour":        now.minute,
    }


# ── Scoring ───────────────────────────────────────────────────────────────────

FEATURE_COLS = [
    "login_count",
    "unique_users",
    "unique_source_ips",
    "machine_account_ratio",
    "ipv6_ratio",
    "failed_login_count",
    "hour_of_day",
    "day_of_week",
]


def score_features(features: dict, model, scaler, threshold: float) -> dict:
    """Score 1 feature vector. Trả về result dict."""
    X = np.array([[features[c] for c in FEATURE_COLS]])
    X_scaled = scaler.transform(X)

    score     = float(model.score_samples(X_scaled)[0])
    is_anomaly = score < threshold

    return {
        "score":      score,
        "threshold":  threshold,
        "is_anomaly": is_anomaly,
        "features":   features,
    }


# ── Actions ───────────────────────────────────────────────────────────────────

def send_alert(result: dict, window_start: datetime, window_end: datetime):
    """Gửi SNS alert khi phát hiện anomaly."""
    if not SNS_TOPIC_ARN:
        print("SNS_TOPIC_ARN not set, skipping alert")
        return

    message = {
        "subject":    "ANOMALY DETECTED - Windows Auth",
        "window":     f"{window_start.isoformat()} → {window_end.isoformat()}",
        "score":      result["score"],
        "threshold":  result["threshold"],
        "features":   result["features"],
        "action":     "Rollback triggered" if ROLLBACK_LAMBDA else "Alert only",
    }

    sns_client.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject="[ANOMALY] Windows Auth Anomaly Detected",
        Message=json.dumps(message, indent=2),
    )
    print(f"SNS alert sent to {SNS_TOPIC_ARN}")


def trigger_rollback(app: str):
    """Invoke Rollback Lambda cho app chỉ định."""
    if not ROLLBACK_LAMBDA:
        print("ROLLBACK_LAMBDA_ARN not set, skipping rollback")
        return

    response = lambda_client.invoke(
        FunctionName=ROLLBACK_LAMBDA,
        InvocationType="Event",  # async
        Payload=json.dumps({"app": app}).encode(),
    )
    print(f"Rollback triggered for app={app}, status={response['StatusCode']}")


def promote_to_stable(app: str):
    """Promote pending-tag → stable-tag khi không có anomaly."""
    try:
        pending = ssm_client.get_parameter(
            Name=f"/{PREFIX}/{app}/pending-tag"
        )["Parameter"]["Value"]

        if pending == "none":
            print(f"[{app}] No pending tag, skipping promote")
            return

        ssm_client.put_parameter(
            Name=f"/{PREFIX}/{app}/stable-tag",
            Value=pending,
            Type="String",
            Overwrite=True,
        )
        print(f"[{app}] Promoted: pending={pending} → stable")
    except Exception as e:
        print(f"[{app}] Promote failed: {e}")


# ── Handler ───────────────────────────────────────────────────────────────────

def handler(event, context):
    now          = datetime.now(timezone.utc)
    window_end   = now.replace(second=0, microsecond=0)
    window_start = window_end - timedelta(minutes=WINDOW_MINUTES)

    print(f"Window: {window_start.isoformat()} → {window_end.isoformat()}")

    # 1. Load model
    model, scaler, meta = load_model()
    threshold = meta["threshold"]

    # 2. Read logs in window
    keys    = list_files_for_window(window_start, window_end)
    records = read_records_in_window(keys, window_start, window_end)
    print(f"Found {len(keys)} S3 files, {len(records)} records in window")

    if not records:
        print("No records in window, skipping")
        return {"statusCode": 200, "body": "no_data"}

    # 3. Extract features
    features = extract_single_window_features(records)
    if features is None:
        print("No auth records in window, skipping")
        return {"statusCode": 200, "body": "no_auth_data"}

    # 4. Score
    result = score_features(features, model, scaler, threshold)
    print(f"Score: {result['score']:.4f} (threshold={threshold:.4f}) → {'ANOMALY' if result['is_anomaly'] else 'normal'}")

    # 5. Action based on result
    if result["is_anomaly"]:
        print("ANOMALY DETECTED!")
        send_alert(result, window_start, window_end)
        for app in APPS:
            trigger_rollback(app.strip())
    else:
        for app in APPS:
            promote_to_stable(app.strip())

    return {
        "statusCode": 200,
        "body": json.dumps({
            "window_start": window_start.isoformat(),
            "window_end":   window_end.isoformat(),
            "score":        result["score"],
            "threshold":    threshold,
            "is_anomaly":   result["is_anomaly"],
            "features":     result["features"],
        }),
    }
