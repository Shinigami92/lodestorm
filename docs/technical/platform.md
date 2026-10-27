# Platform services and distribution


## Abstraction

A `PlatformService` layer (autoload) with backends:

- `NullPlatform`: GitHub/itch builds, development, CI (no-op)
- `SteamPlatform`: via [GodotSteam](https://godotsteam.com/) (GDExtension)
- `EpicPlatform` / `GogPlatform`: later, via EOS / GOG Galaxy plugins (to be evaluated)

Gameplay only calls e.g. `PlatformService.unlock_achievement(&"first_miner")`; the game must run fully without any store client.

## Achievements

- Defined once in the game (id, name, description, icon), mirrored in each store's backend config.
- Optional in-game achievement list so non-Steam builds have them too.
- During development Steam's test App ID `480` (Spacewar) is used until the real App ID exists.

## Steam publishing: first-timer checklist

1. Create a Steamworks partner account (identity, tax and bank info).
2. Pay the Steam Direct fee per game (currently USD 100, recoupable after USD 1,000 gross revenue). After payment there is a mandatory waiting period (~30 days) before release.
3. Get the App ID; set up depots (Windows/Linux/macOS), and the SteamPipe upload via SteamCMD.
4. Configure achievements + icons in Steamworks.
5. Build the store page (capsule images, screenshots, trailer, description) → Valve review.
6. "Coming Soon" page must be public for at least ~2 weeks before release (wishlists matter a lot).
7. Upload a build → Valve build review → release (Early Access is an option for an iterating game).
8. Fill in the AI content disclosure (pre-generated content): the generated models (each `source/trellis/trellis.json`), the emblem (`assets/ui/boot/source/emblem.json`) and sounds (`made_by` in `assets/audio/source/manifest.json`).

These rules may change; re-verify on the Steamworks documentation when we get there.

## Other stores

Epic Games Store and GOG have their own submission processes and SDKs, to be evaluated once the game approaches release.
