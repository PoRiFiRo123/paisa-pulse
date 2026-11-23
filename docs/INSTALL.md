# Installing Paisa Pulse

Downloads: [latest release](https://github.com/PoRiFiRo123/paisa-pulse/releases/latest).

## Android
1. On the phone, open the latest release and tap **PaisaPulse.apk**.
2. Allow your browser to install apps when Android asks (one time).
3. Updates: Paisa Pulse shows **Software Update** in Settings; tap it, open the downloaded APK, and it
   installs over the old one. Your data stays.

## iPhone (free Apple ID)
A free Apple ID allows 3 sideloaded apps at a time, and each install lasts 7 days. Paisa Pulse uses all 3:
the app, its widget and the share extension (share payment screenshots from UPI apps).

**Over USB with [iloader](https://github.com/nab138/iloader)** (Windows, Mac or Linux):
1. Download **PaisaPulse.ipa** from the latest release onto the computer.
2. Connect the iPhone, open iloader, sign in with your Apple ID and choose **Import IPA** → the file.
3. Settings › General › VPN & Device Management: trust your Apple ID if iOS asks. Turn on Developer Mode if asked.
4. Every week, install the same (or newer) .ipa again before the 7 days run out. Your data stays.
   If it expires, it just won't open until you reinstall; nothing is lost.

[Sideloadly](https://sideloadly.io) works the same way. SideStore can refresh on the phone, but it needs one of the
3 slots for itself, so you'd have to give up the share extension.

To use the share extension: in GPay, PhonePe, Paytm or Photos tap Share › Paisa Pulse (if it's missing, tap
More at the end of the app row and turn it on).

### Not in the free iPhone build
- **iCloud backups** (Apple only gives iCloud to paid accounts). Backups are saved daily in Files › On My
  iPhone › Paisa Pulse › backups; copy one off the phone now and then, or turn on backup encryption.
- **Voice entry** is Android only.

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
