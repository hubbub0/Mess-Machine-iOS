#!/usr/bin/env bash
# Quick checks before the build: no em dashes in anything Tyler reads (docs, code comments, on-screen words).
set -u
bad=$(grep -rIl $'\xe2\x80\x94' --include='*.md' --include='*.swift' --include='*.c' --include='*.h' --include='*.yml' --include='*.plist' . 2>/dev/null | grep -v '^./core/' || true)
if [ -n "$bad" ]; then
  echo "Em dashes found in:"; echo "$bad"; exit 1
fi
echo "precheck ok"
