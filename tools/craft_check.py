#!/usr/bin/env python3
"""Craft Simply Light's recipes in a real crafting table.

Called by tools/e2e.sh with the open game's control socket. Uses the
harness's crafting grid (`ctl screen`: slots 100-108 row-major, result 200),
gives the ingredients, and asserts:

1. `aba/bcb/aba` with a=stone, b=glowstone, c=redstone -> four
   `simplylight:illuminant_block` (upstream's off-lamp recipe);
2. the same pattern with c=redstone_torch -> four
   `simplylight:illuminant_block_on` (the inverted lamp);
3. `" b " / "aaa"` with b=glowstone, a=stone -> eight `simplylight:lightbulb`;
4. eight off-lamps (the `#simplylight:any_lamp_off` item tag) around black dye
   -> eight `simplylight:illuminant_black_block` (proves the carried tag and
   one of the 83 recipes the carry tool skipped);
5. the shapeless `illuminant_black_block_on` -> one `illuminant_black_block`
   (the toggle recipe);
6. a stick in the bulb pattern's stone row leaves the result empty.

The table is cleared before every case, so a failed/untaken result cannot leak
into the next grid. Exits 1 with the observed result on the first mismatch.
"""
import json
import subprocess
import sys

GLOWSTONE = "minecraft:glowstone"
STONE = "minecraft:stone"
STICK = "minecraft:stick"


def main():
    sock, ctl, x, y, z = sys.argv[1:6]

    def run(*args):
        out = subprocess.run([ctl, "--socket", sock, *args], text=True, capture_output=True)
        try:
            return json.loads(out.stdout)
        except json.JSONDecodeError:
            raise SystemExit(f"ctl {' '.join(args)}: {out.stdout}{out.stderr}")

    def wait(ticks=4):
        run("wait", str(ticks))

    def slots():
        screen = run("screen")
        if "slots" not in screen:
            raise SystemExit(f"no menu is open: {screen}")
        return screen["slots"]

    def find(item):
        for slot in slots():
            if slot.get("item") == item:
                return slot["slot"]
        raise SystemExit(f"missing ingredient {item} in the inventory")

    def result():
        stack = [s for s in slots() if s["slot"] == 200]
        if not stack or not stack[0].get("item"):
            return None
        return stack[0]

    def place(item, targets, mode="left"):
        slot = find(item)
        run("click-slot", str(slot))
        wait(1)
        for target in targets:
            if mode == "right":
                run("click-slot", str(target), "right")
            else:
                run("click-slot", str(target))
            wait(1)
        run("click-slot", str(slot))
        wait(2)

    def setup(items):
        try:
            run("close")
        except SystemExit:
            pass
        wait(5)
        run("setblock", x, y, z, "minecraft:air")
        run("setblock", x, y, z, "minecraft:crafting_table")
        wait(2)
        run("command", f"tp @s {float(x) - 0.5} {y} {float(z) + 0.5}")
        wait(3)
        run("command", "clear @s")
        for item, count in items:
            run("give", item, str(count))
        wait(5)
        run("interact", x, y, z)
        wait(5)

    failures = []

    def check(label, items, placements, want_item, want_count):
        setup(items)
        for item, targets, mode in placements:
            place(item, targets, mode)
        got = result()
        print(f"{label} ->", json.dumps(got))
        if not got or got.get("item") != want_item or got.get("count") != want_count:
            failures.append(f"{label}: expected {want_count} {want_item}, got {got}")

    def empty_control(label, items, placements):
        setup(items)
        for item, targets, mode in placements:
            place(item, targets, mode)
        got = result()
        print(f"{label} ->", json.dumps(got))
        if got is not None:
            failures.append(f"{label}: control crafted {got['item']}")

    # 1. The off lamp: a=stone b=glowstone c=redstone.
    check(
        "stone/glowstone/redstone",
        [(STONE, 4), (GLOWSTONE, 4), ("minecraft:redstone", 1)],
        [(STONE, ["100", "102", "106", "108"], "right"),
         (GLOWSTONE, ["101", "103", "105", "107"], "right"),
         ("minecraft:redstone", ["104"], "left")],
        "simplylight:illuminant_block",
        4,
    )

    # 2. The inverted lamp: the same grid with a redstone torch.
    check(
        "stone/glowstone/redstone torch",
        [(STONE, 4), (GLOWSTONE, 4), ("minecraft:redstone_torch", 1)],
        [(STONE, ["100", "102", "106", "108"], "right"),
         (GLOWSTONE, ["101", "103", "105", "107"], "right"),
         ("minecraft:redstone_torch", ["104"], "left")],
        "simplylight:illuminant_block_on",
        4,
    )

    # 3. Bulbs: glowstone over a row of stone.
    check(
        "glowstone over stone",
        [(GLOWSTONE, 1), (STONE, 3)],
        [(GLOWSTONE, ["101"], "right"),
         (STONE, ["103", "104", "105"], "right")],
        "simplylight:lightbulb",
        8,
    )

    # 4. The dyed recipe: eight off-lamps (the any_lamp_off tag) around a dye.
    check(
        "8 off-lamps + black dye",
        [("simplylight:illuminant_block", 8), ("minecraft:black_dye", 1)],
        [("simplylight:illuminant_block",
          ["100", "101", "102", "103", "105", "106", "107", "108"], "right"),
         ("minecraft:black_dye", ["104"], "left")],
        "simplylight:illuminant_black_block",
        8,
    )

    # 5. The toggle recipe (shapeless).
    check(
        "black on-lamp -> off-lamp",
        [("simplylight:illuminant_black_block_on", 1)],
        [("simplylight:illuminant_black_block_on", ["100"], "left")],
        "simplylight:illuminant_black_block",
        1,
    )

    # 6. The bulb recipe's deliberately unmatched control.
    empty_control(
        "glowstone over sticks",
        [(GLOWSTONE, 1), (STICK, 3)],
        [(GLOWSTONE, ["101"], "right"),
         (STICK, ["103", "104", "105"], "right")],
    )

    run("close")
    wait(3)
    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        raise SystemExit(1)
    print(
        "recipe PASS: the off and on lamp recipes craft 4, the bulb recipe 8, "
        "the dyed recipe 8 through #simplylight:any_lamp_off, the toggle "
        "recipe 1, and the stick control stays empty"
    )


if __name__ == "__main__":
    main()
