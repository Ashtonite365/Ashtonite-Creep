# Changelog

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
