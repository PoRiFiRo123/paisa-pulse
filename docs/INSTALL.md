# Installing Paisa Pulse

Downloads: [latest release](https://github.com/PoRiFiRo123/paisa-pulse/releases/latest).

## Android
1. On the phone, open the latest release and tap **PaisaPulse.apk**.
2. Allow your browser to install apps when Android asks (one time).
3. Updates: Paisa Pulse shows **Software Update** in Settings; tap it, open the downloaded APK, and it
   installs over the old one. Your data stays.

## iPhone (free Apple ID)
A free Apple ID allows 3 sideloaded apps at a time, and each install lasts 7 days until it is refreshed.
Paisa Pulse uses 2 of the 3 (the app and its widget). The iPhone app is native Swift; the Android app is the Expo one, and backups move between them.

**One-time setup, needs a computer once:** install [SideStore](https://sidestore.io) by following its
guide (it creates a pairing file with your Apple ID). After that, everything happens on the phone.

1. On the iPhone, open the latest release, long-press **PaisaPulse.ipa** and share it to SideStore
   (or download it, then SideStore › My Apps › + and pick the file).
2. Sign in with your Apple ID when SideStore asks. It signs and installs the app.
3. Settings › General › VPN & Device Management: trust your Apple ID if iOS asks.
4. Open SideStore every few days and tap **Refresh All** (or turn on background refresh) so the app
   doesn't expire after 7 days. If it does expire, refreshing brings it back with your data.
5. Updates: Settings › Software Update in Paisa Pulse opens the new build in SideStore.

Without SideStore: [Sideloadly](https://sideloadly.io) on Windows/Mac installs the same .ipa over USB
(refresh weekly the same way).

### Not in the free iPhone build
- **iCloud backups** (Apple only gives iCloud to paid accounts). Backups are saved daily in Files › On My
  iPhone › Paisa Pulse › backups; Settings › Backup & Restore › Save to Google Drive keeps a copy off the phone.
- **Statement import, voice and screenshot capture** aren't ported to the Swift app yet.

## Keeping Android updates installable
Every APK is signed with the same key so updates install over each other. Set it permanently once:
GitHub › paisa-pulse › Settings › Secrets and variables › Actions › New repository secret
`PAISA_ANDROID_KEYSTORE_B64` = a base64 keystore (alias `androiddebugkey`, password `android`):

```bash
keytool -genkeypair -keystore paisa.keystore -storepass android -keypass android \
  -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Paisa Pulse,C=IN"
base64 -w0 paisa.keystore   # paste the output as the secret; keep paisa.keystore somewhere safe
```

Until then, builds use a key cached by GitHub Actions, which works as long as a build runs at least
once a week.
