#!/usr/bin/env bash
# In-game check for the Simply Light content: the 160 light blocks.
#
# Default run (creative launch on the shared unmodded 1d63e0a5 game with
# `--dev-mod content/`, The End):
#   1. all 160 block ids bind their default state;
#   2. every declared state of every block binds and reads back — the two lamp
#      blocks' `on`, the panel/slab/wall lamp/lightbulb `facing × waterlogged`,
#      the rod lamp's `axis × waterlogged`, the lamp post's
#      `position × waterlogged` and both edge lights' 4-side × waterlogged
#      combinations: 2048 states in total;
#   3. an isolated block emits the level upstream sets: 15 for the panel, slab,
#      wall lamp, rod lamp, lamp post and the on lamp; 14 for the light bulb and
#      both edge lights; 0 for the off lamp, against a vanilla glowstone's 15
#      and stone's 0 (the differential);
#   4. one block of every family is mined in survival and drops itself
#      (both edge lights aimed on their 1/16 strip);
#   5. the off/on lamp, bulb, dyed and toggle recipes craft in a real crafting
#      table and a stick control stays empty;
#   6. the block tags (`#minecraft:mineable/pickaxe`,
#      `#minecraft:wall_post_override`) hold;
#   7. all 160 items are `/give`-able and the creative tab lists all 160;
#   8. one item of every family places and reads back;
#   9. unknown ids and invalid states are refused.
#
# COUNTERFACTUAL=1 launches the same run WITHOUT `--dev-mod content/`: the
# same ids are unknown there, and vanilla glowstone still emits 15, so the run
# is not vacuous. NEGATIVE=1 (implies the counterfactual) asserts the
# deliberately false "the content is loaded without --dev-mod", so the run MUST
# exit 1. SELFTEST=1 asserts a deliberately wrong panel facing in the default
# run, so the state read-back MUST exit 1. Every leg prints `EXIT:<status>` from
# the cleanup trap as its last line.
set -euo pipefail

CLONE=${CAMPAIGN_ROOT:?set CAMPAIGN_ROOT to a checkout of the ATM10-Horizon campaign tree}
PORT=$CLONE/ports/simplylight
PIN_BIN=$CLONE/ports/_shared/bin/horizon-1d63e0a5
CTL=${CTL:-$PIN_BIN/horizon-ctl}
GAME=${GAME:-$PIN_BIN/horizon-client}
RES=${RES:-${HORIZON_RES:-.local/horizon-client/26.3}}
SOCK=${SOCK:-/tmp/opencode/simplylight-e2e.sock}
COUNTERFACTUAL=${COUNTERFACTUAL:-0}
NEGATIVE=${NEGATIVE:-0}
SELFTEST=${SELFTEST:-0}
STATE_WAIT=${STATE_WAIT:-1}

if [ "$NEGATIVE" = 1 ]; then
    COUNTERFACTUAL=1
fi

[ -x "$CTL" ] || { echo "missing horizon-ctl: $CTL" >&2; exit 1; }
[ -x "$GAME" ] || { echo "missing horizon-client: $GAME" >&2; exit 1; }
[ -d "$RES/assets" ] || { echo "missing prepared resources: $RES" >&2; exit 1; }
[ -f "$PORT/content/horizon-mod.toml" ] || { echo "missing content mod: $PORT/content" >&2; exit 1; }

DYES=(light_gray gray black brown red orange yellow lime green cyan light_blue blue purple magenta pink)
COLOURS=(white "${DYES[@]}")
FACINGS=(down up north south west east)
AXES=(x y z)
POSITIONS=(bottom middle top)
FAMILIES=(illuminant_block_on illuminant_block illuminant_slab illuminant_panel rodlamp lightbulb wall_lamp lamp_post edge_light edge_light_top)
SHAPES=(illuminant_panel illuminant_slab wall_lamp rodlamp lightbulb lamp_post edge_light edge_light_top)

SCRATCH=$(mktemp -d /tmp/opencode/simplylight-home.XXXXXX)
export HORIZON_HOME=$SCRATCH/game
export HORIZON_LAUNCHER_HOME=$SCRATCH/launcher
export XDG_DATA_HOME=$SCRATCH/data
export XDG_CONFIG_HOME=$SCRATCH/config
export HORIZON_NO_AUDIO=1
mkdir -p "$(dirname "$SOCK")"
rm -f "$SOCK"
cd "$SCRATCH"

