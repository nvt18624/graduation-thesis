#!/bin/bash
set -e
# =================================================

# ================= ENV ==========================
export PATH="/usr/local/bin:/opt/semgrep-venv/bin:/usr/bin:/bin:$PATH"
export HOME="/var/opt/gitlab"
export SEMGREP_SETTINGS_FILE="/var/opt/gitlab/.semgrep/settings.yml"
export SEMGREP_SEND_METRICS=off

# ================= CONFIG =======================
LOG_DIR="/var/log/gitlab/semgrep"
LOG_FILE="${LOG_DIR}/gate.log"
TEMP_BASE="/tmp/semgrep-scans"
STRICT_BRANCHES=("main" "master" "developer" "production" "dev1" "dev2")
WARN_ONLY_BRANCHES=("feature")
export LOGSTASH_URL="${LOGSTASH_URL:-http://52.221.228.172:8080}"

# ================= BRANCH OWNERS ================
declare -A BRANCH_OWNERS=(
  ["dev1"]="dev1"
  ["dev2"]="dev2"
)
# =================================================

mkdir -p "$LOG_DIR"
mkdir -p "$TEMP_BASE"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
  echo "[$(date '+%F %T')] [$GL_PROJECT_PATH] [$GL_USERNAME] $1" | tee -a "$LOG_FILE"
}

# ===============================================
# Function: push log lên Logstash — dont block hook if fail
# ===============================================
send_log() {
  local PAYLOAD="$1"
  curl -s --max-time 5 -X POST "${LOGSTASH_URL}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" >> "$LOG_FILE" 2>&1 || true
}

# ===============================================
# Check Semgrep
# ===============================================
if ! command -v semgrep &> /dev/null; then
  log "ERROR: semgrep not installed"
  echo -e "${RED}Semgrep not installed${NC}"
  exit 1
fi

log "============================================="
log "Semgrep Quality Gate Started"
log "Project: $GL_PROJECT_PATH | User: $GL_USERNAME"

