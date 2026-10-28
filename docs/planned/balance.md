# Pacing miners and furnaces, the rescue drone, co-op miners (planned)

Decided 2026-10-28. The cradles, the early costs, the rescue drone and choosing which miner to place are built before the quests (see [`PLAN.md`](../PLAN.md)); the main quest's rewards with the quests (M4 step 16), the team's miners with co-op (M7). All values **TBD (playtest)**.

## Miners: two at the start, six through the main quest

Today every player takes six miners into every run from the first one on (see [Miners](../design/mining.md)).

- **Two at the start:** M-01 and one standard-issue miner. One alone makes a run mostly waiting; two already means choosing which ore.
- **One more per act in acts 1–4,** a main-quest reward in the middle of the act, not at its end (so it doesn't fall on the same moment as the heat shield plate): 3 in act 1, 4 in act 2, 5 in act 3, 6 in act 4. Who hands it over is written in each act's writing round (see [`story.md`](story.md)).
- **Open cradles set the count:** a crafted miner can only be built in an open cradle, standard-issue miners fill up only to the number of open cradles, and placing stops at that number (as it stops at six today). Until the quests, the debug overlay opens cradles (like the furnaces).
- **The ship's count:** the cradles are the ship's, so the host's save. In co-op everyone uses the host's count (like the furnaces and tier sync); a guest with more crafted miners takes the first ones by number, the rest stay home in the guest's save, never lost.

## Choosing which miner to place

With two to six miners and crafted ones that differ in drill, tank and plating, which miner goes where is a decision. Today placing takes the miner that mines the node's ore fastest (see [Miners](../design/mining.md)), so the best drill lands on the first common node and is already placed when the signature ore turns up.

- **A smarter default:** placing takes the miner with the softest drill that still mines the node's ore at full speed (a standard-issue one before a crafted one with the same result, crafted ones by number on a tie); without one at full speed, the fastest as today. The best drill stays free for the hard ore without the player doing anything.
- **A preview before placing:** while a player is in range of a free node and has a miner left to place, a faint hologram of the miner `place_miner` would place stands on the nearest free node, in place of today's ring marking it. Only one, on that node; it fades out when the player walks off or has none left. It's set apart from the building hologram: lower opacity, slowly breathing, no rising scan lines; `place_miner` turns it into the building hologram and the placing time starts. It also shows that a miner can go here right now. In co-op each player sees only their own.
- **Recognizable:** the preview wears the miner's number plate (a plain grey one for standard-issue) and its owner's color strip, a short label on its side box ("Drill MK5 · Tank MK3", world text), its color saying how it fits the ore (cyan at full speed, amber when the drill is too soft), and a tick on its ring for the time it would take to fill on this node. In the art pass, drill heads and tanks look different per MK level.
- **Switching:** two new actions, `miner_prev` and `miner_next` (D-pad left/right on the gamepad, two free keys on the keyboard, picked when building; `tab_prev`/`tab_next` share Q/R and the bumpers with `switch_weapon` and `reload` during a run), step the preview through the miners still to place. The choice sticks until it's placed; the next preview starts on the default again. In VR the binding comes with M6's controller mapping.

## Why cradles and furnaces are missing

The ship is the survey's old ship, stripped and sold off when the survey ended and bought cheap by Brannik (see [`characters.md`](characters.md)). Cradles and furnaces went with everything else that came loose.

- **A missing cradle** is an empty spot in the bay's row: bare floor rails, cut cables capped and taped, a faded outline on the wall where it hung, its number plate still there. Its card says so in a plain line.
- **A missing furnace** stands cold and open with its burner pulled out (today a cold, dark shell; the first one is rebuilt in Okoro's quest).
- **The main quest pays in parts** (the colony pays in ore, alloys and favors, see [`world.md`](world.md)); each part is installed when it's handed over, and the cradle or furnace lights up.
- **Said in a line:** Brannik's tour stop in the miners' bay ("They sold the cradles with everything else that came loose. We got two back."), Hollis' fleet topic and Okoro's furnace topic (and the stand-in topics until Hollis joins); new and changed lines voiced in English and German (Fenna English).

## Furnaces through the main quest

- **All four through the main quest, one per act in acts 1–4:** the first early in act 1 (Okoro's furnace quest becomes a main step, since crafted miners need Cobrel), then one each in acts 2, 3 and 4. Each of acts 1–4 brings a cradle and a furnace.
- **No more furnaces as skills:** only the main quest adds furnaces; "furnaces running faster" stays a mining skill (see [`skills.md`](skills.md)).

## The early costs

With two or three miners, act 1's runs bring roughly a third to half of today's haul. The first heat shield plate and the MK2 and MK3 costs drop to about half as greybox, then get tuned in playtest; the later acts stay as they are (by act 4 the player has six miners again).

## The rescue drone waits, then flashes

Today the drone gets the player up after 3 s, right where the aliens that killed them still stand, so they die again at once (see [Progression](../design/progression.md)).

- **It waits for a gap:** the drone keeps the player down until no alien is within 10 m, at most 8 s. The aliens leave a downed player alone already; while the player is down they turn away and walk back towards their nest, as when a player outruns them. The wait costs time on the storm clock: the drone's small price.
- **It burns out with a flash:** when the player gets up, the drone flares bright and is gone; aliens within 8 m are staggered for 2 s and pushed back a little. The flash is also why they scatter (a warden by its nest never walks off by itself).
- **The same in co-op** when the drone gets a downed player up (see [`coop-revive.md`](coop-revive.md)).

## Co-op: the team's miners

Everyone still gets the whole haul (see [Co-op progression](../design/progression.md#co-op-progression)), so six miners per player would give each of four players about four times a solo run's ore, and with that many miners picking one up and moving it mid-run would never be worth it.

- **The team's budget:** the open cradles plus one per extra player, never fewer than one per player. With six cradles 7 / 8 / 9 miners for 2 / 3 / 4 players, so each player earns about 1.17× / 1.33× / 1.5× a solo run; with two cradles 3 / 4 / 5.
- **A shared pool:** anyone places while the team has miners left, each from their own (crafted first, then standard-issue), so the team decides who mines and who fights; nobody places more than the open cradles. The count of miners left to place shows the team's count.
- **The map stays as it is:** the team places only a few miners more than a solo player, so no extra ore fields or bigger maps per player.