ctl() { "$CTL" --socket "$SOCK" "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
say() { echo "+ $*"; }
count_item() { ctl inventory | jq -r --arg i "$1" '.counts[$i] // 0'; }
block_state() { ctl block "$1" "$2" "$3" | jq -r '.block // "unknown"'; }
full_state() { ctl block "$1" "$2" "$3" | jq -r '.state // "unknown"'; }
light_hex() { ctl light "$1" "$2" "$3" "$1" "$2" "$3" | jq -r '.block // "unknown"'; }
end() { ctl command "execute in minecraft:the_end run $1"; }

state_has() { # state key value
    local state=$1 key=$2 want=$3
    echo "$state" | grep -Eq "(^|[,\[)${key}=${want}([],]|$)" || fail "$state: expected $key=$want"
}

# The family member's block id; `white` is the family's uncoloured member.
fam_id() { # family colour
    case "$1" in
        illuminant_block) [ "$2" = white ] && echo simplylight:illuminant_block || echo "simplylight:illuminant_$2_block" ;;
        illuminant_block_on) [ "$2" = white ] && echo simplylight:illuminant_block_on || echo "simplylight:illuminant_$2_block_on" ;;
        *) [ "$2" = white ] && echo "simplylight:$1" || echo "simplylight:$1_$2" ;;
    esac
}

# All 16 members of a family, one id per line.
fam_ids() {
    local colour
    for colour in "${COLOURS[@]}"; do
        fam_id "$1" "$colour"
    done
}

# Six stone neighbours make every facing survivable at the state centre.
CX=0; CY=100; CZ=0

bind() { # id [props]
    local id=$1 props=${2:-} target state pair key value
    target=$id
    [ -n "$props" ] && target="$id[$props]"
    ctl setblock "$CX" "$CY" "$CZ" "$target" >/dev/null || fail "setblock $target failed"
    [ "$STATE_WAIT" != 0 ] && ctl wait "$STATE_WAIT" >/dev/null
    state=$(full_state "$CX" "$CY" "$CZ")
    case "$state" in
        "$id"*) ;;
        *) fail "setblock $target read '$state'" ;;
    esac
    if [ -n "$props" ]; then
        local pairs
        IFS=',' read -ra pairs <<< "$props"
        for pair in "${pairs[@]}"; do
            key=${pair%%=*}; value=${pair##*=}
            state_has "$state" "$key" "$value"
        done
    fi
}

cleanup() {
    local status=$?
    echo "EXIT:$status"
    ctl quit >/dev/null 2>&1 || true
    sleep 1
    rm -rf "$SCRATCH" || true
}
trap cleanup EXIT

launch() { # world [extra ctl args...]
    local world=$1; shift
    rm -f "$SOCK"
    "$CTL" --socket "$SOCK" launch \
        --game "$GAME" --world "$world" --seed 20261109 --creative --offscreen --wait \
        --game-dir "$SCRATCH/game" --resources "$RES" "$@"
    ctl wait-ready 240
}

platform() {
    say "The End platform at y=79, a stone shell for the state centre"
    end "forceload add -12 -12 340 12"
    end "tp @s 0.5 80 2.5"
    ctl wait 40
    end "fill -12 79 -12 340 79 12 minecraft:stone"
    end "kill @e[type=minecraft:item]"
    end "kill @e[type=minecraft:ender_dragon]"
    end "kill @e[type=minecraft:end_crystal]"
    end "difficulty peaceful"
    end "tp @s 0.5 80 2.5"
    ctl wait 10
    # Killing the dragon opens the victory/credits screen, which makes `ctl
    # break` refuse until it is closed.
    ctl close >/dev/null 2>&1 || true
    ctl wait 5
    for d in "0 -1 0" "0 1 0" "0 0 -1" "0 0 1" "-1 0 0" "1 0 0"; do
        read -r dx dy dz <<< "$d"
        ctl setblock "$((CX + dx))" "$((CY + dy))" "$((CZ + dz))" minecraft:stone >/dev/null
    done
    ctl setblock "$CX" "$CY" "$CZ" minecraft:air >/dev/null
}

