# LPE

The Live Persona Engine app for The Omniverse — create your Halo; your identity home.

Your LPE profile already lives on your Omni Node (daemon 8.25+) and the rest of
the ecosystem already reads it: Plaza-Brawler builds your fighter from it
(`GET /api/lpe/profile`), KickBack shows it as your persona. Until now a profile
could only appear through raw API calls. This app is the missing creator surface —
and, over time, the identity home whose personal space is injected into the
Omni-Hub. The zodiac fighters in Plaza-Brawler are the NPC cast; your Halo is you.

**Status: skeleton (v0.1.0), Nov 8, 2026.** Three tabs:

- **Home** — your identity (this install's Ed25519 StargateIdentity) and your
  stored profile: handle, aura tier, XP, Plaza credits.
- **Creator** — handle, sign, ambient activity, live preview; saving signs a
  `lpe_profile` event and posts it to your node (`POST /api/lpe/profile`),
  then reads it back to confirm.
- **Node** — node host/token (Omni Node > Connect apps) and a health check on
  the standard ports (5000 API, 9100 telemetry).

Honest skeleton limits:

- One avatar (`default_m_01`) and no cosmetics yet — the daemon API already
  carries cosmetics/sockets; the pickers come later.
- The daemon's profile payload schema is strict and has **no sign field yet**,
  so the chosen sign is kept on the phone (the same fallback Plaza-Brawler
  uses today). Carrying the sign inside the profile needs a small daemon
  schema extension; tracked as the first follow-up.
- CI here makes test builds (debug key), like the sibling apps; signed
  releases come from the monorepo pipeline until release orchestration moves.

## Build

```
flutter pub get
flutter build apk --release --target-platform android-arm64
```

Shared code comes from [Omni-Core-UI](https://github.com/kiroba/Omni-Core-UI),
pinned by tag in `pubspec.yaml`. Android package: `com.omniverse.lpe`.
Scaffolded from the OmniCast sibling pattern (same generator family).
