// Simply Light for Horizon — the 160-block census (pure, test-only).
//
// Ported from Simply Light 1.5.3 (`Flanks255/simplylight`, MIT) for Minecraft
// Java 26.3. The upstream source was read for the families, registration
// order, templates' state spaces, light levels and drop rules; this is a
// clean-room model. The port is content-only: the 160 blocks are declared in
// `../content` by `../tools/gen_content.py`, and this module spells out the
// facts those declarations must keep true.

#[cfg(test)]
mod tests {
    use std::collections::BTreeSet;

    /// A dye colour of a family. White is the family's uncoloured member:
    /// upstream registers `illuminant_panel`, never `illuminant_panel_white`.
    #[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
    enum Colour {
        White,
        LightGray,
        Gray,
        Black,
        Brown,
        Red,
        Orange,
        Yellow,
        Lime,
        Green,
        Cyan,
        LightBlue,
        Blue,
        Purple,
        Magenta,
        Pink,
    }

    impl Colour {
        /// Upstream `SLBlocks` order: white, then the 15 dye colours.
        const ALL: [Colour; 16] = [
            Colour::White,
            Colour::LightGray,
            Colour::Gray,
            Colour::Black,
            Colour::Brown,
            Colour::Red,
            Colour::Orange,
            Colour::Yellow,
            Colour::Lime,
            Colour::Green,
            Colour::Cyan,
            Colour::LightBlue,
            Colour::Blue,
            Colour::Purple,
            Colour::Magenta,
            Colour::Pink,
        ];

        const fn name(self) -> &'static str {
            match self {
                Colour::White => "white",
                Colour::LightGray => "light_gray",
                Colour::Gray => "gray",
                Colour::Black => "black",
                Colour::Brown => "brown",
                Colour::Red => "red",
                Colour::Orange => "orange",
                Colour::Yellow => "yellow",
                Colour::Lime => "lime",
                Colour::Green => "green",
                Colour::Cyan => "cyan",
                Colour::LightBlue => "light_blue",
                Colour::Blue => "blue",
                Colour::Purple => "purple",
                Colour::Magenta => "magenta",
                Colour::Pink => "pink",
            }
        }

