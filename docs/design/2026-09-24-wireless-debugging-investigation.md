# Wireless debugging turns itself off — 24 September 2026

## Finding

The unexplained loss of port 36901 at **18:56:19 Singapore time** was caused by
Android deliberately disabling wireless debugging when the phone changed Wi-Fi
BSSID. The Wi-Fi name stayed the same, but the phone moved from its 2.4 GHz radio
to its 5 GHz radio. This is separate from Wing's notification recovery bug.

This conclusion is proven by retained phone logs and Wi-Fi state history. No
network, debugging, security, or power settings were changed during this
investigation. No additional disruptive reproduction was needed.

## Direct evidence

Device: Samsung Galaxy S23 Ultra, Android 16. Times below are phone local time,
24 September 2026, UTC+08:00. SSID, addresses, keys and unrelated phone data are
intentionally omitted.

| Time | Recorded event |
| --- | --- |
| 18:54:28.095 | Wi-Fi completed association with BSSID B on the existing saved network. Other Wi-Fi records identify B as 2412 MHz, the 2.4 GHz band. |
| 18:54:30.380 | Android obtained wireless-debugging port 36901. |
| 18:56:19.450–.459 | Wi-Fi associated with BSSID A and completed on the **same SSID and network ID**. Other Wi-Fi records identify A as 5745 MHz, the 5 GHz band. |
| 18:56:19.454 | `AdbBroadcastReceiver: Detected wifi network change. Disabling adbwifi.` |
| 18:56:19.455 | `SettingsProvider: PUT_ret(/global/adb_wifi_enabled), callingPackage:android` |
| 18:56:19.522 | `AdbService: setAdbEnabled(false), mIsAdbUsbEnabled=false, mIsAdbWifiEnabled=true, transportType=1` |
| 18:56:19.522 | `AdbService: Disabling ADBd Wifi property` |
| 19:25:01.044 | After wireless debugging was enabled again, adbd started its TLS listener on new port 36259. |

Wi-Fi history also shows the opposite band transition at 18:54:28 and several
earlier same-network BSSID changes. The captured shutdown above establishes the
cause of the recent unexplained loss; it does not prove that every historical
disconnect had the same cause. Some earlier losses followed intentional offline
testing.

The workstation ADB server had remained running since 10:54:42, more than eight
hours before capture. Phone `adb_allowed_connection_time` was already `0`, so
changing authorization timeout is not a remedy for this event. The observed
shutdown happened with the screen on; a screen-sleep theory does not explain it.

## Why the Wi-Fi name staying unchanged does not help

The stock Android framework compares the current access-point **BSSID** with the
one recorded when wireless debugging was enabled. A mismatch emits the exact
log above and writes `ADB_WIFI_ENABLED = 0`, even if the SSID is unchanged.
See [AOSP AdbDebuggingManager, Android 15 release branch](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android15-release/services/core/java/com/android/server/adb/AdbDebuggingManager.java).
This source is a reference for the matching framework behavior; the direct logs
establish that this Samsung Android 16 device follows that shutdown path.

The logs establish the band/BSSID change, but do **not** establish whether the
router's band steering, the phone's radio selection, or movement caused that
change. Do not label a particular router feature defective without its logs.

## Practical remedy

For stable wireless testing, keep the phone on **one AP/radio**. A dedicated
single-band test SSID, or a router-supported per-client AP/band lock, would avoid
the particular BSSID changes observed here. This is a proposed mitigation, not
an applied or verified fix. A single-band SSID spanning multiple access points
could still roam between BSSIDs; use one AP as well where possible. Separating
bands or disabling roaming for a client trades away seamless Wi-Fi roaming and
may reduce coverage or throughput away from that AP.

USB debugging to an accessible workstation is an alternative that avoids the
wireless-debugging dependency, but is not currently the remote connection used
for this phone. No router changes, new debugging mode, or security-policy changes
were made. Battery exemptions and Wing changes do not address this framework
BSSID check. Repeatedly reconnecting to the old port cannot help once the phone
has disabled its listener.

The [official ADB guide](https://developer.android.com/tools/adb) now distinguishes
Android 17's newer Wi-Fi debugging from older devices; do not assume those new
automatic-reconnection guarantees apply to this Android 16 phone. It also
documents the optional Wireless debugging Quick Settings tile, which can reduce
manual navigation when re-enabling it but does not prevent this shutdown.

## Reproducible evidence check

Private captures and a sanitized-output replay assertion are under
`/tmp/wing-wireless-debugging-investigation/`; raw captures are not committed.
The replay checks the exact shutdown, same SSID/network ID, different BSSIDs,
and the recorded frequency mappings:

```text
python3 /tmp/wing-wireless-debugging-investigation/check_disconnect.py
FAIL: Wireless debugging disabled at 18:56:19 immediately after same-SSID BSSID change from 2.4 GHz to 5 GHz.
PROVEN: Android framework wrote adb_wifi_enabled=0; this was not merely lost host connectivity.
```

Exit status 1 intentionally denotes the captured failure. This checks retained
evidence; it neither causes a live roam nor claims the mitigation has passed a
live retest.
