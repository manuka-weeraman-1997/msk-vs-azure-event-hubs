#!/usr/bin/env bash
# Remove the local virtualenv and Python caches.
#
# This does NOT destroy any cloud resources. To remove infrastructure run
# `terraform destroy` yourself in aws/terraform and/or azure/terraform after
# reviewing the plan.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "Removing .venv and Python caches under $ROOT"
rm -rf .venv
find . -type d -name "__pycache__" -prune -exec rm -rf {} +
find . -type d -name ".pytest_cache" -prune -exec rm -rf {} +
find . -type f -name "*.pyc" -delete

echo "Local cleanup complete."
echo "Cloud resources were NOT touched. To destroy them:"
echo "  (cd aws/terraform   && terraform destroy)"
echo "  (cd azure/terraform && terraform destroy)"
