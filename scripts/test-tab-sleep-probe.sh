#!/bin/bash
# Execute the production tab-sleep JavaScript against controlled form and audio surfaces.
set -euo pipefail
cd "$(dirname "$0")/.."
node Tests/TabSleepProbeDOMTests.js
