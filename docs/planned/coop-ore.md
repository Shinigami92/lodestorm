# Whose ore (planned)

Decided 2026-10-17. Built in parts: the ship's projects with the heat shield (M4 step 4), the players' own holds with the refinery (M4 step 11), quest deliveries with the quests (M4 step 15), the rest with co-op (M7); see [`PLAN.md`](../PLAN.md). All values **TBD (playtest)**. Today the hold is the ship's and lives in the host's save (`ship.json`); solo, the player is the host, so it doesn't show. Co-op rules so far: see [Co-op progression](../GAME_DESIGN.md#co-op-progression).

## Every player has their own hold

- **In their own save:** the hold moves from `ship.json` into each player's `player.json`, with the ores they've found (the silos' "?"). What a player mines, they spend on their own gear (upgrades, skills, the refinery, the ore exchange, building weapons), also when they play on someone else's ship; back home it's all still there. The host's save keeps what belongs to the ship: the heat shield's level, where the ship is, the story, the crew, the quests.
- **Nothing is split:** at the end of a run everyone gets the whole team's haul (all the ore brought aboard, by anyone) into their own hold, so nobody fights over a miner's hose or who carries what. What a player loses by dying is lost for everyone (it never got aboard). Co-op progresses faster than solo; aliens already scale with the player count, and the tier sync caps the gear.
- **The silos** show the hold of the player looking at them: each client sees their own player's amounts and "?" silos. With several players on one machine (local tests), the card shows the hold of the player using it.
- **Saving:** the save version goes up; an old save moves its hold and found ores from `ship.json` into `player.json` (solo, so nothing is lost).

## Ship and quest costs come out of the haul

The ship's costs would otherwise fall on the host alone, who'd fall behind their guests. Since everyone gets the whole haul, the ship takes its part **before** the haul is shared, so everyone pays the same, and nobody's hold is touched.

- **The ship's project:** at the engine room, the host picks the next heat shield plate as the ship's current project (see [`opening-planets.md`](opening-planets.md)). From then on, every run that comes back pays into it first, with exactly the ores it still needs, until it's paid; then it's installed. Example: the plate needs 300 Meridine; a run brings home 200, the plate takes all 200, and everyone's share of Meridine from that run is 0; the next run brings 150, the plate takes the last 100, and everyone gets 50.
- **Quest deliveries the same:** while a quest step asks for an amount of an ore ("bring 300 Kyrite", see [`quests.md`](quests.md)), the hauls pay into it the same way; it's handed in at the NPC once it's full. Several projects and deliveries at once fill in a fixed order (the ship's project first, then the deliveries in the order they were accepted).
- **Paying the rest from the hold:** the host at the engine room, and whoever hands in a quest step, can pay what's still missing from their own hold at any time; that's always their own choice, never someone else's ore. Solo works the same way: a project fills from what you bring home, or from your silos if you choose.
- **Alloys** never come from a haul: a step that asks for an alloy is paid from the rack of the player handing it in.
- **Shown in the world:** the plate on the drive core fills up like a silo as it's paid; when a run comes back, the cargo hatch and the silos show what the ship and the quests took ("Heat shield: 200 Meridine").
- **Rewards in ore or alloys** go to every player in the session, like a haul; the other rewards (reputation, a crew member joining, a furnace) belong to the host's ship and story, blueprints to everyone (as decided).

A guest pays into the host's ship but not into their own: when they host later, their own ship still needs its plates. That's fair: the host paid nothing for the guest's ship either.
