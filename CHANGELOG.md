# Changelog

## 1.2.0

Changed:
- Two-step hop checks its path first. It samples rays down along the sideways leg and backwards along the up/down leg,
  then offsets the hop by the nearest surface found plus the hitbox, so the move stays tucked behind geometry
- Code comments for the Driftball exclusions, back probe and through-cage rays

Licence:
- Now licensed under GPL-3.0-only, with NOTICE additional terms (keep the author attribution, mark modified versions)
- Added LICENSE, NOTICE, a licence/copyright header in the script, and the `package.json` licence field
- Added the Another Axiom non-affiliation disclaimer and an AI-assistance credit
- 1.1.0 moved to `archive/1.1.0/`

## 1.1.0

Added:
- 32 gravity-aligned search rays (22 down / level, 10 up)
- Cage traces go through the future camera point and stop the same distance out
- No 3rd person toggle (can lag on low end devices)
- Header line for current wall vs floor priority

Fixed:
- Search not running (search direction helper used flatten too early)

## 1.0.0

First public build.

Added:
- Player search and Begin / Stop creep
- Perch hide behind one-sided geo (back probe + 14-ray cage + room-behind check)
- Face-side cage retry so ramps can slide deeper
- Driftball see-through exclusions (Plaza, Stadium Prime, Bunker, Fieldhouse) with master toggle
- Two-step hop so vertical travel does not pop into view
- 3rd person fallback with orbit / follow distance
- Freecam with mouse invert, move speed, and Q/E speed
- LOS check: any hit between camera and player invalidates the perch
