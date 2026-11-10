# Simply Light — Horizon port

A port of [Simply Light](https://github.com/Flanks255/simplylight) by Flanks255
for Horizon: ten families of decorative light blocks — lamps, slabs, panels,
wall lamps, bulbs, rods, posts and edge lights — in all sixteen colours, 160
blocks and 2048 block states.

- Lamps emit light 15; bulbs and edge lights emit 14; an unlit lamp emits none.
- Every block drops itself and is craftable from its family's recipe.
- Builders get the same shapes as upstream: panels and slabs that sit flush,
  wall-mounted lamps, and edge lights for ceilings and floors.

Original copyright and licence notices are kept in the port repository. Pinned
to Horizon 1d63e0a and horizon-mixins 5a64af93. Redstone toggling, the lamp-post
column and the edge-light editor are later slices.

**Original:** [Simply Light](https://github.com/Flanks255/simplylight) 1.5.3+1.21.1-b4 by
Flanks255, **MIT**. The original
copyright and licence notices are kept in [LICENSE](LICENSE), and
[LICENSE-NOTICE.md](LICENSE-NOTICE.md) records where each was read from.

**Horizon:** a port for [Horizon](https://github.com/horizon-rust/horizon), Minecraft:
Java Edition 26.3 rewritten in Rust. The exact Horizon and horizon-mixins
revisions this port builds against are pinned in `compatibility.json`.

## Install

1. Take `simplylight.hmod` from this repository (or build it below).
2. Put it in the game folder's `horizon-mods` folder — the game folder is the one
   holding `options.txt`.
3. Mods are off by default: enable this one in the game's mod list.

To try it without installing, start the game with
`--dev-mod simplylight.hmod`.

## Build

This is a content-only mod: `content/horizon-mod.toml` plus `assets/` and
`data/`.

```sh
cd content && cargo horizon-mod build    # packs content/ into the .hmod and checks it
```

`cargo-horizon-mod` comes from the Horizon repository
(`cargo install --git https://github.com/horizon-rust/horizon cargo-horizon-mod`).
`tools/e2e.sh` is the in-game harness and expects a campaign checkout
(`$CAMPAIGN_ROOT`) with the prepared 26.3 resources (`$HORIZON_RES`, default
`.local/horizon-client/26.3`).

## Layout

`content/` is the 160-block data tier plus the carried assets; `tools/gen_content.py` regenerates the declarations.

This is an unofficial port: Horizon is not affiliated with the original author.
The licence above is the original's and travels with every copy; see
[LICENSE](LICENSE) and [LICENSE-NOTICE.md](LICENSE-NOTICE.md).