# --------------------------------------------------- counterfactual / negative
if [ "$COUNTERFACTUAL" = 1 ]; then
    say "counterfactual: the same run WITHOUT --dev-mod content/"
    launch SimplyLightControl
    platform
    end "setblock 0 80 0 minecraft:glowstone"
    ctl wait 5
    glow=$(light_hex 0 80 0)
    echo "vanilla glowstone light=$glow"
    [ "$glow" = "f" ] || fail "vanilla glowstone emits '$glow', expected f (15)"
    end "setblock 4 80 0 simplylight:illuminant_block_on" >/dev/null 2>&1 || true
    ctl wait 2
    got=$(block_state 4 80 0)
    echo "without the content, setblock simplylight:illuminant_block_on reads '$got'"
    if [ "$NEGATIVE" = 1 ]; then
        if [ "$got" != "minecraft:air" ]; then
            fail "NEGATIVE run: the content is loaded without --dev-mod; the control is broken"
        fi
        echo "FAIL: NEGATIVE: the deliberately false assertion (the content is loaded without --dev-mod) tripped, as it must; the --dev-mod differential is live (this exit 1 is the proof)" >&2
        exit 1
    fi
    [ "$got" = "minecraft:air" ] || fail "simplylight:illuminant_block_on exists without the content mod (read '$got')"
    if ctl give simplylight:illuminant_block_on 1 >/dev/null 2>&1; then
        fail "give simplylight:illuminant_block_on succeeded without the content mod"
    fi
    echo "the content ids are refused without --dev-mod, and vanilla glowstone still emits 15"
    echo "PASS: counterfactual (no --dev-mod: the 160 ids are unknown there; a vanilla glowstone emits 15)"
    exit 0
fi

say "launch (offscreen renderer, creative, content --dev-mod content/)"
launch SimplyLightE2E --dev-mod "$PORT/content"
platform

# --------------------------------------------------------------- state bind
say "every one of the 160 block ids binds its default state"
n=0
for family in "${FAMILIES[@]}"; do
    while IFS= read -r id; do
        bind "$id"
        n=$((n + 1))
    done < <(fam_ids "$family")
done
[ "$n" -eq 160 ] || fail "bound $n default states, expected 160"
echo "160/160 default states bound (10 families × 16 colours)"

# ---------------------------------------------------------- selftest (early)
if [ "$SELFTEST" = 1 ]; then
    say "selftest: the state read-back must reject a deliberately wrong facing"
    ctl setblock "$CX" "$CY" "$CZ" "simplylight:illuminant_panel[facing=up]" >/dev/null
    ctl wait "$STATE_WAIT" >/dev/null
    state=$(full_state "$CX" "$CY" "$CZ")
    echo "SELFTEST: read $state"
    if echo "$state" | grep -Eq 'facing=down'; then
        fail "SELFTEST: the deliberately wrong facing=down assertion passed; the state read-back is vacuous"
    fi
    echo "FAIL: SELFTEST: read '$state' where the deliberately wrong assertion wanted facing=down; the state read-back is live (this exit 1 is the proof)" >&2
    exit 1
fi

sweep_on() { # id
    bind "$1" "on=false"
    bind "$1" "on=true"
}

sweep_facing() { # id
    local face w
    for face in "${FACINGS[@]}"; do
        for w in false true; do
            bind "$1" "facing=${face},waterlogged=${w}"
        done
    done
}

sweep_axis() { # id
    local axis w
    for axis in "${AXES[@]}"; do
        for w in false true; do
            bind "$1" "axis=${axis},waterlogged=${w}"
        done
    done
}

sweep_position() { # id
    local position w
    for position in "${POSITIONS[@]}"; do
        for w in false true; do
            bind "$1" "position=${position},waterlogged=${w}"
        done
    done
}

sweep_edge() { # id
    local combo w bits north south east west i
    for combo in $(seq 0 15); do
        bits=()
        for i in 0 1 2 3; do
            if [ $((combo >> i & 1)) -eq 1 ]; then bits+=(true); else bits+=(false); fi
        done
        north=${bits[0]}; south=${bits[1]}; east=${bits[2]}; west=${bits[3]}
        for w in false true; do
            bind "$1" "north=${north},south=${south},east=${east},west=${west},waterlogged=${w}"
        done
    done
}

sweep_each() { # label family per-block-sweep expected-per-block
    local label=$1 family=$2 sweep=$3 per=$4 n=0 id
    while IFS= read -r id; do
        "$sweep" "$id"
        n=$((n + per))
    done < <(fam_ids "$family")
    local expect=$((16 * per))
    [ "$n" -eq "$expect" ] || fail "$label: bound $n states, expected $expect"
    echo "$n/$n $label states bind (16 blocks × $per)"
}

