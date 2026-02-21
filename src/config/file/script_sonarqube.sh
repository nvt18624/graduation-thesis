#!/bin/bash
set -e

# =================================================
# SONARQUBE QUALITY GATE - PRE-RECEIVE HOOK
# =================================================

# ================= CONFIG ========================
SONAR_URL="http://10.0.1.2:9000"
SONAR_TOKEN="sqa_278b9f304a025759a97c44a059761a8480a7b16e"
# =================================================

LOG_DIR="/var/log/gitlab/sonarqube"
LOG_FILE="${LOG_DIR}/gate.log"
TEMP_BASE="/tmp/sonar-scans"

mkdir -p "$LOG_DIR"
mkdir -p "$TEMP_BASE"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
  echo "[$(date '+%F %T')] [$GL_PROJECT_PATH] [$GL_USERNAME] $1" | tee -a "$LOG_FILE"
}

error_exit() {
  log "ERROR: $1"
  echo -e "${RED}$1${NC}"
  exit 1
}

log "============================================="
log "SonarQube Quality Gate Started"
log "Project: $GL_PROJECT_PATH"
log "User: $GL_USERNAME"

# ===============================================
# Check SonarQube
# ===============================================
if ! curl -s -f -u "${SONAR_TOKEN}:" \
  "${SONAR_URL}/api/system/status" \
  > /dev/null 2>&1; then
  error_exit "Cannot connect to SonarQube"
fi

log " SonarQube connected"

# ===============================================
# Process Push
# ===============================================
while read oldrev newrev refname; do

  branch="${refname##refs/heads/}"
  log "Branch=$branch Commit=$newrev"

  # Only protect main branches
  if [[ "$branch" != "main" && "$branch" != "master" && "$branch" != "develop" && "$branch" != "production" ]]; then
    log "Skip branch $branch"
    continue
  fi

  log "Protected branch → scanning"

  # Temp dir
  SCAN_ID="$(date +%s)-$$"
  TEMP_DIR="${TEMP_BASE}/scan-${SCAN_ID}"

  mkdir -p "$TEMP_DIR"
  chmod 700 "$TEMP_DIR"

  cleanup() {
    if [ -d "$TEMP_DIR" ]; then
      log "Cleanup: $TEMP_DIR"
      rm -rf "$TEMP_DIR"
    fi
  }
  trap cleanup EXIT

  log "Temp dir: $TEMP_DIR"

  # ===============================================
  # Extract code
  # ===============================================

  echo -e "${BLUE} Scanning code quality...${NC}"
  log "Extracting code from commit $newrev"

  if ! git archive --format=tar "$newrev" | tar -xC "$TEMP_DIR" 2>> "$LOG_FILE"; then
    log "git archive failed, trying alternative..."

    WORKTREE_DIR="${TEMP_BASE}/worktree-${SCAN_ID}"
    if git worktree add -f "$WORKTREE_DIR" "$newrev" >> "$LOG_FILE" 2>&1; then
      cp -r "$WORKTREE_DIR/." "$TEMP_DIR/"
      git worktree remove -f "$WORKTREE_DIR" >> "$LOG_FILE" 2>&1 || true
    else
      error_exit "Failed to extract code"
    fi
  fi

  cd "$TEMP_DIR"
  log "Code extracted successfully"

  # ===============================================
  # Project Key
  # ===============================================
  PROJECT_KEY="${GL_PROJECT_PATH//\//-}"
  log "ProjectKey=$PROJECT_KEY"

  # ===============================================
  # Sonar properties
  # ===============================================
  if [ ! -f sonar-project.properties ]; then
    log "Creating sonar-project.properties"
    cat > sonar-project.properties <<EOF
