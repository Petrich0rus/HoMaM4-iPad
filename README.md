# HoMaM4-iPad

Reimplementation of the engine of *Heroes of Might and Magic IV* for iPadOS (Swift), in the spirit of VCMI.
**No game files are included**: the app reads the player's own copy (GOG version).
The file formats are reconstructed by reverse engineering the original executable (Ghidra, through REA).

- [`H4Kit/`](H4Kit/README.md): Swift library + `h4tool` command-line tool — archives, images, terrain,
  fonts, maps (header, scripts, objects, terrain). Research notes in `H4Kit/Research/`.
- `H4App/`: iPad application (in progress).
