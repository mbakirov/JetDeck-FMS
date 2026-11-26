# CGeodesic

Geodesic routines of GeographicLib-C by Charles Karney. The files are not changed.

| File | Source | SHA-256 |
|---|---|---|
| `geodesic.c` | https://github.com/geographiclib/geographiclib-c, tag `v2.2`, `src/geodesic.c` | `87a91e0e30e7db839cbd1ef5aafea77487524958070565ff9155e50e9bead550` |
| `include/geodesic.h` | same tag, `src/geodesic.h` | `a964a747bc4f388fb3a93cc9bc379aebe4cdd78b3ee909c071be711b82db4b10` |
| `LICENSE.txt` | same tag, `LICENSE.txt` | `44e8d5e992a01915a3522d48296b8a684df5641e8162be44431c9911b9e9f32b` |

License: MIT (`LICENSE.txt`). Reference: C. F. F. Karney, "Algorithms for geodesics", J. Geodesy 87, 43–55 (2013).

Only `Kernel/Earth/Geodesy.swift` uses this target. Simulation modules call `Geodesy`, not the C functions.
The C code initialises its constants on the first call. `Geodesy` makes the first call once
(in the initialiser of a static constant), so later calls from several threads only read them.
