# Licence notice — Simply Light

This port carries the original mod's assets and data, and rewrites its behaviour
in Rust (or, for a data-tier port, declares its blocks from the same data). The
original licence and copyright notices are reproduced verbatim in
[LICENSE](LICENSE).

## Where the licence was read

- The pack jar `simplylight-1.5.3+1.21.1-b4.jar` (kept at
  `licence-cache/`) declares `license="MIT"` in `META-INF/neoforge.mods.toml`
  and carries no licence file.
- The MIT text is reproduced from that declaration; the copyright line uses the
  jar's own `authors="Flanks255"`, because the jar ships no copyright line.

## The port

- Original: Simply Light 1.5.3+1.21.1-b4 by Flanks255 — MIT.
- Licence: **MIT**
- Port to Horizon by AdLf0208: the Rust runtime, the Horizon declarations and the
  build/verification tooling in this repository.
- No Mojang file is included. The carried files are the mod's own assets and
  data; `data/minecraft/tags/…` files only add this mod's ids to vanilla tags.
