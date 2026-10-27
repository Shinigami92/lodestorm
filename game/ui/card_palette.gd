class_name CardPalette
extends RefCounted
## The colors of the holo cards' text, in one place (see docs/design/ui.md). The cards' look is
## the terminal theme's card variations (`assets/ui/terminal_theme.tres`): `Card` (the panel),
## `CardTitle`, `CardText`, `CardNote` and `CardStatus`; the colors here are the same as theirs
## (`tests/ui/test_card_palette.gd` keeps them so), for text that changes its color in code.

## Titles (`CardTitle`).
const TITLE := Color(0.3, 0.85, 1.0)
## Where things stand, what's new or selected (`CardStatus`; amber like the highlight).
const STATUS := Color(1.0, 0.75, 0.3)
## Something missing or about to be lost (ore a cost lacks, sleeping during a run).
const WARNING := Color(1.0, 0.4, 0.35)
## Done and fine (healed).
const GOOD := Color(0.3, 1.0, 0.45)
## Side notes and row names (`CardNote`).
const NOTE := Color(1.0, 1.0, 1.0, 0.75)
## Hints and roles, fainter than notes.
const HINT := Color(1.0, 1.0, 1.0, 0.6)
## What can't be had yet (a weapon not owned, a later plate): the whole row dimmed (`modulate`).
const DIMMED := Color(1.0, 1.0, 1.0, 0.45)
