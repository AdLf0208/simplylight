#!/usr/bin/env python3
"""Generate Simply Light's Horizon content from the upstream 1.21.1 jar.

Ported from Simply Light 1.5.3 (`Flanks255/simplylight`, MIT) for Minecraft
Java 26.3 on Horizon ``1d63e0a5``. The jar is the content source: its
blockstates, models, textures, lang and item tags are carried, its loot tables
and recipes are the 26.3 shapes `horizon-port-pack check` wrote, and the 160
block declarations are generated here (the carry tool leaves out the 48 blocks
whose states no vanilla template has: the 32 ``illuminant_block*`` with the
``on`` property and the 16 ``lamp_post`` with ``position``).

Deterministic: the same jar and carry tree always give the same bytes.
Run ``horizon-port-pack check <jar> content`` once before this script; it
writes ``content/carry`` (loot tables, recipes, item definitions).

Usage: python3 tools/gen_content.py
"""
from __future__ import annotations

import json
import shutil
import sys
import zipfile
from pathlib import Path

PORT = Path(__file__).resolve().parents[1]
CAMPAIGN = PORT.parents[1]
JAR = CAMPAIGN / "ports/_shared/carry-work/simplylight/simplylight-1.5.3+1.21.1-b4.jar"
CARRY = PORT / "content/carry"
OUT = PORT / "content"

# Upstream DyeColor order in the registration sets (SLBlocks.LAMPBLOCKS_ON,
# SLABS, PANELS, RODS, BULBS, FIXTURES, POSTS, EDGE_LIGHTS, EDGE_LIGHTS_TOP),
# which is also the creative-tab order.
COLOURS = [
    "light_gray", "gray", "black", "brown", "red", "orange", "yellow",
    "lime", "green", "cyan", "light_blue", "blue", "purple", "magenta", "pink",
]

# 26.3 MapColor ids (crates/horizon-items/src/blocks.rs::MAP_COLORS).
BLACK = 29
LIGHT_GRAY = 22
TERRACOTTA_WHITE = 36
NONE = 0


def px(*values: float) -> list[float]:
    """A box in pixels (0..16) as block space (0..1)."""
    return [v / 16 for v in values]


# ---------------------------------------------------------------- shapes
# Upstream `getShape` boxes (block space). ThinLamp/Fixture/RotatableLamp
# select by `facing`, RodLamp by `axis`, LampPost by `position`, EdgeLight by
# its four side booleans (and falls back to all four when none is set).
FACING = ["down", "up", "north", "south", "west", "east"]  # get3DDataValue order


def thin_lamp(t: float) -> dict:
    """ThinLamp: a t-thick plate on the clicked face (panel 4/16, slab 8/16)."""
    return {
        "up": [px(0, 0, 0, 16, 16 * t, 16)],
        "down": [px(0, 16 - 16 * t, 0, 16, 16, 16)],
        "east": [px(0, 0, 0, 16 * t, 16, 16)],
        "west": [px(16 - 16 * t, 0, 0, 16, 16, 16)],
        "north": [px(0, 0, 16 - 16 * t, 16, 16, 16)],
        "south": [px(0, 0, 0, 16, 16, 16 * t)],
    }


LIGHTBULB = {
    "up": [px(6, 0, 6, 10, 5, 10)],
    "down": [px(6, 11, 6, 10, 16, 10)],
    "east": [px(0, 6, 6, 5, 10, 10)],
    "west": [px(11, 6, 6, 16, 10, 10)],
    "north": [px(6, 6, 11, 10, 10, 16)],
    "south": [px(6, 6, 0, 10, 10, 5)],
}

WALL_LAMP = {
    "up": [px(6, 0, 6, 10, 2, 10)],
    "down": [px(6, 14, 6, 10, 16, 10)],
    "east": [px(0, 6, 4, 3, 10, 12)],
    "west": [px(13, 6, 4, 16, 10, 12)],
    "north": [px(4, 6, 13, 12, 10, 16)],
    "south": [px(4, 6, 0, 12, 10, 3)],
}

ROD = {
    "x": [px(0, 7, 7, 16, 9, 9)],
    "y": [px(7, 0, 7, 9, 16, 9)],
    "z": [px(7, 7, 0, 9, 9, 16)],
}

LAMP_POST = {
    "bottom": [
        px(3, 0, 3, 13, 2, 13),
        px(4, 2, 4, 12, 4, 12),
        px(6, 4, 6, 10, 16, 10),
    ],
    "middle": [px(6, 0, 6, 10, 10, 10), px(5, 10, 5, 11, 16, 11)],
    "top": [
        px(6, 0, 6, 10, 5, 10),
        px(5, 5, 5, 11, 6, 11),
        px(3, 6, 3, 13, 16, 13),
    ],
}