say "every lamp state binds: 32 blocks × 2 on values"
sweep_each lamp illuminant_block_on sweep_on 2
sweep_each lamp illuminant_block sweep_on 2
say "every slab state binds: 6 facings × 2 waterlogged"
sweep_each slab illuminant_slab sweep_facing 12
say "every panel state binds: 6 facings × 2 waterlogged"
sweep_each panel illuminant_panel sweep_facing 12
say "every wall-lamp state binds: 6 facings × 2 waterlogged"
sweep_each wall-lamp wall_lamp sweep_facing 12
say "every lightbulb state binds: 6 facings × 2 waterlogged"
sweep_each lightbulb lightbulb sweep_facing 12
say "every rod-lamp state binds: 3 axes × 2 waterlogged"
sweep_each rod-lamp rodlamp sweep_axis 6
say "every lamp-post state binds: 3 positions × 2 waterlogged"
sweep_each lamp-post lamp_post sweep_position 6
say "every edge-light state binds: 4 sides × 2 waterlogged"
sweep_each edge-light edge_light sweep_edge 32
say "every top edge-light state binds: 4 sides × 2 waterlogged"
sweep_each top-edge-light edge_light_top sweep_edge 32
echo "2048/2048 declared states total"

# ------------------------------------------------------------------- light
say "light: the families' levels against a vanilla glowstone and stone"
X=0
declare -A LIGHT
for family in "${SHAPES[@]}"; do
    id=$(fam_id "$family" white)
    end "setblock $X 80 0 $id" >/dev/null
    LIGHT[$family]=$X
    X=$((X + 20))
done
end "setblock $X 80 0 simplylight:illuminant_block_on" >/dev/null
LIGHT[on]=$X; X=$((X + 20))
end "setblock $X 80 0 simplylight:illuminant_block" >/dev/null
LIGHT[off]=$X; X=$((X + 20))
end "setblock $X 80 0 minecraft:glowstone" >/dev/null
LIGHT[glowstone]=$X; X=$((X + 20))
end "setblock $X 80 0 minecraft:stone" >/dev/null
LIGHT[stone]=$X
ctl wait 10
for key in "${!LIGHT[@]}"; do
    printf '%s=%s ' "$key" "$(light_hex "${LIGHT[$key]}" 80 0)"
done
echo
[ "$(light_hex "${LIGHT[illuminant_panel]}" 80 0)" = "f" ] || fail "the panel does not emit 15"
[ "$(light_hex "${LIGHT[illuminant_slab]}" 80 0)" = "f" ] || fail "the slab does not emit 15"
[ "$(light_hex "${LIGHT[wall_lamp]}" 80 0)" = "f" ] || fail "the wall lamp does not emit 15"
[ "$(light_hex "${LIGHT[rodlamp]}" 80 0)" = "f" ] || fail "the rod lamp does not emit 15"
[ "$(light_hex "${LIGHT[lamp_post]}" 80 0)" = "f" ] || fail "the lamp post does not emit 15"
[ "$(light_hex "${LIGHT[on]}" 80 0)" = "f" ] || fail "the on lamp does not emit 15"
[ "$(light_hex "${LIGHT[lightbulb]}" 80 0)" = "e" ] || fail "the light bulb does not emit 14"
[ "$(light_hex "${LIGHT[edge_light]}" 80 0)" = "e" ] || fail "the edge light does not emit 14"
[ "$(light_hex "${LIGHT[edge_light_top]}" 80 0)" = "e" ] || fail "the top edge light does not emit 14"
[ "$(light_hex "${LIGHT[off]}" 80 0)" = "0" ] || fail "the off lamp emits light"
[ "$(light_hex "${LIGHT[glowstone]}" 80 0)" = "f" ] || fail "vanilla glowstone does not emit 15"
[ "$(light_hex "${LIGHT[stone]}" 80 0)" = "0" ] || fail "stone emits light"
echo "15: panel/slab/wall/rod/post/on-lamp; 14: bulb/edge/edge-top; 0: off lamp and stone; the off lamp differs from the vanilla glowstone"

# ------------------------------------------------------------------- drops
say "drops: one block of every family drops itself"
ctl command "gamemode survival @s" >/dev/null
ctl command "clear @s" >/dev/null
# x|block|aim — `centre` aims at the block centre from 2 blocks away (the ray
# enters the block and hits the shape wherever it is); the two edge lights are
# 1/16 strips, so they are aimed at a point on the north strip from the north.
DROPS=(
    "200|simplylight:illuminant_panel|centre"
    "203|simplylight:illuminant_slab|centre"
    "206|simplylight:wall_lamp|centre"
    "209|simplylight:rodlamp|centre"
    "212|simplylight:lightbulb|centre"
    "215|simplylight:lamp_post|centre"
    "218|simplylight:illuminant_block_on|centre"
    "221|simplylight:edge_light[north=true,south=true,east=true,west=true,waterlogged=false]|edge-bottom"
    "224|simplylight:edge_light_top[north=true,south=true,east=true,west=true,waterlogged=false]|edge-top"
)
for entry in "${DROPS[@]}"; do
    IFS='|' read -r X block aim <<< "$entry"
    end "setblock $X 80 0 $block"
