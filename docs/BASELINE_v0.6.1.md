# Trace Race HD v0.6.1 — Gameplay Feel Fixed

## Status
PLAYTEST CONFIRMED WORKING — 2026-08-17

v0.6.1 is confirmed working by playtest.

## Confirmed presentation changes
- existing 3-2-1 / GO countdown retained
- subtle speed streaks while racing
- finish flash
- finish/results panel
- clearer retry messaging

## Gameplay status
The confirmed v0.5 drawing, path-following, driving, ghost, timer and save systems remain working. No physics or route-following logic was changed in this pass.

## Development note
The failed v0.6 build was discarded because it referenced variables that do not exist in the current engine. v0.6.1 was rebuilt directly from v0.5 using only existing engine state.

## Next target
v0.7 — add the first production game flow around the stable race engine: main menu -> track select -> race -> results, while keeping the race scene itself unchanged.
