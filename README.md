# Paisa Pulse

A free, local-first personal finance tracker for India. Expo + TypeScript, Liquid Glass on iOS 26.
See `SPEC.md` for the product spec and `CLAUDE.md` for project context.

```bash
npm install
npm run start:go     # open in Expo Go (plain `npm start` targets a development build)
npm test             # unit + in-memory database tests
npm run typecheck
npm run lint
npm run db:generate  # after changing src/db/schema.ts
```

## Development build (encryption, voice, screenshots, widgets, Siri, iCloud backups)

Expo Go runs everything except SQLCipher encryption, live voice entry, screenshot reading, widgets,
Siri & Shortcuts, iCloud Drive backups, quick actions and alternate icons. For those, make a
development build with EAS:

```bash
npm i -g eas-cli && eas login
# once: set ios.appleTeamId in app.json (Xcode → Signing & Capabilities)
npm run build:dev:ios        # or build:dev:android
npm run start:dev            # then open the dev build on your phone
```

iOS also needs the App Group `group.com.paisapulse.app` and the iCloud container
`iCloud.com.paisapulse.app` enabled for `com.paisapulse.app` (EAS offers to sync capabilities on the
first build). The widget and Siri extensions' Swift code hasn't been compiled outside Xcode yet, so
expect small fixes on the first build.