done
ctl wait 10
for entry in "${DROPS[@]}"; do
    IFS='|' read -r X block aim <<< "$entry"
    id=${block%%[*}
    case "$aim" in
        centre)
            ctl command "tp @s $((X + 2)).5 80 0.5" >/dev/null
            ctl wait 6
            ctl look-at-block "$X" 80 0 >/dev/null || true
            ;;
        edge-bottom)
            ctl command "tp @s $((X)).5 80 -1.5" >/dev/null
            ctl wait 6
            ctl look-at "$((X)).5" 80.03 0.02 >/dev/null || true
            ;;
        edge-top)
            ctl command "tp @s $((X)).5 80 -1.5" >/dev/null
            ctl wait 6
            ctl look-at "$((X)).5" 80.97 0.02 >/dev/null || true
            ;;
    esac
    ctl wait 2
    broken=$(ctl break "$X" 80 0) || { echo "break reply: $broken"; fail "cannot break $id"; }
    echo "$broken" | jq -c --arg want "$id" '{scenario:$want,block,block_before,drops}'
    [ "$(echo "$broken" | jq -r '.block')" = "minecraft:air" ] || fail "$id did not break"
    got=$(echo "$broken" | jq -r --arg i "$id" '.drops[$i] // 0')
    [ "$got" -ge 1 ] || fail "$id dropped $got of itself"
done
echo "drops PASS: 9/9 blocks drop themselves (the eight shape families and the on lamp)"

# ------------------------------------------------------------------- recipe
say "craft: the off/on lamp, bulb, dyed and toggle recipes; a stick control"
ctl command "clear @s" >/dev/null
ctl command "gamemode survival @s" >/dev/null
end "setblock 300 80 2 minecraft:crafting_table"
ctl command "tp @s 300.5 80 3.5" >/dev/null
ctl wait 10
python3 "$PORT/tools/craft_check.py" "$SOCK" "$CTL" 300 80 2 || fail "the recipe check failed"
ctl command "gamemode creative @s" >/dev/null
ctl command "clear @s" >/dev/null
ctl wait 3
echo "recipes PASS"

# ---------------------------------------------------------------------- tag
say "block tags: #minecraft:mineable/pickaxe and #minecraft:wall_post_override"
end "setblock 0 80 0 simplylight:rodlamp"
end "setblock 1 80 0 simplylight:lightbulb[facing=up]"
end "setblock 2 80 0 minecraft:stone"
ctl wait 5
ctl command "execute in minecraft:the_end if block 0 80 0 #minecraft:mineable/pickaxe run say TAG_ROD" >/dev/null
ctl command "execute in minecraft:the_end if block 1 80 0 #minecraft:wall_post_override run say TAG_BULB" >/dev/null
ctl command "execute in minecraft:the_end if block 2 80 0 #minecraft:wall_post_override run say TAG_STONE" >/dev/null
ctl wait 5
messages=$(ctl messages 40 | jq -r '.chat[]')
echo "$messages" | grep -q '] TAG_ROD' || fail "the rod lamp is not in #minecraft:mineable/pickaxe"
echo "$messages" | grep -q '] TAG_BULB' || fail "the light bulb is not in #minecraft:wall_post_override"
echo "$messages" | grep -q '] TAG_STONE' && fail "stone is in #minecraft:wall_post_override"
echo "tag PASS"

# --------------------------------------------------------------------- item
say "all 160 items are give-able; the creative tab lists all 160"
ctl command "gamemode creative @s" >/dev/null
ctl command "clear @s" >/dev/null
n=0
for family in "${FAMILIES[@]}"; do
    while IFS= read -r id; do
        if ! ctl give "$id" 1 >/dev/null 2>&1; then
            # A full inventory is not an unknown item: clear and retry once.
            ctl command "clear @s" >/dev/null
            ctl give "$id" 1 >/dev/null || fail "give $id failed"
        fi
        n=$((n + 1))
        if [ $((n % 20)) -eq 0 ]; then
            ctl command "clear @s" >/dev/null
        fi
    done < <(fam_ids "$family")