sonar.projectKey=${PROJECT_KEY}
sonar.projectName=${GL_PROJECT_PATH}
sonar.sources=.
sonar.sourceEncoding=UTF-8
sonar.exclusions=**/node_modules/**,**/vendor/**,**/tests/**,**/test/**,**/__pycache__/**,**/.venv/**,**/venv/**,**/*.test.js,**/*.spec.js
EOF
  fi

  # ===============================================
  # Run Scan - QUIET MODE
  # ===============================================
  log "Start scan"

  export SONAR_USER_HOME="/tmp/sonar-scanner-cache"
  mkdir -p "$SONAR_USER_HOME"

  START=$(date +%s)

  # Disable exit on error temporarily (Quality Gate fail returns non-zero)
  set +e

  /opt/sonar-scanner/bin/sonar-scanner \
      -Dsonar.projectKey="$PROJECT_KEY" \
      -Dsonar.projectName="$GL_PROJECT_PATH" \
      -Dsonar.sources=. \
      -Dsonar.host.url="$SONAR_URL" \
      -Dsonar.token="$SONAR_TOKEN" \
      -Dsonar.scm.revision="$newrev" \
      -Dsonar.qualitygate.wait=true \
      -Dsonar.qualitygate.timeout=300 \
      -Dsonar.log.level=WARN \
      >> "$LOG_FILE" 2>&1

  SCAN_EXIT_CODE=$?

  # Re-enable exit on error
  set -e

  unset SONAR_USER_HOME

  END=$(date +%s)
  DURATION=$((END-START))

  log "Scan completed (${DURATION}s) with exit code: $SCAN_EXIT_CODE"

  # ===============================================
  # Get Results
  # ===============================================

  log "Fetching Quality Gate status..."

  QG_RESPONSE=$(curl -s -u "${SONAR_TOKEN}:" \
    "${SONAR_URL}/api/qualitygates/project_status?projectKey=${PROJECT_KEY}")

  STATUS=$(echo "$QG_RESPONSE" | jq -r '.projectStatus.status')

  log "Quality Gate Status: $STATUS"

  # Get metrics
  METRICS=$(curl -s -u "${SONAR_TOKEN}:" \
    "${SONAR_URL}/api/measures/component?component=${PROJECT_KEY}&metricKeys=bugs,vulnerabilities,code_smells,security_hotspots,coverage")

  BUGS=$(echo "$METRICS" | jq -r '.component.measures[] | select(.metric=="bugs") | .value // "0"')
  VULNS=$(echo "$METRICS" | jq -r '.component.measures[] | select(.metric=="vulnerabilities") | .value // "0"')
  SMELLS=$(echo "$METRICS" | jq -r '.component.measures[] | select(.metric=="code_smells") | .value // "0"')
  HOTSPOTS=$(echo "$METRICS" | jq -r '.component.measures[] | select(.metric=="security_hotspots") | .value // "0"')
  COV=$(echo "$METRICS" | jq -r '.component.measures[] | select(.metric=="coverage") | .value // "0.0"')

  log "Metrics: Bugs=$BUGS, Vulns=$VULNS, Smells=$SMELLS, Hotspots=$HOTSPOTS, Cov=$COV%"

  # ===============================================
  # Decision
  # ===============================================

  if [[ "$STATUS" == "ERROR" ]]; then
    log " Quality Gate FAILED"

    echo ""
    echo -e "${RED}════════════════════════════════════════════════════${NC}"
    echo -e "${RED} QUALITY GATE FAILED - PUSH BLOCKED${NC}"
    echo -e "${RED}════════════════════════════════════════════════════${NC}"
    echo ""
    echo " Issues Found:"
    echo "   • Bugs: $BUGS"
    echo "   • Vulnerabilities: $VULNS"
    echo "   • Security Hotspots: $HOTSPOTS (need review)"
    echo "   • Code Smells: $SMELLS"
    echo "   • Coverage: $COV%"
    echo ""
    echo " Details: ${SONAR_URL}/dashboard?id=${PROJECT_KEY}"
    echo ""

    exit 1
  fi

  # ===============================================
  # Success
  # ===============================================
  log " Quality Gate PASSED"

  echo ""
  echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN} QUALITY GATE PASSED${NC}"
  echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
  echo ""
  echo " Code Quality:"
  echo "   • Bugs: $BUGS"
  echo "   • Vulnerabilities: $VULNS"
  echo "   • Code Smells: $SMELLS"
  echo "   • Coverage: $COV%"
  echo ""
  echo "  Scan: ${DURATION}s"
  echo ""

done

log "All checks passed"
log "============================================="
exit 0