def edge_light(top: bool) -> dict:
    """EdgeLight: one 1/16 strip per supported horizontal side, or all four."""
    y0, y1 = (15, 16) if top else (0, 1)
    west = px(0, y0, 0, 1, y1, 16)
    east = px(15, y0, 0, 16, y1, 16)
    north = px(0, y0, 0, 16, y1, 1)
    south = px(0, y0, 15, 16, y1, 16)
    # BlockShapes keys are the property values in the declaration's property
    # order (north, south, east, west); the all-false state draws every strip.
    names = ["north", "south", "east", "west"]
    sides = {"north": north, "south": south, "east": east, "west": west}
    values = {}
    for combo in range(16):
        key = ",".join("true" if combo & (1 << i) else "false" for i in range(4))
        boxes = [sides[name] for i, name in enumerate(names) if combo & (1 << i)]
        values[key] = boxes or [west, east, north, south]
    return {"properties": names, "values": values}


def shapes_of(prop: str, table: dict) -> dict:
    return {"property": prop, "values": table}


# ---------------------------------------------------------- declarations
def declaration(family: str, block_id: str) -> dict:
    """One `data/simplylight/horizon/block/<id>.json`."""
    base = {
        "template": "minecraft:calcite",
        "properties": {
            # Block.Properties.of().strength(1.0f): destroy time and blast
            # resistance together, default STONE sound, no correct-tool need.
            "hardness": 1.0,
            "explosion_resistance": 1.0,
            "requires_tool": False,
            "sounds": "minecraft:stone",
        },
    }
    props = base["properties"]

    if family == "illuminant_block":
        props["light"] = 0
        props["map_color"] = BLACK
        return base | {
            "state_properties": {"on": {"type": "boolean"}},
            "default_state": {"on": "false"},
        }
    if family == "illuminant_block_on":
        props["light"] = 15
        props["map_color"] = LIGHT_GRAY
        return base | {
            "state_properties": {"on": {"type": "boolean"}},
            "default_state": {"on": "true"},
        }
    if family in ("illuminant_panel", "illuminant_slab"):
        thickness = 0.25 if family == "illuminant_panel" else 0.5
        props["light"] = 15
        props["map_color"] = NONE
        base["template"] = "minecraft:amethyst_cluster"  # facing × waterlogged
        base["shapes"] = shapes_of("facing", thin_lamp(thickness))
        return base
    if family == "wall_lamp":
        props["light"] = 15
        props["map_color"] = NONE
        base["template"] = "minecraft:amethyst_cluster"
        base["shapes"] = shapes_of("facing", WALL_LAMP)
        base["collision_shapes"] = {"default": []}  # upstream noCollission()
        return base
    if family == "lightbulb":
        props["light"] = 14
        props["map_color"] = NONE
        base["template"] = "minecraft:amethyst_cluster"
        base["shapes"] = shapes_of("facing", LIGHTBULB)
        base["collision_shapes"] = {"default": []}
        return base
    if family == "rodlamp":
        props["light"] = 15
        props["map_color"] = TERRACOTTA_WHITE
        base["template"] = "minecraft:iron_chain"  # axis × waterlogged
        base["shapes"] = shapes_of("axis", ROD)
        return base
    if family == "lamp_post":
        props["light"] = 15  # scalar: only `top` emits 15 upstream (recorded gap)
        props["map_color"] = BLACK
        base["template"] = "minecraft:mangrove_roots"  # waterlogged only
        base["state_properties"] = {
            "position": {"type": "enum", "values": ["bottom", "middle", "top"]}
        }
        base["default_state"] = {"position": "bottom"}
        base["shapes"] = shapes_of("position", LAMP_POST)
        return base
    if family == "edge_light":
        props["light"] = 14
        props["map_color"] = NONE
        base["template"] = "minecraft:oak_fence"  # 4 sides × waterlogged
        base["shapes"] = edge_light(top=False)
        base["collision_shapes"] = {"default": []}
        return base
    if family == "edge_light_top":
        props["light"] = 14
        props["map_color"] = NONE
        base["template"] = "minecraft:oak_fence"
        base["shapes"] = edge_light(top=True)
        base["collision_shapes"] = {"default": []}
        return base
    raise ValueError(f"unknown family {family}")


FAMILIES = [
    "illuminant_block", "illuminant_block_on", "illuminant_slab",
    "illuminant_panel", "rodlamp", "lightbulb", "wall_lamp", "lamp_post",
    "edge_light", "edge_light_top",
]


def block_id(family: str, colour: str | None) -> str:
    """The jar's block id for a family's white or coloured member."""
    if family == "illuminant_block":
        return "illuminant_block" if colour is None else f"illuminant_{colour}_block"
    if family == "illuminant_block_on":
        return "illuminant_block_on" if colour is None else f"illuminant_{colour}_block_on"
    return family if colour is None else f"{family}_{colour}"


def all_blocks() -> list[tuple[str, str]]:
    """(family, id) for all 160 blocks in upstream's registration order."""
    out = []
    for family in FAMILIES:
        out.append((family, block_id(family, None)))
        for colour in COLOURS:
            out.append((family, block_id(family, colour)))
    return out


# --------------------------------------------------------------- helpers
def write(path: Path, data: bytes | str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data.encode() if isinstance(data, str) else data)


def json_file(path: Path, value) -> None:
    write(path, json.dumps(value, indent=2, sort_keys=True) + "\n")


