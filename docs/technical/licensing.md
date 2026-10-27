# Source-available and licensing

- Code **and** assets (incl. `.blend` source files) are public on GitHub.
- License: **[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/)** for everything original to this project (full text in `LICENSE`).
  - Others may fork, modify and share, with attribution, non-commercially, under the same license.
  - Only the owner sells the game (Steam/Epic/GOG). Strictly speaking this is *source-available*, not OSI "open source".
  - Third-party code and assets keep their own licenses, shipped next to them (e.g. `addons/godot_ai/` and `addons/gut/` are MIT, see their license files; GUT's bundled fonts are OFL). Only add third-party material whose license allows redistribution in this repo and in the commercial release.
- **CLA required for contributions**, so the owner may use contributions in the commercial release: the text is [`CLA.md`](../../CLA.md) (a license grant, the contributor keeps the copyright). Contributors sign it on their first pull request through [CLA Bot](https://cla.fiveonefour.com/) (a hosted GitHub App by fiveonefour, [source](https://github.com/514-labs/cla-bot)) with their GitHub account; it reports the `CLA Bot / Contributor License Agreement` check, required on `main`, and updates open pull requests by itself once their author signs (`/recheck` in a comment checks again). It checks the pull request's author, not every commit's. Its dashboard (`https://cla.fiveonefour.com/admin/Shinigami92`) holds the same text as `CLA.md`; a change to `CLA.md` is pasted there too, which makes it a new version (tracked by a hash of the text) that contributors sign again. The owner's own pull requests pass without signing; bots that can't sign are on its bypass list (`renovate`).
- Game name/logo: consider protecting as trademark before release.
- Get a short legal review before the commercial release.
- Secrets (Steam credentials, store tokens) only live in GitHub Actions secrets, never in the repo.
