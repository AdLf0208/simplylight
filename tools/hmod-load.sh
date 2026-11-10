#!/usr/bin/env bash
# Prove the built content package (content/simplylight.hmod) loads on a real
# game: the shared, unmodded 1d63e0a5 game with `--dev-mod <the .hmod>` must
# register a representative block of each family and their items. A second
# launch of a fresh world WITHOUT --dev-mod is the negative control: the same
# ids must be unknown there, so the check cannot pass vacuously.
set -euo pipefail
export LC_ALL=C

CLONE=${CAMPAIGN_ROOT:?set CAMPAIGN_ROOT to a checkout of the ATM10-Horizon campaign tree}
PIN_BIN=$CLONE/ports/_shared/bin/horizon-1d63e0a5
CTL=${CTL:-$PIN_BIN/horizon-ctl}
GAME=${GAME:-$PIN_BIN/horizon-client}
HMOD=${HMOD:-$CLONE/ports/simplylight/content/simplylight.hmod}
RES=${RES:-${HORIZON_RES:-.local/horizon-client/26.3}}
SOCK=${SOCK:-/tmp/opencode/simplylight-hmod-load.sock}

[ -x "$CTL" ] || { echo "missing horizon-ctl: $CTL" >&2; exit 1; }
[ -x "$GAME" ] || { echo "missing horizon-client: $GAME" >&2; exit 1; }
[ -f "$HMOD" ] || { echo "missing package: $HMOD" >&2; exit 1; }
[ -d "$RES/assets" ] || { echo "missing prepared resources: $RES" >&2; exit 1; }

SCRATCH=$(mktemp -d /tmp/opencode/simplylight-hmod-home.XXXXXX)
export HORIZON_HOME=$SCRATCH/game
export HORIZON_LAUNCHER_HOME=$SCRATCH/launcher
export XDG_DATA_HOME=$SCRATCH/data
export XDG_CONFIG_HOME=$SCRATCH/config
export HORIZON_NO_AUDIO=1
mkdir -p "$(dirname "$SOCK")" "$XDG_CONFIG_HOME"
rm -f "$SOCK"
cd "$SCRATCH"

ctl() { "$CTL" --socket "$SOCK" "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

cleanup() {
    local status=$?
    echo "EXIT:$status"
    ctl quit >/dev/null 2>&1 || true
    sleep 1
    rm -rf "$SCRATCH" 2>/dev/null || true
}
trap cleanup EXIT

launch() { # world [extra args...]
    local world=$1; shift
    rm -f "$SOCK"
    "$CTL" --socket "$SOCK" launch \
        --game "$GAME" --world "$world" --seed 20261109 --creative --headless --wait \
        --game-dir "$SCRATCH/game" --resources "$RES" "$@" >/dev/null
    ctl wait-ready 120 >/dev/null
    ctl command "execute in minecraft:the_end run tp @s 0.5 80 2.5" >/dev/null
    ctl wait 20
    ctl command "execute in minecraft:the_end run fill -4 79 -4 8 79 8 minecraft:stone" >/dev/null
    ctl command "execute in minecraft:the_end run fill -4 80 -4 8 88 8 minecraft:air" >/dev/null
    ctl wait 4
}

# x y z block expected-state-prefix
CASES=(
    "0 80 0 simplylight:illuminant_block_on simplylight:illuminant_block_on"
    "2 80 0 simplylight:illuminant_panel[facing=up] simplylight:illuminant_panel"
    "4 80 0 simplylight:lamp_post_pink simplylight:lamp_post_pink"
    "6 80 0 simplylight:edge_light_top_red simplylight:edge_light_top_red"
)

echo "== launch WITH the package (--dev-mod $HMOD) =="
launch SimplyLightHmod --dev-mod "$HMOD"
for case_ in "${CASES[@]}"; do
    read -r x y z block want <<< "$case_"
    ctl command "execute in minecraft:the_end run setblock $x $y $z $block" >/dev/null
    ctl wait 2
    got=$(ctl block "$x" "$y" "$z" | jq -r '.state // .block // .name // "unknown"')
    echo "block $x,$y,$z = $got"
    case "$got" in
        "$want"*) ;;
        *) fail "the package did not register $block (read '$got')" ;;
    esac
done
ctl give simplylight:illuminant_block_on 1 >/dev/null
ctl give simplylight:lamp_post_pink 1 >/dev/null
ctl wait 4
ctl inventory | jq -e '[.counts["simplylight:illuminant_block_on"] // 0] | .[0] >= 1' >/dev/null \
    || fail "the packaged on lamp has no item"
ctl inventory | jq -e '[.counts["simplylight:lamp_post_pink"] // 0] | .[0] >= 1' >/dev/null \
    || fail "the packaged lamp post has no item"
echo "items simplylight:illuminant_block_on and simplylight:lamp_post_pink = 1"
ctl quit >/dev/null 2>&1 || true
sleep 2

echo "== control launch WITHOUT the package =="
launch SimplyLightNoHmod
for case_ in "${CASES[@]}"; do
    read -r x y z block _want <<< "$case_"
    ctl command "execute in minecraft:the_end run setblock $x $y $z $block" >/dev/null 2>&1 || true
    ctl wait 2
    got=$(ctl block "$x" "$y" "$z" | jq -r '.state // .block // .name // "unknown"')
    echo "control block $x,$y,$z = $got"
    [ "$got" = "minecraft:air" ] || fail "without the package $block is still '$got'"
done
echo "control: all four ids are unknown without the package"
echo "PASS: the .hmod registers the on lamp, a panel, the pink lamp post and a top edge light and their items; without it the same ids are refused"