# ===============================================
# Function: scan 1 commit — return TOTAL findings
# ===============================================
scan_commit() {
  local COMMIT=$1
  local BRANCH=$2
  SCAN_ID="$(date +%s)-$$-${COMMIT:0:8}"
  TEMP_DIR="${TEMP_BASE}/scan-${SCAN_ID}"
  mkdir -p "$TEMP_DIR"
  chmod 700 "$TEMP_DIR"
  SCAN_START=$(date +%s)

  # Extract code
  if ! git archive --format=tar "$COMMIT" | tar -xC "$TEMP_DIR" 2>> "$LOG_FILE"; then
    log "git archive failed for $COMMIT"
    rm -rf "$TEMP_DIR"
    send_log "{
      \"@timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
      \"event_type\":\"pre_receive_scan\",
      \"project\":\"${GL_PROJECT_PATH}\",
      \"error\":\"git_archive_failed\",
      \"gate_passed\":false,
      \"message\":\"Pre-receive scan error\"
    }"
    echo "0"
    return
  fi

  SECRET_OUTPUT="${TEMP_DIR}/secrets.json"
  SMELL_OUTPUT="${TEMP_DIR}/smells.json"

  set +e
  semgrep scan \
    --config=p/secrets \
    --config=p/gitleaks \
    --config=/opt/semgrep-rules/secrets.yaml \
    --json --output="$SECRET_OUTPUT" \
    --quiet --no-error --timeout 60 \
    "$TEMP_DIR" >> "$LOG_FILE" 2>&1

  semgrep scan \
    --config=p/bandit \
    --json --output="$SMELL_OUTPUT" \
    --quiet --no-error --timeout 60 \
    "$TEMP_DIR" >> "$LOG_FILE" 2>&1
  set -e

  SCAN_END=$(date +%s)
  SCAN_DURATION=$((SCAN_END - SCAN_START))

  # Deduplicate and count
  SECRET_COUNT=$(python3 -c "
import json
try:
  d=json.load(open('$SECRET_OUTPUT'))
  seen=set()
  count=0
  for r in d.get('results',[]):
    key=f\"{r.get('path','')}:{r.get('start',{}).get('line','')}\"
    if key not in seen:
      seen.add(key)
      count+=1
  print(count)
except: print(0)
" 2>/dev/null || echo "0")

  SMELL_COUNT=$(python3 -c "
import json
try:
  d=json.load(open('$SMELL_OUTPUT'))
  seen=set()
  count=0
  for r in d.get('results',[]):
    key=f\"{r.get('path','')}:{r.get('start',{}).get('line','')}\"
    if key not in seen:
      seen.add(key)
      count+=1
  print(count)
except: print(0)
" 2>/dev/null || echo "0")

  TOTAL=$((SECRET_COUNT + SMELL_COUNT))
  RISK=$((SECRET_COUNT * 10 + SMELL_COUNT * 3))

  # Top rules policy  
  TOP_RULES=$(python3 -c "
import json
from collections import Counter
rules=[]
for f in ['$SECRET_OUTPUT','$SMELL_OUTPUT']:
  try:
    d=json.load(open(f))
    rules+=[r.get('check_id','').split('.')[-1] for r in d.get('results',[])]
  except: pass
top=';'.join([k for k,_ in Counter(rules).most_common(3)])
print(top if top else 'none')
" 2>/dev/null || echo "none")

  log "Commit=${COMMIT:0:8} secrets=$SECRET_COUNT smells=$SMELL_COUNT total=$TOTAL duration=${SCAN_DURATION}s"

  # ─── push log every commit to Logstash ───
  send_log "{
    \"@timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
    \"event_type\":\"pre_receive_scan\",
    \"project\":\"${GL_PROJECT_PATH}\",
    \"user\":\"${GL_USERNAME}\",
    \"branch\":\"${BRANCH}\",
    \"commit\":\"${COMMIT:0:8}\",
    \"duration_seconds\":${SCAN_DURATION},
    \"findings\":{
      \"secrets\":${SECRET_COUNT},
      \"code_smells\":${SMELL_COUNT},
      \"total\":${TOTAL},
      \"top_rules\":\"${TOP_RULES}\"
    },
    \"risk_score\":${RISK},
    \"gate_passed\":$([ ${TOTAL} -eq 0 ] && echo true || echo false),
    \"status\":\"$([ ${TOTAL} -eq 0 ] && echo passed || echo findings_found)\",
    \"message\":\"Pre-receive commit scan completed\"
  }"

  # detail findings
  if [ "$SECRET_COUNT" -gt 0 ]; then
    echo ""
    echo -e "${RED} SECRET in commit ${COMMIT:0:8}: $SECRET_COUNT findings${NC}"
    python3 -c "
import json
try:
  d=json.load(open('$SECRET_OUTPUT'))
  seen=set()
  for r in d.get('results',[]):
    path=r.get('path','').replace('$TEMP_DIR/','')
    line=r.get('start',{}).get('line','?')
    rule=r.get('check_id','').split('.')[-1]
    key=f'{path}:{line}'
    if key not in seen:
      seen.add(key)
      print(f'   • {path}:{line} → {rule}')
except: pass
" 2>/dev/null || true
  fi

  if [ "$SMELL_COUNT" -gt 0 ]; then
    echo ""
    echo -e "${YELLOW} CODE SMELL in commit ${COMMIT:0:8}: $SMELL_COUNT findings${NC}"
    python3 -c "
import json
try:
  d=json.load(open('$SMELL_OUTPUT'))
  seen=set()
  for r in d.get('results',[]):
    path=r.get('path','').replace('$TEMP_DIR/','')
    line=r.get('start',{}).get('line','?')
    rule=r.get('check_id','').split('.')[-1]
    msg=r.get('extra',{}).get('message','')[:60]
    key=f'{path}:{line}'
    if key not in seen:
      seen.add(key)
      print(f'   • {path}:{line} → {rule}: {msg}')
except: pass
" 2>/dev/null || true
  fi

  rm -rf "$TEMP_DIR"
  echo "$TOTAL"
}

