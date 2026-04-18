"""
Train Isolation Forest trên Windows auth features.
Lưu model + metadata lên S3.
"""

import boto3
import pickle
import json
import io
import numpy as np
import pandas as pd
from datetime import datetime, timezone
from dateutil.relativedelta import relativedelta
from sklearn.ensemble import IsolationForest
from sklearn.preprocessing import StandardScaler

import feature_extraction

S3_BUCKET  = "zt-devsecops-logs"
MODEL_KEY  = "model/auth_anomaly_detector.pkl"
META_KEY   = "model/auth_anomaly_metadata.json"
AWS_REGION = "ap-southeast-1"

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


def train(df: pd.DataFrame):
    """Train Isolation Forest, return (model, scaler, stats)."""
    X = df[FEATURE_COLS].values

    # Scale features
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)

    # Train Isolation Forest
    # contamination=0.05 → expect 5% data is anomaly
    model = IsolationForest(
        n_estimators=100,
        contamination=0.05,
        random_state=42,
        n_jobs=-1,
    )
    model.fit(X_scaled)

    # Calculate threshold from training scores
    scores = model.score_samples(X_scaled)
    threshold = float(np.percentile(scores, 5))  # 5th percentile = boundary

    stats = {
        "trained_at":    datetime.now(timezone.utc).isoformat(),
        "n_samples":     len(df),
        "feature_cols":  FEATURE_COLS,
        "threshold":     threshold,
        "score_mean":    float(scores.mean()),
        "score_std":     float(scores.std()),
        "training_months": ["01", "02", "03"],
    }

    return model, scaler, stats


def save_to_s3(model, scaler, stats):
    """Upload model + metadata lên S3."""
    s3 = boto3.client("s3", region_name=AWS_REGION)

    # Serialize model + scaler together
    payload = pickle.dumps({"model": model, "scaler": scaler})
    s3.put_object(Bucket=S3_BUCKET, Key=MODEL_KEY, Body=payload)
    print(f"Model saved → s3://{S3_BUCKET}/{MODEL_KEY}")

    # Metadata (JSON, human-readable)
    s3.put_object(
        Bucket=S3_BUCKET,
        Key=META_KEY,
        Body=json.dumps(stats, indent=2).encode(),
        ContentType="application/json",
    )
    print(f"Metadata saved → s3://{S3_BUCKET}/{META_KEY}")


def last_n_months(n: int = 3) -> list[str]:
    """Calculate n month earliest , return list ["01", "03", ...] """
    now = datetime.now(timezone.utc)
    months = []
    for i in range(1, n + 1):
        m = now - relativedelta(months=i)
        months.append(f"{m.month:02d}")
    return months


def main():
    import sys
    # Allow apply window_minutes via CLI: python train.py 15
    window_minutes = int(sys.argv[1]) if len(sys.argv) > 1 else 60

    # Automate take 3 month erliest instead of hardcode
    months = last_n_months(3)
    print(f"Training on months: {months}")

    print(f"=== Step 1: Feature extraction (window={window_minutes}min) ===")
    df = feature_extraction.run(months=months, window_minutes=window_minutes)

    if len(df) < 10:
        print(f"ERROR: Too few samples ({len(df)}), need at least 10")
        return

    print(f"\n=== Step 2: Training on {len(df)} buckets ===")
    model, scaler, stats = train(df)
    stats["window_minutes"]   = window_minutes
    stats["training_months"]  = months

    print(f"\nThreshold: {stats['threshold']:.4f}")
    print(f"Score mean: {stats['score_mean']:.4f} ± {stats['score_std']:.4f}")

    print("\n=== Step 3: Saving to S3 ===")
    save_to_s3(model, scaler, stats)

    print("\n=== Done ===")
    print(json.dumps(stats, indent=2))


if __name__ == "__main__":
    main()
