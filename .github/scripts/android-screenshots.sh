#!/usr/bin/env bash
# Installs the release APK on the emulator, opens each screen with sample data (light + dark) and
# publishes the PNGs to the ci-screenshots-android branch (read them through the GitHub API).
set -euo pipefail
adb install -r PaisaPulse.apk
mkdir -p shots
shot() { # name, extras...
  local name=$1; shift
  adb shell am force-stop com.paisapulse.app
  adb shell am start -n com.paisapulse.app/.MainActivity --ez PaisaDemo true "$@" >/dev/null
  sleep 8
  adb exec-out screencap -p > "shots/$name.png"
}
for mode in light dark; do
  if [ $mode = dark ]; then adb shell cmd uimode night yes; else adb shell cmd uimode night no; fi
  for tab in home activity accounts settings; do shot "$tab-$mode" --es PaisaTab $tab; done
  shot "add-$mode" --ez PaisaAdd true
done
ls -la shots
cd shots
git init -q -b ci-screenshots-android
git -c user.name=ci -c user.email=ci@users.noreply.github.com add .
git -c user.name=ci -c user.email=ci@users.noreply.github.com commit -qm "Android screenshots for ${GITHUB_SHA} (build ${GITHUB_RUN_NUMBER})"
git push -fq "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" ci-screenshots-android
