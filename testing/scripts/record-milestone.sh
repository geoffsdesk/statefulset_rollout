#!/bin/bash
# Wrapper to record a milestone test session using `script`.
# Creates a timestamped terminal recording in the evidence directory.
#
# Usage: ./record-milestone.sh <milestone> [command...]
# Example: ./record-milestone.sh M3-manual bash
#          ./record-milestone.sh M2-preflight ./preflight.sh test-sts default
#
# If no command is given, starts an interactive shell session.
# Type `exit` to stop recording.

set -euo pipefail

MILESTONE="${1:?Usage: $0 <milestone> [command...]}"
shift

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EVIDENCE_DIR="$SCRIPT_DIR/../evidence/$MILESTONE"

if [ ! -d "$EVIDENCE_DIR" ]; then
  echo "ERROR: Evidence directory not found: $EVIDENCE_DIR"
  echo "Available milestones:"
  ls "$SCRIPT_DIR/../evidence/"
  exit 1
fi

TIMESTAMP=$(date +'%Y%m%d-%H%M%S')
RECORDING="$EVIDENCE_DIR/recording-${TIMESTAMP}.log"

echo "=================================================="
echo "  Recording milestone: $MILESTONE"
echo "  Output: $RECORDING"
echo "  Started: $(date)"
echo "=================================================="

if [ $# -gt 0 ]; then
  script -q "$RECORDING" -c "$*"
else
  echo "  Interactive session — type 'exit' to stop recording"
  echo "=================================================="
  script -q "$RECORDING"
fi

echo ""
echo "=================================================="
echo "  Recording saved: $RECORDING"
echo "  Size: $(du -h "$RECORDING" | cut -f1)"
echo "  Ended: $(date)"
echo "=================================================="
