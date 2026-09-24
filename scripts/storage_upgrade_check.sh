#!/usr/bin/env bash
set -euo pipefail

package=com.tarkilhk.wing.dev
activity=com.tarkilhk.wing.MainActivity

check_screen() {
  local expected="$1"
  for attempt in $(seq 1 30); do
    adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1 || true
    if adb shell cat /sdcard/window.xml 2>/dev/null | grep -q "$expected"; then
      return 0
    fi
    sleep 2
  done
  adb logcat -d -s flutter:I | tail -100
  echo "Expected app status $expected was not shown" >&2
  return 1
}

adb install -r previous/build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -W -n "$package/$activity"
check_screen UPGRADE_CHECK_SEEDED
adb shell am force-stop "$package"
adb install -r current/build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -W -n "$package/$activity"
check_screen UPGRADE_CHECK_PASSED