# ===============================================
# Process Push
# ===============================================
while read oldrev newrev refname; do
  branch="${refname##refs/heads/}"
  PUSH_START=$(date +%s)
  log "Branch=$branch NewRev=$newrev OldRev=$oldrev"

  # ─────────────────────────────────────
  # Check branch ownership
  # ─────────────────────────────────────
  if [[ -n "${BRANCH_OWNERS[$branch]}" ]]; then
    ALLOWED_USER="${BRANCH_OWNERS[$branch]}"
    if [[ "$GL_USERNAME" != "$ALLOWED_USER" ]]; then
      echo ""
      echo -e "${RED}════════════════════════════════════════════════════${NC}"
      echo -e "${RED} PUSH REJECTED — Branch ownership violation${NC}"
      echo -e "${RED}════════════════════════════════════════════════════${NC}"
      echo ""
      echo "  Branch  : $branch"
      echo "  You     : $GL_USERNAME"
      echo "  Owner   : $ALLOWED_USER"
      echo ""
      echo "  Only [$ALLOWED_USER] just push to branch [$branch]!"
      echo ""
      log "REJECTED: $GL_USERNAME tried to push to $branch (owner: $ALLOWED_USER)"
      send_log "{
        \"@timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
        \"event_type\":\"pre_receive_ownership_violation\",
        \"project\":\"${GL_PROJECT_PATH}\",
        \"user\":\"${GL_USERNAME}\",
        \"branch\":\"${branch}\",
        \"allowed_user\":\"${ALLOWED_USER}\",
        \"gate_passed\":false,
        \"decision\":\"block\",
        \"message\":\"Branch ownership violation\"
      }"
      exit 1
    fi
  fi

  # ─────────────────────────────────────
  # Skip delete branch
  # ─────────────────────────────────────
  if [[ "$newrev" == "0000000000000000000000000000000000000000" ]]; then
    log "Skip: branch deleted"
    continue
  fi

  # ─────────────────────────────────────
  # Verify strict mode
  # ─────────────────────────────────────
  STRICT_MODE=false
  for b in "${STRICT_BRANCHES[@]}"; do
    if [[ "$branch" == "$b" ]]; then
      STRICT_MODE=true
      break
    fi
  done

  # ─────────────────────────────────────
  # Take all commits in push
  # ─────────────────────────────────────
  if [[ "$oldrev" == "0000000000000000000000000000000000000000" ]]; then
    COMMITS="$newrev"
    COMMIT_COUNT=1
    log "New branch — scanning HEAD only"
  else
    COMMITS=$(git rev-list "$oldrev..$newrev" 2>/dev/null || echo "$newrev")
    COMMIT_COUNT=$(echo "$COMMITS" | wc -l | tr -d ' ')
    log "Scanning $COMMIT_COUNT commits in this push"
    echo ""
    echo -e "${BLUE} Found $COMMIT_COUNT commit(s) to scan${NC}"
  fi

  # ─────────────────────────────────────
  # Scan every commit
  # ─────────────────────────────────────
  PUSH_BLOCKED=false
  BLOCKED_LIST=""
  GRAND_TOTAL_SECRETS=0
  GRAND_TOTAL_SMELLS=0

  for COMMIT in $COMMITS; do
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE} Commit: ${COMMIT:0:8} — Branch: [$branch] by $GL_USERNAME${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"

    RESULT=$(scan_commit "$COMMIT" "$branch")
    COMMIT_TOTAL=$(echo "$RESULT" | tail -1 | tr -d '[:space:]')

    # take count to log
    LAST_LOG=$(grep "Commit=${COMMIT:0:8}" "$LOG_FILE" | tail -1)
    C_SEC=$(echo "$LAST_LOG" | grep -oP 'secrets=\K[0-9]+' || echo "0")
    C_SME=$(echo "$LAST_LOG" | grep -oP 'smells=\K[0-9]+' || echo "0")
    GRAND_TOTAL_SECRETS=$((GRAND_TOTAL_SECRETS + C_SEC))
    GRAND_TOTAL_SMELLS=$((GRAND_TOTAL_SMELLS + C_SME))

    if [[ "$COMMIT_TOTAL" =~ ^[0-9]+$ ]] && [ "$COMMIT_TOTAL" -gt 0 ]; then
      PUSH_BLOCKED=true
      BLOCKED_LIST="$BLOCKED_LIST ${COMMIT:0:8}"
    fi
  done

  PUSH_END=$(date +%s)
  PUSH_DURATION=$((PUSH_END - PUSH_START))
  GRAND_TOTAL=$((GRAND_TOTAL_SECRETS + GRAND_TOTAL_SMELLS))
  GRAND_RISK=$((GRAND_TOTAL_SECRETS * 10 + GRAND_TOTAL_SMELLS * 3))

  # ─────────────────────────────────────
  # Final Decision +  log push summary
  # ─────────────────────────────────────
  if $PUSH_BLOCKED; then
    if $STRICT_MODE; then
      FINAL_STATUS="blocked"
      FINAL_DECISION="block"
    else
      FINAL_STATUS="warning"
      FINAL_DECISION="warn"
    fi
  else
    FINAL_STATUS="passed"
    FINAL_DECISION="allow"
  fi

  send_log "{
    \"@timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
    \"event_type\":\"pre_receive_push_summary\",
    \"project\":\"${GL_PROJECT_PATH}\",
    \"user\":\"${GL_USERNAME}\",
    \"branch\":\"${branch}\",
    \"newrev\":\"${newrev:0:8}\",
    \"oldrev\":\"${oldrev:0:8}\",
    \"strict_mode\":${STRICT_MODE},
    \"commit_count\":${COMMIT_COUNT},
    \"duration_seconds\":${PUSH_DURATION},
    \"findings\":{
      \"secrets\":${GRAND_TOTAL_SECRETS},
      \"code_smells\":${GRAND_TOTAL_SMELLS},
      \"total\":${GRAND_TOTAL},
      \"blocked_commits\":\"${BLOCKED_LIST}\"
    },
    \"risk_score\":${GRAND_RISK},
    \"gate_passed\":$([ \"${FINAL_DECISION}\" = \"allow\" ] && echo true || echo false),
    \"decision\":\"${FINAL_DECISION}\",
    \"status\":\"${FINAL_STATUS}\",
    \"message\":\"Pre-receive push gate: ${FINAL_STATUS}\"
  }"

  if [ "$FINAL_STATUS" = "blocked" ]; then
    echo ""
    echo -e "${RED}════════════════════════════════════════════════════${NC}"
    echo -e "${RED} PUSH BLOCKED — Branch: $branch${NC}"
    echo -e "${RED}════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Blocked commits  :$BLOCKED_LIST"
    echo "  Total secrets    : $GRAND_TOTAL_SECRETS"
    echo "  Total code smells: $GRAND_TOTAL_SMELLS"
    echo ""
    echo "  Fix ALL commits before pushing to [$branch]!"
    echo "  Hint: git rebase -i origin/$branch to squash/edit commits"
    echo "  See details at: $LOG_FILE"
    echo ""
    log "BLOCKED: branch=$branch commits=$BLOCKED_LIST secrets=$GRAND_TOTAL_SECRETS smells=$GRAND_TOTAL_SMELLS"
    exit 1

  elif [ "$FINAL_STATUS" = "warning" ]; then
    echo ""
    echo -e "${YELLOW}════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW} WARNING — Branch: $branch (push allowed)${NC}"
    echo -e "${YELLOW}════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Affected commits :$BLOCKED_LIST"
    echo "  Total secrets    : $GRAND_TOTAL_SECRETS"
    echo "  Total code smells: $GRAND_TOTAL_SMELLS"
    echo ""
    echo "  Fix before creating MR to main!"
    echo ""
    log "WARNING: branch=$branch commits=$BLOCKED_LIST secrets=$GRAND_TOTAL_SECRETS smells=$GRAND_TOTAL_SMELLS"

  else
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN} ALL COMMITS PASSED — Branch: $branch${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  No secrets detected"
    echo "  No code smells detected"
    echo ""
    log "PASSED: branch=$branch"
  fi

done

log "All checks completed"
log "============================================="
exit 0

