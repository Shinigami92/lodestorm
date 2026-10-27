# Title view and pause panel (planned)

Decided 2026-10-17; the title view, the pause panel, the settings in one place, quitting and the credits are built (M4 step 5 A, see [UI](../design/ui.md)). What's left comes with co-op (M7), VR (M6) and the platform services (M8). All values **TBD (playtest)**.

- **Co-op (M7):** guests get "Leave session" (back to their own ship) on the pause panel, the host "End session"; joining a friend also works from the title view (accepting an invite through the platform's overlay).
- **The Steam overlay (M8):** solo, opening the platform's overlay pauses the game like the window losing focus.
- **More settings, as their features come:** later display and graphics (the suit ring's size and "Always show" and the sound volumes are built); they go into the one settings component, so the pause panel and the terminal both get them. The CC-BY sound sources join the credits, generated from the sound manifest.
- **VR (M6):** the pause panel floats in front of the player at a comfortable distance (see [`vr-view.md`](vr-view.md)); the title view is the same scene.
