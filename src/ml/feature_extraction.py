"""
Feature extraction từ Windows auth logs (event_id 4624) trên S3.
Aggregate theo window_minutes → tạo feature vector cho training.

window_minutes: kích thước time window (mặc định 60 phút)
  - 1   → theo phút (rất chi tiết, cần nhiều data)
  - 15  → theo 15 phút
  - 60  → theo giờ (mặc định)
  - 1440 → theo ngày
"""

import boto3
import gzip
import json
import io
from collections import defaultdict
from datetime import datetime, timezone
import pandas as pd

S3_BUCKET  = "zt-devsecops-logs"
S3_PREFIX  = "logs/2026"
AWS_REGION = "ap-southeast-1"


def _bucket_key(ts: datetime, window_minutes: int) -> str:
    """
    Tạo key cho time bucket dựa trên window_minutes.
    Ví dụ window_minutes=15: "2026-01-07 08:15"
         window_minutes=60: "2026-01-07 08"
         window_minutes=1:  "2026-01-07 08:07"
    """
    total_minutes = ts.hour * 60 + ts.minute
    slot = (total_minutes // window_minutes) * window_minutes
    slot_hour = slot // 60
    slot_min  = slot % 60

    if window_minutes >= 60:
        return ts.strftime(f"%Y-%m-%d {slot_hour:02d}")
    else:
        return ts.strftime(f"%Y-%m-%d {slot_hour:02d}:{slot_min:02d}")


def _parse_key(key: str, window_minutes: int) -> datetime:
    """Parse bucket key ngược lại thành datetime."""
    if window_minutes >= 60:
        return datetime.strptime(key, "%Y-%m-%d %H")
    else:
        return datetime.strptime(key, "%Y-%m-%d %H:%M")


def list_all_files(s3_client, months: list[str]) -> list[str]:
    """List tất cả .txt.gz files trong các tháng chỉ định."""
    keys = []
    for month in months:
        paginator = s3_client.get_paginator("list_objects_v2")
        pages = paginator.paginate(
            Bucket=S3_BUCKET,
            Prefix=f"{S3_PREFIX}/{month}/"
        )
        for page in pages:
            for obj in page.get("Contents", []):
                if obj["Key"].endswith(".txt.gz"):
                    keys.append(obj["Key"])
    print(f"Found {len(keys)} files")
    return keys


def read_gz_file(s3_client, key: str) -> list[dict]:
    """Download và parse 1 file .txt.gz từ S3."""
    response = s3_client.get_object(Bucket=S3_BUCKET, Key=key)
    compressed = response["Body"].read()
    with gzip.open(io.BytesIO(compressed), "rt", encoding="utf-8") as f:
        records = []
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return records


def _empty_bucket() -> dict:
    return {
        "login_count":      0,
        "users":            set(),
        "source_ips":       set(),
        "machine_accounts": 0,
        "ipv6_count":       0,
        "failed_logins":    0,
    }


def extract_features_from_records(records: list[dict], window_minutes: int = 60) -> dict:
    """
    Aggregate records theo time window → feature buckets.
    Key format phụ thuộc vào window_minutes.
    """
    buckets = defaultdict(_empty_bucket)

    for rec in records:
        if "winlog" not in rec:
            continue

        ts_str = rec.get("@timestamp", "")
        if not ts_str:
            continue

        try:
            ts = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
        except ValueError:
            continue

        key    = _bucket_key(ts, window_minutes)
        bucket = buckets[key]

        event_id = str(rec.get("winlog", {}).get("event_id", ""))
        result   = rec.get("auth", {}).get("result", "success")

        if event_id == "4625" or result == "failure":
            bucket["failed_logins"] += 1
            continue

        if event_id != "4624":
            continue

        bucket["login_count"] += 1

        user = rec.get("user", {}).get("name", "")
        if user:
            bucket["users"].add(user)
            if user.endswith("$"):
                bucket["machine_accounts"] += 1

        src_ip = rec.get("source", {}).get("ip", "")
        if src_ip:
            bucket["source_ips"].add(src_ip)
            if ":" in src_ip:
                bucket["ipv6_count"] += 1

    return buckets


def build_feature_dataframe(buckets: dict, window_minutes: int = 60) -> pd.DataFrame:
    """Chuyển buckets thành DataFrame với numeric features."""
    rows = []
    for key, b in sorted(buckets.items()):
        total = b["login_count"]
        if total == 0:
            continue

        dt = _parse_key(key, window_minutes)

        rows.append({
            "window_key":            key,
            "login_count":           total,
            "unique_users":          len(b["users"]),
            "unique_source_ips":     len(b["source_ips"]),
            "machine_account_ratio": b["machine_accounts"] / total,
            "ipv6_ratio":            b["ipv6_count"] / total,
            "failed_login_count":    b["failed_logins"],
            "hour_of_day":           dt.hour,
            "day_of_week":           dt.weekday(),  # 0=Mon, 6=Sun
            "minute_of_hour":        dt.minute,     # 0 nếu window >= 60
        })

    return pd.DataFrame(rows)


def run(months: list[str] = ["01", "02", "03"],
        window_minutes: int = 60) -> pd.DataFrame:
    """
    Run all pipeline: list files → read → extract → DataFrame.

    Args:
        months:        list month can take 
        window_minutes: size time window (1, 5, 15, 60, 1440...)
    """
    s3 = boto3.client("s3", region_name=AWS_REGION)

    print(f"Window size: {window_minutes} minute(s)")
    all_keys = list_all_files(s3, months)

    combined = defaultdict(_empty_bucket)

    for i, key in enumerate(all_keys):
        if i % 50 == 0:
            print(f"Processing file {i+1}/{len(all_keys)}: {key}")
        try:
            records = read_gz_file(s3, key)
            buckets = extract_features_from_records(records, window_minutes)
            for bkey, b in buckets.items():
                c = combined[bkey]
                c["login_count"]      += b["login_count"]
                c["users"]            |= b["users"]
                c["source_ips"]       |= b["source_ips"]
                c["machine_accounts"] += b["machine_accounts"]
                c["ipv6_count"]       += b["ipv6_count"]
                c["failed_logins"]    += b["failed_logins"]
        except Exception as e:
            print(f"  SKIP {key}: {e}")
            continue

    df = build_feature_dataframe(combined, window_minutes)
    print(f"\nExtracted {len(df)} buckets ({window_minutes}min window) from {len(all_keys)} files")
    return df


if __name__ == "__main__":
    import sys
    window = int(sys.argv[1]) if len(sys.argv) > 1 else 60
    df = run(months=["01", "02", "03"], window_minutes=window)
    print(df.describe())
    df.to_csv(f"/tmp/features_{window}min.csv", index=False)
    print(f"Saved to /tmp/features_{window}min.csv")
