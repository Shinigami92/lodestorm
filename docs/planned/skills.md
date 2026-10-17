# More skills (planned)

Decided 2026-10-17, built in M4 step 14 (see [`PLAN.md`](../PLAN.md)). All values **TBD (playtest)**. Today the skill graph has four clusters with eight skills (see [Progression](../GAME_DESIGN.md#12-progression--upgrades)).

## Where the graph is heading

Six clusters of about ten skills each (about 60 over the campaign): **Mobility**, **Survival**, **Ammo**, **Scanning**, and later **Mining** (with the crafted miners, see [`refinery.md`](refinery.md)) and **Support** (with co-op, M7). Each cluster branches into 2–3 paths, so a deep skill isn't one long chain. No planet gates: the ore costs (signature ores deeper in, see [Progression](../GAME_DESIGN.md#12-progression--upgrades)) pace it by themselves, and each skill takes its time to learn (see [`refinery.md`](refinery.md)).

## The next four

These are the second or third skill of their tree, so they cost mid ores and take about 20–60 min each.

- **Rescue drone** (Survival, after regeneration): once per run, when the player would die outside, a small drone from the backpack revives them on the spot after 3 s (they lie still meanwhile, aliens ignore the body) with half their health; nothing carried is lost. One rank. It sits on the backpack while ready and shows as a tick on the suit ring's health arc (see [`player-display.md`](player-display.md)); once used, it's gone until the next run. Solo and co-op alike (reviving each other stays open for M7).
- **Hardened canister** (Survival, a second branch from reinforced suit): on death, part of the carried ore is safe: 2 ranks, 25 % and 50 % of the carried units, taken from the bottom of the stack (the rarest first). That share counts as banked: it reaches the hold when the run ends, even a lost one; the rest is lost as now. On the back, the bottom of the stack sits behind a reinforced band.
- **Rebuilding spares** (Ammo, after careful reload): during a run the suit refills one empty spare magazine of the equipped weapon from carried ore every 30 s (rank 2: 20 s), paying like a reload (commonest ore first), only while not reloading and only when there's ore. The spare ticks on the suit ring fill up as it does. Works for every ore-fed feed (magazines, shells, cells, belts; see [`weapons.md`](weapons.md)).
- **Miner radar** (Scanning, after the ore scanner, a second branch beside damage readout): the player's own miners show as small pointers on the suit ring's edge: amber when full or dry (see [`risk-reward.md`](risk-reward.md)), blinking red when attacked; working ones don't show. That's the answer to showing miners off-screen: without the skill, players keep an eye on their miners themselves.

## Later, per cluster

Not decided, a list later rounds pick from:

- **Mobility:** a second dash charge, a longer dash, moving faster with a big haul.
- **Survival:** armor plates that soak the first hit after a while, faster healing at the med bed.
- **Ammo** (becomes **Arms** with the planned weapons): the third loadout slot (deep, rare ores), faster switching (the draw time), longer timing windows.
- **Scanning:** sensing the nearest nest through rock within 30 m, the late deposit's beam lasting longer.
- **Mining** (with the crafted miners): faster placing and picking up, a longer hose, repairing from farther away, furnaces running faster.
- **Support** (with co-op): sentries, giving ammo faster, faster revives, getting up with more health, a longer bleed-out (reviving itself is for everyone, see [`coop-revive.md`](coop-revive.md)).