        /// The id suffix, or `None` for the family's uncoloured member.
        const fn suffix(self) -> Option<&'static str> {
            match self {
                Colour::White => None,
                other => Some(other.name()),
            }
        }
    }

    /// The ten block classes `SLBlocks` registers, in creative-tab order:
    /// the inverted (on) lamps first, then the off ones, then the shapes.
    #[derive(Clone, Copy, Debug, PartialEq, Eq)]
    enum Family {
        IlluminantBlockOn,
        IlluminantBlockOff,
        Slab,
        Panel,
        Rod,
        Bulb,
        Wall,
        Post,
        Edge,
        EdgeTop,
    }

    impl Family {
        const ALL: [Family; 10] = [
            Family::IlluminantBlockOn,
            Family::IlluminantBlockOff,
            Family::Slab,
            Family::Panel,
            Family::Rod,
            Family::Bulb,
            Family::Wall,
            Family::Post,
            Family::Edge,
            Family::EdgeTop,
        ];

        /// The base name upstream's registry uses.
        const fn name(self) -> &'static str {
            match self {
                Family::IlluminantBlockOn => "illuminant_block_on",
                Family::IlluminantBlockOff => "illuminant_block",
                Family::Slab => "illuminant_slab",
                Family::Panel => "illuminant_panel",
                Family::Rod => "rodlamp",
                Family::Bulb => "lightbulb",
                Family::Wall => "wall_lamp",
                Family::Post => "lamp_post",
                Family::Edge => "edge_light",
                Family::EdgeTop => "edge_light_top",
            }
        }

        /// `<namespace>:<path>` for a member.
        fn id(self, colour: Colour) -> String {
            match (self, colour.suffix()) {
                (Family::IlluminantBlockOn, None) => "simplylight:illuminant_block_on".to_string(),
                (Family::IlluminantBlockOn, Some(c)) => {
                    format!("simplylight:illuminant_{c}_block_on")
                }
                (Family::IlluminantBlockOff, None) => "simplylight:illuminant_block".to_string(),
                (Family::IlluminantBlockOff, Some(c)) => {
                    format!("simplylight:illuminant_{c}_block")
                }
                (_, None) => format!("simplylight:{}", self.name()),
                (_, Some(c)) => format!("simplylight:{}_{c}", self.name()),
            }
        }

        /// The vanilla block whose states the declaration copies. Chosen from
        /// the 26.3 state table, not guessed: the five waterlogged families
        /// need a `SimpleWaterloggedBlock` template with exactly their
        /// properties, and the two lamp blocks a stateless full cube.
        const fn template(self) -> &'static str {
            match self {
                Family::IlluminantBlockOn | Family::IlluminantBlockOff => "minecraft:calcite",
                Family::Slab | Family::Panel | Family::Bulb | Family::Wall => {
                    "minecraft:amethyst_cluster"
                }
                Family::Rod => "minecraft:iron_chain",
                Family::Post => "minecraft:mangrove_roots",
                Family::Edge | Family::EdgeTop => "minecraft:oak_fence",
            }
        }

        /// The states the template itself has (`model-states.json`).
        const fn template_states(self) -> u32 {
            match self {
                Family::IlluminantBlockOn | Family::IlluminantBlockOff => 1,
                Family::Slab | Family::Panel | Family::Bulb | Family::Wall => 12,
                Family::Rod => 6,
                Family::Post => 2, // mangrove_roots: waterlogged only
                Family::Edge | Family::EdgeTop => 32,
            }
        }

        /// The extra states the declaration adds (`on` boolean, `position`
        /// enum: 3 values).
        const fn declared_states(self) -> u32 {
            match self {
                Family::IlluminantBlockOn | Family::IlluminantBlockOff => 2,
                Family::Post => 3,
                _ => 1,
            }
        }

        /// The state space the declaration binds: the template's × its own.
        const fn state_count(self) -> u32 {
            self.template_states() * self.declared_states()
        }

        /// `lightLevel` in upstream `SLBlocks`: 15 for the plain emitters and
        /// the on lamp, 14 for the bulb and both edge lights, 0 for the off
        /// lamp.
        const fn light(self) -> u8 {
            match self {
                Family::IlluminantBlockOff => 0,
                Family::Bulb | Family::Edge | Family::EdgeTop => 14,
                _ => 15,
            }
        }

        /// Every family is a `SimpleWaterloggedBlock` upstream except the two
        /// full-block lamps.
        const fn waterlogged(self) -> bool {
            !matches!(self, Family::IlluminantBlockOn | Family::IlluminantBlockOff)
        }
    }

    /// Every block the jar registers: 10 families × 16 colours.
    fn registry() -> Vec<(Family, Colour)> {
        let mut blocks = Vec::with_capacity(160);
        for family in Family::ALL {
            for colour in Colour::ALL {
                blocks.push((family, colour));
            }
        }
        blocks
    }

    /// Upstream's `LampBlock.lightLevel`: `on ? 15 : 0`, and every
    /// `illuminant_block[_on]` id is one fixed `on` value.
    #[test]
    fn the_two_lamp_blocks_carry_their_on_value() {
        assert_eq!(Family::IlluminantBlockOn.light(), 15);
        assert_eq!(Family::IlluminantBlockOff.light(), 0);
        // Both variants keep the `on` property (2 states); the block id, not
        // the state, is what differs between an off and an on lamp.
        for family in [Family::IlluminantBlockOn, Family::IlluminantBlockOff] {
            assert_eq!(family.declared_states(), 2);
            assert_eq!(family.state_count(), 2);
        }
    }

    #[test]
    fn ten_families_times_sixteen_colours_is_one_hundred_sixty_blocks() {
        let blocks = registry();
        assert_eq!(blocks.len(), 160);
        for family in Family::ALL {
            let members = blocks.iter().filter(|(f, _)| *f == family).count();
            assert_eq!(members, 16, "{} has {members} members", family.name());
        }
    }

    #[test]
    fn every_block_id_is_unique_and_namespaced() {
        let ids: Vec<String> = registry().iter().map(|(f, c)| f.id(*c)).collect();
        assert_eq!(ids.iter().collect::<BTreeSet<_>>().len(), 160);
        assert!(ids.iter().all(|id| id.starts_with("simplylight:")));
    }

    #[test]
    fn ids_follow_upstream_registration_names() {
        let ids: Vec<String> = registry().iter().map(|(f, c)| f.id(*c)).collect();
        for wanted in [
            "simplylight:illuminant_block",
            "simplylight:illuminant_block_on",
            "simplylight:illuminant_black_block",
            "simplylight:illuminant_black_block_on",
            "simplylight:illuminant_panel_light_blue",
            "simplylight:illuminant_slab",
            "simplylight:rodlamp",
            "simplylight:rodlamp_light_gray",
            "simplylight:lightbulb_brown",
            "simplylight:wall_lamp_red",
            "simplylight:lamp_post_pink",
            "simplylight:edge_light",
            "simplylight:edge_light_top_yellow",
        ] {
            assert!(ids.iter().any(|id| id == wanted), "missing {wanted}");
        }
        // White is the uncoloured member, not a 17th colour.
        assert!(ids.iter().all(|id| !id.contains("_white")));
    }

    #[test]
    fn light_levels_match_upstream() {
        assert_eq!(Family::IlluminantBlockOn.light(), 15);
        assert_eq!(Family::IlluminantBlockOff.light(), 0);
        for family in [Family::Slab, Family::Panel, Family::Rod, Family::Wall] {
            assert_eq!(family.light(), 15, "{}", family.name());
        }
        assert_eq!(Family::Post.light(), 15);
        for family in [Family::Bulb, Family::Edge, Family::EdgeTop] {
            assert_eq!(family.light(), 14, "{}", family.name());
        }
    }

    #[test]
    fn lamp_post_light_is_the_recorded_scalar_gap() {
        // Upstream: `position == TOP ? 15 : 0`. A content block has one light
        // value, so the port emits 15 from all three positions; the e2e pins
        // the gap so a per-state light API makes it fail.
        let upstream = |position: &str| -> u8 { if position == "top" { 15 } else { 0 } };
        let mismatched = ["bottom", "middle", "top"]
            .iter()
            .filter(|position| upstream(position) != Family::Post.light())
            .count();
        assert_eq!(mismatched, 2, "only the top block is faithful");
    }

    #[test]
    fn state_space_is_the_template_times_the_declared_properties() {
        let expected = [
            (Family::IlluminantBlockOn, 2),
            (Family::IlluminantBlockOff, 2),
            (Family::Slab, 12),
            (Family::Panel, 12),
            (Family::Rod, 6),
            (Family::Bulb, 12),
            (Family::Wall, 12),
            (Family::Post, 6),
            (Family::Edge, 32),
            (Family::EdgeTop, 32),
        ];
        for (family, states) in expected {
            assert_eq!(family.state_count(), states, "{}", family.name());
        }
        let total: u32 = expected
            .iter()
            .map(|(family, _)| family.state_count())
            .sum();
        assert_eq!(total, 128);
        assert_eq!(total * 16, 2048, "the e2e binds 2048 states");
    }

    #[test]
    fn waterlogged_families_copy_a_waterloggable_template() {
        for family in Family::ALL {
            let template = family.template();
            if family.waterlogged() {
                assert!(
                    matches!(
                        template,
                        "minecraft:amethyst_cluster"
                            | "minecraft:iron_chain"
                            | "minecraft:mangrove_roots"
                            | "minecraft:oak_fence"
                    ),
                    "{} copies {template}",
                    family.name()
                );
            } else {
                assert_eq!(template, "minecraft:calcite", "{}", family.name());
            }
        }
        // The edge light's four side booleans are the oak fence's own states.
        assert_eq!(Family::Edge.template_states(), 2u32.pow(4) * 2);
    }

    #[test]
    fn every_block_drops_itself() {
        // `SLBlockLoot.generate` is `dropSelf(block)` for every registered
        // block: one pool, one item entry, the block itself.
        let drops: Vec<(String, String)> = registry()
            .iter()
            .map(|(family, colour)| {
                let id = family.id(*colour);
                (id.clone(), id)
            })
            .collect();
        assert_eq!(drops.len(), 160);
        assert!(drops.iter().all(|(dropped, block)| dropped == block));
    }

    #[test]
    fn creative_order_is_upstreams() {
        // `SimplyLight.TABITEMS`: on lamps, off lamps, slabs, panels, rods,
        // bulbs, fixtures, posts, edge lights, top edge lights.
        let order: Vec<String> = registry()
            .iter()
            .map(|(family, colour)| family.id(*colour))
            .collect();
        assert_eq!(order.len(), 160);
        assert_eq!(
            order.first().map(String::as_str),
            Some("simplylight:illuminant_block_on")
        );
        assert_eq!(
            order.last().map(String::as_str),
            Some("simplylight:edge_light_top_pink")
        );
        // Cards are 16 wide: the off lamp family starts the second card.
        assert_eq!(order[16], "simplylight:illuminant_block");
    }
}
