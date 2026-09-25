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

## Development build (encryption, widgets, quick actions, app icons)

Expo Go runs everything except SQLCipher encryption, widgets, quick actions and alternate icons.
For those, make a development build with EAS:

```bash
npm i -g eas-cli && eas login
# once: set ios.appleTeamId in app.json (Xcode → Signing & Capabilities)
npm run build:dev:ios        # or build:dev:android
npm run start:dev            # then open the dev build on your phone
```
