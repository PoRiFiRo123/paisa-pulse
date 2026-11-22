#!/usr/bin/env bash
# Paisa Pulse dev loop. Run from anywhere inside the repo.
#   dev.sh check        typecheck + lint + tests (what CI's "tests" job runs)
#   dev.sh test [pat]   jest, optionally filtered
#   dev.sh config       print the resolved Expo config, normal and free-signing
#   dev.sh ci [branch]  latest GitHub Actions run for a branch (default: current)
#   dev.sh logs [job]   failed-step logs of that run (job: android | ios | tests)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
REPO=PoRiFiRo123/paisa-pulse
cmd=${1:-check}; shift || true
case "$cmd" in
  check)  npm run typecheck && npm run lint && npx jest --ci ;;
  test)   npx jest "$@" ;;
  config) npx expo config --type public --json | node -e 'const c=JSON.parse(require("fs").readFileSync(0));console.log("normal:",c.plugins.length,"plugins",c.extra)'
          PAISA_FREE_SIGNING=1 npx expo config --type public --json | node -e 'const c=JSON.parse(require("fs").readFileSync(0));console.log("free:",c.plugins.length,"plugins",c.extra)' ;;
  ci)     b=${1:-$(git branch --show-current)}; gh run list -R $REPO -b "$b" -L 3
          id=$(gh run list -R $REPO -b "$b" -L 1 --json databaseId --jq '.[0].databaseId'); gh run view "$id" -R $REPO ;;
  logs)   b=$(git branch --show-current); id=$(gh run list -R $REPO -b "$b" -L 1 --json databaseId --jq '.[0].databaseId')
          if [ -n "${1:-}" ]; then j=$(gh run view "$id" -R $REPO --json jobs --jq ".jobs[]|select(.name==\"$1\")|.databaseId"); gh run view -R $REPO --job "$j" --log-failed | tail -150
          else gh run view "$id" -R $REPO --log-failed | tail -150; fi ;;
  *) sed -n 2,8p "$0"; exit 2 ;;
esac