def strip_bom(data: bytes) -> bytes:
    return data[3:] if data.startswith(b"\xef\xbb\xbf") else data


def ingredient(value):
    """1.21.1's `{"item": X}` / `{"tag": T}` ingredient to 26.3's string form."""
    if isinstance(value, dict):
        if "item" in value:
            return value["item"]
        if "tag" in value:
            return "#" + value["tag"]
    if isinstance(value, list):
        return [ingredient(item) for item in value]
    return value


def upgrade_recipe(recipe: dict) -> dict:
    if "key" in recipe:
        recipe["key"] = {key: ingredient(value) for key, value in recipe["key"].items()}
    if "ingredients" in recipe:
        recipe["ingredients"] = [ingredient(value) for value in recipe["ingredients"]]
    return recipe


def main() -> int:
    if not JAR.is_file():
        raise SystemExit(f"missing pack jar: {JAR}")
    if not (CARRY / "data/simplylight").is_dir():
        raise SystemExit(
            "missing content/carry: run "
            f"horizon-port-pack check {JAR} {OUT} first"
        )

    for stale in ("assets", "data"):
        shutil.rmtree(OUT / stale, ignore_errors=True)

    with zipfile.ZipFile(JAR) as jar:
        entries = [info for info in jar.infolist() if not info.is_dir()]
        names = [info.filename for info in entries]
        # Assets: blockstates, models, lang, textures. `edge_light.jsn` and
        # `edge_light_top.jsn` are upstream's dead typo files (no registered
        # block reads them), and `pack.mcmeta`/`logo.png` are not content.
        carried = 0
        for name in names:
            if not name.startswith("assets/simplylight/"):
                continue
            if name.endswith(".jsn"):
                continue
            data = jar.read(name)
            if name.endswith(".json"):
                data = strip_bom(data)
            write(OUT / name, data)
            carried += 1

        # Item tags (the `any_*` families) and the vanilla block-tag additions.
        for name in names:
            if name.startswith(("data/simplylight/tags/", "data/minecraft/tags/")):
                write(OUT / name, strip_bom(jar.read(name)))

        # Recipes: the carry tool's 26.3 files, then any it left out (they
        # named the left-out blocks) upgraded here.
        recipes = 0
        for name in names:
            if not (name.startswith("data/simplylight/recipe/") and name.endswith(".json")):
                continue
            target = OUT / name
            if target.is_file():
                recipes += 1
                continue
            raw = json.loads(jar.read(name))
            json_file(target, upgrade_recipe(raw))
            recipes += 1

    # Item definitions (26.3 `assets/<ns>/items/<id>.json`) for all 160 items.
    items = 0
    for source in sorted((CARRY / "assets/simplylight/items").glob("*.json")):
        write(OUT / "assets/simplylight/items" / source.name, strip_bom(source.read_bytes()))
        items += 1

    # Loot tables: already 26.3 (`"condition": {"type": …}`), carried verbatim.
    loot = 0
    for source in sorted((CARRY / "data/simplylight/loot_table/blocks").glob("*.json")):
        data = json.loads(source.read_text())
        json_file(OUT / "data/simplylight/loot_table/blocks" / source.name, data)
        loot += 1

    # Declarations for all 160 blocks.
    blocks = all_blocks()
    for family, ident in blocks:
        json_file(OUT / f"data/simplylight/horizon/block/{ident}.json", declaration(family, ident))

    # Creative tab: upstream's order, icon the inverted (on) white block.
    order = [f"simplylight:{ident}" for _, ident in blocks]
    json_file(
        OUT / "data/simplylight/horizon/creative_tab/lights.json",
        {"title": "Simply Light", "icon": "simplylight:illuminant_block_on", "items": order},
    )

    # Convention tags: 26.3 ships no `c:` tags, so the recipes that use them
    # would expand to an empty ingredient and never match.
    json_file(
        OUT / "data/c/tags/item/stones.json",
        {"values": [
            "minecraft:stone", "minecraft:granite", "minecraft:diorite",
            "minecraft:andesite", "minecraft:deepslate", "minecraft:tuff",
            "minecraft:calcite", "minecraft:basalt", "minecraft:smooth_basalt",
            "minecraft:blackstone", "minecraft:dripstone_block",
            "minecraft:netherrack",
        ]},
    )
    json_file(OUT / "data/c/tags/item/dusts/redstone.json", {"values": ["minecraft:redstone"]})
    json_file(OUT / "data/c/tags/item/dusts/glowstone.json", {"values": ["minecraft:glowstone_dust"]})

    write(
        OUT / "horizon-mod.toml",
        "# Carried from simplylight-1.5.3+1.21.1-b4.jar (MIT) for local use only.\n"
        'id = "simplylight"\n'
        'name = "Simply Light"\n'
        'version = "1.5.3"\n'
        'api = "0.2"\n'
        'side = "both"\n'
        'capabilities = ["registries"]\n',
    )

    print(json.dumps({
        "assets": carried, "items": items, "recipes": recipes,
        "loot_tables": loot, "blocks": len(blocks),
    }, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