done
[ "$n" -eq 160 ] || fail "gave $n items, expected 160"
ctl command "clear @s" >/dev/null
ctl give simplylight:illuminant_block_on 1 >/dev/null
ctl give simplylight:lamp_post_pink 1 >/dev/null
ctl wait 5
[ "$(count_item simplylight:illuminant_block_on)" -ge 1 ] || fail "the on lamp did not land in the inventory"
[ "$(count_item simplylight:lamp_post_pink)" -ge 1 ] || fail "the pink lamp post did not land in the inventory"
if ctl give simplylight:not_a_lamp 1 >/dev/null 2>&1; then
    fail "give simplylight:not_a_lamp succeeded"
fi
echo "160/160 items give-able; sample items land in the inventory"

CREATIVE=$(find "$SCRATCH/game/.horizon-cache/mod-content" -name creative-inventory.json 2>/dev/null | head -1)
[ -n "$CREATIVE" ] || fail "no creative-inventory.json under $SCRATCH/game/.horizon-cache/mod-content"
missing=0
for family in "${FAMILIES[@]}"; do
    while IFS= read -r id; do
        grep -q "$id" "$CREATIVE" || missing=$((missing + 1))
    done < <(fam_ids "$family")
done
[ "$missing" -eq 0 ] || fail "the creative tab misses $missing items"
echo "creative tab lists all 160 items"

# ---------------------------------------------------------------- placement
say "one item of every family places and reads back"
ctl command "gamemode creative @s" >/dev/null
ctl command "clear @s" >/dev/null
PX=0
place_family() { # family [state-key value]
    local family=$1 key=${2:-} value=${3:-} id state
    id=$(fam_id "$family" white)
    # Stand two blocks east of an air cell whose west neighbour is stone: the
    # placement ray enters the cell's east face, and the support that an
    # amethyst-cluster template needs (the block opposite `facing`) is there.
    ctl setblock "$((PX - 1))" 80 0 minecraft:stone >/dev/null
    ctl setblock "$PX" 80 0 minecraft:air >/dev/null
    ctl command "tp @s $((PX + 2)).5 80 0.5" >/dev/null
    ctl wait 2
    # One item at a time: `ctl select` picks a hotbar slot, and ten items would
    # push the last one into the main inventory.
    ctl command "clear @s" >/dev/null
    ctl give "$id" 1 >/dev/null
    ctl wait 3
    ctl select "$id" >/dev/null
    ctl wait 2
    ctl place "$PX" 80 0 --item "$id" >/dev/null || fail "cannot place $id"
    ctl wait 3
    state=$(full_state "$PX" 80 0)
    echo "placed $id -> $state"
    [ "$(block_state "$PX" 80 0)" = "$id" ] || fail "the placed $id is '$(block_state "$PX" 80 0)'"
    if [ -n "$key" ]; then
        state_has "$state" "$key" "$value"
    fi
    PX=$((PX + 3))
}

place_family illuminant_block on false
place_family illuminant_block_on on true
place_family illuminant_slab
place_family illuminant_panel
place_family rodlamp
place_family lightbulb
place_family wall_lamp
place_family lamp_post
place_family edge_light
place_family edge_light_top
say "wrong-name controls fail"
ctl setblock 6 80 5 minecraft:air >/dev/null
ctl setblock 6 80 5 simplylight:bogus_lamp >/dev/null 2>&1 || true
[ "$(block_state 6 80 5)" = "minecraft:air" ] || fail "simplylight:bogus_lamp became a block"
ctl setblock 7 80 5 minecraft:air >/dev/null
ctl setblock 7 80 5 "simplylight:illuminant_panel[facing=sideways]" >/dev/null 2>&1 || true
[ "$(block_state 7 80 5)" = "minecraft:air" ] || fail "an invalid facing became a block"
echo "unknown ids and invalid states are refused"

echo "PASS: 2048/2048 states bind (160 defaults; 64 lamp, 192 slab, 192 panel, 192 wall lamp, 192 bulb, 96 rod, 96 post, 512 edge, 512 top edge), light is 15 for panel/slab/wall/rod/post/on-lamp, 14 for bulb/edge/edge-top and 0 for the off lamp, 9/9 blocks self-drop, six recipes craft with an empty stick control, the block tags hold, 160 items give and the tab lists 160, one item of every family places, and unknown ids are refused"
