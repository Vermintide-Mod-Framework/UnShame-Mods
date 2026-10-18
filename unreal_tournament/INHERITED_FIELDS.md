# What the finished weapons still inherit from their base weapons

Made with the extras mod's `/ut_inherited` in the game (build 1282): each finished weapon's template compared with the template
of the game weapon it is a copy of. A part that the mod sets to the same value as the base's is listed too, because the
comparison can't tell the two apart. A sub-action the base has none of by its name (made from a copy of one of the base's) is
compared with the base's sub-action it shares the most with. The actions' lookup_data is left out. The damage profiles are
not here: they are made with `utils.add_damage_profile`, with nothing from the game's.

The groups are by field name. The numbers in brackets are how many parts of that field are the base's.

## What stands out

- The Shield Gun is five copies of five melee weapons, and each keeps its base's `dodge_count` (2 or 3), `weapon_type` (SWORD_2H,
  MACE_2H, AXE_2H, POLEARM), `buffs`, its push (`action_one.push`, all of it: timing, reach, angles and movement while pushing) and its
  block (`action_two.default`). So the same weapon dodges, pushes and blocks differently for each hero.
- Every weapon keeps its base's `weapon_type` and `buff_type`, which the game's talents, traits and properties go by (a weapon type's
  own bonuses, and "ranged" or "melee" ones). The Bio Rifle is a BRACE_OF_PISTOLS to them, the Shock Rifle a FIRE_STAFF, the Lightning
  Gun a LIFE_STAFF.
- Every weapon keeps its base's bot settings (`attack_meta_data`) apart from what was changed: where bots aim, what they use it against,
  and whether they shoot past allies and enemies in the way. The Minigun's bots, with the repeater's, don't shoot past an ally.
- The Minigun's rounds keep the repeater's action settings that are not damage: `headshot_multiplier` 2 (which the game doesn't use for
  damage), `charge_value` "bullet_hit" (what talents take a hit for), the action's `critical_strike` (the chance), `alert_sound_range_*`,
  `aim_assist_*`, and the recoil's functions. Its reload actions are the repeater's, though it never reloads.
- The Shock Rifle and the Lightning Gun keep the staves' `overcharge_data` whole, and `default_spread_template` "spear".
- The Flak Cannon, the Shield Gun and the Minigun keep the game's own hit effects and impact sounds (`hit_effect`, `impact_sound_event`),
  which the UT effects are drawn on top of.

## Summary

| Weapon | Base | Gameplay | Tied to the base's animations, models or career skills | The game's own hit effects and sounds | Menus and tooltips | Unclear |
|---|---|---|---|---|---|---|
| bio_rifle | dr_steam_pistol (`heavy_steam_pistol_template_1`) | 59 | 20 | 0 | 2 | 1 |
| flak_cannon | es_blunderbuss (`blunderbuss_template_1`) | 53 | 14 | 11 | 7 | 1 |
| lightning_gun | we_life_staff (`staff_life`) | 32 | 13 | 0 | 7 | 1 |
| minigun | es_repeating_handgun (`repeating_handgun_template_1`) | 93 | 16 | 6 | 8 | 1 |
| minigun_wh | wh_repeating_pistols (`repeating_pistol_template_1`) | 74 | 12 | 3 | 4 | 1 |
| rocket_launcher | wh_crossbow_repeater (`repeating_crossbow_template_1`) | 95 | 34 | 3 | 5 | 5 |
| shield_gun | es_bastard_sword (`bastard_sword_template`) | 99 | 41 | 12 | 7 | 5 |
| shield_gun_bw | bw_ghost_scythe (`staff_scythe`) | 73 | 21 | 3 | 5 | 8 |
| shield_gun_dr | dr_2h_cog_hammer (`two_handed_cog_hammers_template_1`) | 100 | 40 | 12 | 7 | 4 |
| shield_gun_we | we_spear (`two_handed_spears_elf_template_1`) | 90 | 40 | 12 | 7 | 7 |
| shield_gun_wh | wh_2h_billhook (`two_handed_billhooks_template`) | 70 | 24 | 3 | 6 | 2 |
| shock_rifle | bw_skullstaff_beam (`staff_blast_beam_template_1`) | 29 | 12 | 0 | 5 | 1 |

## bio_rifle

`ut_bio_rifle_template`, a copy of `dr_steam_pistol` (`heavy_steam_pistol_template_1`).

New sub-actions: `action_one.shoot_charged` (like the base's action_one.shoot); `action_one.ut_bio_child` (like the base's action_career_dr_3.default).

**Gameplay: should be set explicitly**

- `aim_assist_settings` (all of it)
- `ammo_data.ammo_hand` = "right"
- `ammo_data.reload_on_ammo_pickup` = false
- `attack_meta_data.aim_at_node` = "j_spine1"
- `attack_meta_data.aim_data` (all of it)
- `attack_meta_data.aim_data_charged` (all of it)
- `attack_meta_data.effective_against` = 84
- `attack_meta_data.effective_against_charged` = 0
- `attack_meta_data.effective_against_combined` = 84
- `attack_meta_data.fire_input` = "fire_hold"
- `attack_meta_data.hold_fire_condition` = [function]
- `attack_meta_data.ignore_enemies_for_obstruction` = true
- `buff_type` = "RANGED"
- `buffs` (all of it)
- `crosshair_style` = "default"
- `dodge_count` = 100
- `spread_lerp_speed` = 5
- `weapon_type` = "BRACE_OF_PISTOLS"
- `action_one.fast_shot` (all of it)
- `action_one.shoot` (all of it)
- `weapon_reload.auto_reload_on_empty` (all of it)
- `weapon_reload.default` (all of it)
- `action_one.default`: allowed_chain_actions (8), ammo_usage, fire_time, projectile_info (3)
- `action_one.shoot_charged`: alert_sound_range_fire, alert_sound_range_hit, allowed_chain_actions (7), apply_recoil, fire_time, projectile_info (3), recoil_settings (5)
- `action_one.ut_bio_child`: allowed_chain_actions
- `action_two.default`: allowed_chain_actions (2), hold_input, total_time

**Tied to the base's animations, models or career skills: stays**

- `display_unit` = "units/weapons/weapon_display/display_1h_grudge_raker"
- `gui_texture` = "hud_weapon_icon_repeating_handgun"
- `jump_anim_enabled_1p` = true
- `no_ammo_reload_event` = "reload"
- `reload_event` = "reload"
- `required_projectile_unit_templates.bullet_temp` = false
- `right_hand_attachment_node_linking` (all of it)
- `right_hand_unit` = ""
- `state_machine` = "units/beings/player/first_person_base/state_machines/ranged/steam_pistol"
- `wield_anim` = "to_steam_pistol"
- `wield_anim_career` (all of it)
- `wield_anim_no_ammo` = "to_steam_pistol_noammo"
- `wield_anim_no_ammo_career` (all of it)
- `wwise_dep_left_hand` (all of it)
- `wwise_dep_right_hand` (all of it)
- `action_career_dr_3.default` (all of it)
- `action_career_dr_4.default` (all of it)
- `action_inspect.action_inspect_hold` (all of it)
- `action_inspect.default` (all of it)
- `action_one.shoot_charged`: anim_event

**Menus and tooltips**

- `tooltip_compare` (all of it)
- `tooltip_detail` (all of it)

**Unclear**

- `action_wield.default` (all of it)

## flak_cannon

`ut_flak_cannon_template`, a copy of `es_blunderbuss` (`blunderbuss_template_1`).

New sub-actions: `action_one.ut_flak_burst_0` (like the base's action_one.default); `action_one.ut_flak_burst_1` (like the base's action_one.default); `action_one.ut_flak_burst_2` (like the base's action_one.default); `action_one.ut_flak_burst_3` (like the base's action_one.default); `action_one.ut_flak_burst_4` (like the base's action_one.default); `action_one.ut_flak_chunk_0` (like the base's action_one.default); `action_one.ut_flak_chunk_1` (like the base's action_one.default); `action_one.ut_flak_chunk_2` (like the base's action_one.default); `action_one.ut_flak_chunk_3` (like the base's action_one.default); `action_one.ut_flak_chunk_4` (like the base's action_one.default); `action_two.ut_flak_shell` (like none of the base's).

**Gameplay: should be set explicitly**

- `ammo_data.ammo_hand` = "right"
- `ammo_data.play_reload_anim_on_wield_reload` = true
- `ammo_data.reload_on_ammo_pickup` = true
- `ammo_data.should_update_anim_ammo` = true
- `attack_meta_data.aim_at_node` = "j_spine"
- `attack_meta_data.effective_against_charged` = 0
- `attack_meta_data.ignore_enemies_for_obstruction` = true
- `attack_meta_data.max_range` = 15
- `buff_type` = "RANGED"
- `buffs` (all of it)
- `crosshair_style` = "shotgun"
- `default_spread_template` = "blunderbuss"
- `dodge_count` = 3
- `fire_at_gaze_setting` = "tobii_fire_at_gaze_blunderbuss"
- `weapon_type` = "SHOTGUN"
- `weapon_reload.auto_reload_on_empty` (all of it)
- `weapon_reload.default` (all of it)
- `action_one.default`: active_reload_time, alert_sound_range_fire, alert_sound_range_hit, allowed_chain_actions (7), ammo_usage, apply_recoil, bullseye, charge_value, damage_profile, damage_window_end, damage_window_start, fire_at_gaze_setting, fire_time, hit_mass_count, kind, num_layers_spread, range, recoil_settings, reload_when_out_of_ammo
- `action_two.default`: allowed_chain_actions (10), reload_when_out_of_ammo

**Tied to the base's animations, models or career skills: stays**

- `display_unit` = "units/weapons/weapon_display/display_blunderbusses"
- `reload_event` = "reload"
- `right_hand_attachment_node_linking` (all of it)
- `right_hand_unit` = ""
- `state_machine` = "units/beings/player/first_person_base/state_machines/ranged/blunderbuss"
- `wield_anim` = "to_blunderbuss"
- `wield_anim_no_ammo` = "to_blunderbuss_noammo"
- `wwise_dep_right_hand` (all of it)
- `action_career_es_4.default` (all of it)
- `action_inspect.action_inspect_hold` (all of it)
- `action_inspect.default` (all of it)
- `action_one.default`: anim_event, anim_event_last_ammo, anim_event_secondary

**The game's own hit effects and sounds**

- `action_one.default`: hit_effect
- `action_one.ut_flak_burst_0`: hit_effect
- `action_one.ut_flak_burst_1`: hit_effect
- `action_one.ut_flak_burst_2`: hit_effect
- `action_one.ut_flak_burst_3`: hit_effect
- `action_one.ut_flak_burst_4`: hit_effect
- `action_one.ut_flak_chunk_0`: hit_effect
- `action_one.ut_flak_chunk_1`: hit_effect
- `action_one.ut_flak_chunk_2`: hit_effect
- `action_one.ut_flak_chunk_3`: hit_effect
- `action_one.ut_flak_chunk_4`: hit_effect

**Menus and tooltips**

- `tooltip_compare` (all of it)
- `tooltip_detail` (all of it)
- `tooltip_keywords.1` = "weapon_keyword_high_damage"
- `tooltip_keywords.2` = "weapon_keyword_crowd_control"
- `weapon_diagram.heavy_attack.2` = 7
- `weapon_diagram.heavy_attack.3` = 3
- `weapon_diagram.light_attack.4` = 4

**Unclear**

- `action_wield.default` (all of it)

## lightning_gun

`ut_lightning_gun_template`, a copy of `we_life_staff` (`staff_life`).

**Gameplay: should be set explicitly**

- `aim_assist_settings` (all of it)
- `attack_meta_data.aim_at_node` = "j_head"
- `attack_meta_data.aim_at_node_charged` = "j_spine1"
- `attack_meta_data.aim_data` (all of it)
- `attack_meta_data.aim_data_charged` (all of it)
- `attack_meta_data.charge_when_obstructed` = true
- `attack_meta_data.charge_when_outside_max_range_charged` = false
- `attack_meta_data.effective_against` = 21
- `attack_meta_data.effective_against_charged` = 114
- `attack_meta_data.effective_against_combined` = 119
- `attack_meta_data.ignore_disabled_enemies_charged` = true
- `attack_meta_data.ignore_enemies_for_obstruction` = false
- `attack_meta_data.ignore_enemies_for_obstruction_charged` = true
- `attack_meta_data.ignore_hitting_allies_charged` = true
- `attack_meta_data.max_range_charged` = 50
- `attack_meta_data.obstruction_fuzzyness_range` = 1
- `attack_meta_data.obstruction_fuzzyness_range_charged` = 6
- `buff_type` = "RANGED"
- `buffs` (all of it)
- `default_spread_template` = "spear"
- `overcharge_data` (all of it)
- `weapon_type` = "LIFE_STAFF"
- `weapon_reload.default` (all of it)
- `action_one.default`: allowed_chain_actions (3), apply_recoil, ranged_attack, recoil_settings (3), reload_when_out_of_ammo

**Tied to the base's animations, models or career skills: stays**

- `display_unit` = "units/weapons/weapon_display/display_staff"
- `jump_anim_enabled_1p` = true
- `left_hand_attachment_node_linking` (all of it)
- `required_projectile_unit_templates` (all of it)
- `state_machine` = "units/beings/player/first_person_base/state_machines/ranged/life_staff"
- `wield_anim` = "to_life_staff"
- `action_career_we_3.default` (all of it)
- `action_career_we_3_piercing.default` (all of it)
- `action_career_we_thornsister.default` (all of it)
- `action_inspect.action_inspect_hold` (all of it)
- `action_inspect.default` (all of it)
- `action_one.default`: anim_event, weapon_action_hand

**Menus and tooltips**

- `tooltip_compare.heavy.action_name` = "action_one"
- `tooltip_compare.light` (all of it)
- `tooltip_detail.heavy.action_name` = "action_one"
- `tooltip_detail.light` (all of it)
- `weapon_diagram.heavy_attack.1` = 0
- `weapon_diagram.heavy_attack.2` = 0
- `weapon_diagram.heavy_attack.5` = 0

**Unclear**

- `action_wield.default` (all of it)

## minigun

`ut_minigun_template`, a copy of `es_repeating_handgun` (`repeating_handgun_template_1`).

New sub-actions: `action_one.loop` (like the base's action_one.bullet_spray); `action_two.loop` (like the base's action_one.bullet_spray).

**Gameplay: should be set explicitly**

- `aim_assist_settings` (all of it)
- `ammo_data.ammo_hand` = "right"
- `ammo_data.play_reload_anim_on_wield_reload` = true
- `ammo_data.reload_on_ammo_pickup` = true
- `attack_meta_data.aim_at_node` = "j_neck"
- `attack_meta_data.can_charge_shot` = false
- `attack_meta_data.effective_against` = 84
- `attack_meta_data.effective_against_charged` = 0
- `attack_meta_data.effective_against_combined` = 84
- `buff_type` = "RANGED"
- `buffs` (all of it)
- `crosshair_style` = "default"
- `default_spread_template` = "repeating_handgun"
- `dodge_count` = 1
- `spread_lerp_speed` = 12
- `weapon_type` = "REPEATING_HANDGUN"
- `weapon_reload.auto_reload_on_empty` (all of it)
- `weapon_reload.default` (all of it)
- `action_one.default`: additional_critical_strike_chance, aim_assist_auto_hit_chance, aim_assist_max_ramp_multiplier, aim_assist_ramp_decay_delay, aim_assist_ramp_multiplier, alert_sound_range_fire, alert_sound_range_hit, allowed_chain_actions (4), ammo_usage, apply_recoil, charge_value, critical_strike, damage_window_end, damage_window_start, headshot_multiplier, kind, recoil_settings (3), reload_time
- `action_one.loop`: additional_critical_strike_chance, aim_assist_auto_hit_chance, aim_assist_max_ramp_multiplier, aim_assist_ramp_decay_delay, aim_assist_ramp_multiplier, alert_sound_range_fire, alert_sound_range_hit, allowed_chain_actions (5), ammo_usage, apply_recoil, charge_value, critical_strike, damage_window_end, damage_window_start, fire_time, headshot_multiplier, kind, recoil_settings (3), reload_time
- `action_two.default`: allowed_chain_actions.1, hold_input
- `action_two.loop`: additional_critical_strike_chance, aim_assist_auto_hit_chance, aim_assist_max_ramp_multiplier, aim_assist_ramp_decay_delay, aim_assist_ramp_multiplier, alert_sound_range_fire, alert_sound_range_hit, allowed_chain_actions (4), ammo_usage, apply_recoil, charge_value, critical_strike, damage_window_end, damage_window_start, fire_time, headshot_multiplier, hold_input, kind, recoil_settings (3), reload_time

**Tied to the base's animations, models or career skills: stays**

- `display_unit` = "units/weapons/weapon_display/display_repeating_handguns"
- `reload_event` = "reload"
- `required_projectile_unit_templates` (all of it)
- `right_hand_attachment_node_linking` (all of it)
- `right_hand_unit` = ""
- `state_machine` = "units/beings/player/first_person_base/state_machines/ranged/repeating_handgun"
- `wield_anim` = "to_repeating_handgun"
- `wield_anim_no_ammo` = "to_repeating_handgun_noammo"
- `wwise_dep_right_hand` (all of it)
- `action_career_es_4.default` (all of it)
- `action_inspect.action_inspect_hold` (all of it)
- `action_inspect.default` (all of it)
- `action_one.loop`: anim_event, anim_event_last_ammo
- `action_two.loop`: anim_event, anim_event_last_ammo

**The game's own hit effects and sounds**

- `action_one.default`: critical_hit_effect, hit_effect
- `action_one.loop`: critical_hit_effect, hit_effect
- `action_two.loop`: critical_hit_effect, hit_effect

**Menus and tooltips**

- `tooltip_compare.light.action_name` = "action_one"
- `tooltip_detail.light.action_name` = "action_one"
- `weapon_diagram.heavy_attack.2` = 1
- `weapon_diagram.heavy_attack.4` = 3
- `weapon_diagram.heavy_attack.5` = 5
- `weapon_diagram.light_attack.2` = 1
- `weapon_diagram.light_attack.4` = 3
- `weapon_diagram.light_attack.5` = 5

**Unclear**

- `action_wield.default` (all of it)

## minigun_wh

`ut_minigun_wh_template`, a copy of `wh_repeating_pistols` (`repeating_pistol_template_1`).

New sub-actions: `action_one.loop` (like the base's action_one.default); `action_two.loop` (like the base's action_one.default).

**Gameplay: should be set explicitly**

- `aim_assist_settings` (all of it)
- `ammo_data.ammo_hand` = "right"
- `ammo_data.play_reload_anim_on_wield_reload` = true
- `ammo_data.reload_on_ammo_pickup` = true
- `ammo_data.should_update_anim_ammo` = true
- `attack_meta_data.aim_at_node` = "j_neck"
- `attack_meta_data.can_charge_shot` = false
- `attack_meta_data.effective_against` = 84
- `attack_meta_data.effective_against_charged` = 0
- `attack_meta_data.effective_against_combined` = 84
- `buff_type` = "RANGED"
- `buffs` (all of it)
- `crosshair_style` = "default"
- `default_spread_template` = "repeating_pistol"
- `dodge_count` = 3
- `fire_at_gaze_setting` = "tobii_fire_at_gaze_repeating_pistol"
- `spread_lerp_speed` = 5
- `weapon_type` = "REPEATING_PISTOL"
- `weapon_reload.auto_reload_on_empty` (all of it)
- `weapon_reload.default` (all of it)
- `action_one.default`: aim_assist_auto_hit_chance, alert_sound_range_fire, alert_sound_range_hit, allowed_chain_actions (4), ammo_usage, apply_recoil, charge_value, damage_window_end, damage_window_start, headshot_multiplier, kind, recoil_settings (3)
- `action_one.loop`: aim_assist_auto_hit_chance, alert_sound_range_fire, alert_sound_range_hit, allowed_chain_actions (4), ammo_usage, apply_recoil, charge_value, damage_window_end, damage_window_start, fire_time, headshot_multiplier, kind, recoil_settings (3)
- `action_two.default`: allowed_chain_actions.1, hold_input
- `action_two.loop`: aim_assist_auto_hit_chance, alert_sound_range_fire, alert_sound_range_hit, allowed_chain_actions (3), ammo_usage, apply_recoil, charge_value, damage_window_end, damage_window_start, fire_time, headshot_multiplier, kind, recoil_settings (3)

**Tied to the base's animations, models or career skills: stays**

- `display_unit` = "units/weapons/weapon_display/display_repeating_pistols"
- `reload_event` = "reload"
- `required_projectile_unit_templates` (all of it)
- `right_hand_attachment_node_linking` (all of it)
- `right_hand_unit` = "units/weapons/player/wpn_emp_pistol_01_t1/wpn_emp_pistol_01_t1"
- `state_machine` = "units/beings/player/first_person_base/state_machines/ranged/repeater_pistol"
- `wield_anim` = "to_repeater_pistol"
- `wwise_dep_right_hand` (all of it)
- `action_career_wh_2.default` (all of it)
- `action_career_wh_priest.default` (all of it)
- `action_inspect.action_inspect_hold` (all of it)
- `action_inspect.default` (all of it)

**The game's own hit effects and sounds**

- `action_one.default`: hit_effect
- `action_one.loop`: hit_effect
- `action_two.loop`: hit_effect

**Menus and tooltips**

- `tooltip_compare.light.action_name` = "action_one"
- `tooltip_detail.heavy.action_name` = "action_two"
- `tooltip_detail.light.action_name` = "action_one"
- `weapon_diagram.light_attack.3` = 7

**Unclear**

- `action_wield.default` (all of it)

## rocket_launcher

`ut_rocket_launcher_template`, a copy of `wh_crossbow_repeater` (`repeating_crossbow_template_1`).

New sub-actions: `action_one.zoomed_shot_spiral` (like the base's action_one.zoomed_shot).

**Gameplay: should be set explicitly**

- `ammo_data.ammo_hand` = "left"
- `ammo_data.ammo_unit_attachment_node_linking` (all of it)
- `ammo_data.destroy_when_out_of_ammo` = false
- `ammo_data.play_reload_anim_on_wield_reload` = true
- `ammo_data.reload_on_ammo_pickup` = false
- `attack_meta_data.aim_at_node` = "j_spine1"
- `attack_meta_data.aim_at_node_charged` = "j_head"
- `attack_meta_data.charge_above_range` = 10
- `attack_meta_data.charge_when_obstructed` = false
- `attack_meta_data.charged_attack_action_name` = "zoomed_shot"
- `attack_meta_data.effective_against` = 84
- `attack_meta_data.effective_against_charged` = 0
- `attack_meta_data.effective_against_combined` = 84
- `attack_meta_data.ignore_enemies_for_obstruction` = false
- `attack_meta_data.ignore_enemies_for_obstruction_charged` = true
- `attack_meta_data.minimum_charge_time` = 0.45000000000000001
- `buff_type` = "RANGED"
- `buffs` (all of it)
- `crosshair_style` = "projectile"
- `dodge_count` = 3
- `spread_lerp_speed` = 2
- `weapon_type` = "REPEATING_CROSSBOW"
- `weapon_reload.auto_reload_on_empty` (all of it)
- `weapon_reload.default` (all of it)
- `action_one.default`: alert_sound_range_fire, alert_sound_range_hit, allowed_chain_actions (8), ammo_usage, apply_recoil, charge_value, cleave_distribution, kind, projectile_info (6), recoil_settings, reload_when_out_of_ammo
- `action_one.zoomed_shot`: alert_sound_range_fire, alert_sound_range_hit, allowed_chain_actions.1, ammo_usage, apply_recoil, charge_value, cleave_distribution, kind, num_projectiles, projectile_info (6), recoil_settings, reload_when_out_of_ammo
- `action_one.zoomed_shot_spiral`: alert_sound_range_fire, alert_sound_range_hit, allowed_chain_actions.1, ammo_usage, apply_recoil, charge_value, cleave_distribution, kind, num_projectiles, projectile_info (6), recoil_settings, reload_when_out_of_ammo
- `action_two.default`: aim_at_gaze_setting, aim_sound_delay, allowed_chain_actions (3), ammo_requirement, can_abort_reload, cooldown, default_zoom, hold_input, kind, minimum_hold_time, total_time, unzoom_condition_function

**Tied to the base's animations, models or career skills: stays**

- `display_unit` = "units/weapons/weapon_display/display_1h_crossbow"
- `left_hand_attachment_node_linking` (all of it)
- `left_hand_unit` = ""
- `reload_event` = "reload"
- `required_projectile_unit_templates` (all of it)
- `state_machine` = "units/beings/player/first_person_base/state_machines/ranged/repeating_crossbow"
- `wield_anim` = "to_repeating_crossbow"
- `wield_anim_no_ammo` = "to_repeating_crossbow_noammo"
- `wield_anim_not_loaded` = "to_repeating_crossbow"
- `wwise_dep_left_hand` (all of it)
- `action_career_wh_2.default` (all of it)
- `action_career_wh_priest.default` (all of it)
- `action_inspect.action_inspect_hold` (all of it)
- `action_inspect.default` (all of it)
- `action_one.default`: anim_event, anim_event_last_ammo, anim_event_no_ammo_left, weapon_action_hand
- `action_one.zoomed_shot`: anim_end_event, anim_end_event_condition_func, anim_event, anim_event_last_ammo, anim_event_no_ammo_left, weapon_action_hand
- `action_one.zoomed_shot_spiral`: anim_end_event, anim_end_event_condition_func, anim_event, anim_event_last_ammo, anim_event_no_ammo_left, weapon_action_hand
- `action_two.default`: anim_end_event, anim_end_event_condition_func, anim_event, weapon_action_hand

**The game's own hit effects and sounds**

- `action_one.default`: hit_effect
- `action_one.zoomed_shot`: hit_effect
- `action_one.zoomed_shot_spiral`: hit_effect

**Menus and tooltips**

- `tooltip_compare` (all of it)
- `tooltip_detail` (all of it)
- `tooltip_keywords.1` = "weapon_keyword_high_damage"
- `weapon_diagram.heavy_attack.2` = 7
- `weapon_diagram.heavy_attack.3` = 1

**Unclear**

- `action_wield.default` (all of it)
- `action_one.default`: enter_function
- `action_one.zoomed_shot`: enter_function
- `action_one.zoomed_shot_spiral`: enter_function
- `action_two.default`: enter_function

## shield_gun

`ut_shield_gun_template`, a copy of `es_bastard_sword` (`bastard_sword_template`).

New sub-actions: `action_one.bash` (like the base's action_one.heavy_attack_left); `action_one.punch` (like the base's action_one.heavy_attack_left); `action_one.punch_auto` (like the base's action_one.heavy_attack_left).

**Gameplay: should be set explicitly**

- `aim_assist_settings` (all of it)
- `attack_meta_data.hold_attack.arc` = 2
- `attack_meta_data.tap_attack.arc` = 1
- `buff_type` = "MELEE_2H"
- `buffs` (all of it)
- `crosshair_style` = "dot"
- `dodge_count` = 3
- `max_fatigue_points` = 6
- `outer_block_angle` = 360
- `outer_block_fatigue_point_multiplier` = 2
- `weapon_type` = "SWORD_2H"
- `action_two.default` (all of it)
- `action_one.bash`: additional_critical_strike_chance, allowed_chain_actions (7), buff_data, damage_profile, dedicated_target_range, hit_mass_count, range_mod, slide_armour_hit, sweep_z_offset, uninterruptible, use_precision_sweep
- `action_one.default`: aim_assist_max_ramp_multiplier, aim_assist_ramp_multiplier, allowed_chain_actions (6), attack_hold_input, blocking_charge_start_time, stop_action_on_leave_for_bot, total_time, weapon_sway_settings
- `action_one.punch`: additional_critical_strike_chance, allowed_chain_actions (7), buff_data, damage_profile, dedicated_target_range, hit_mass_count, range_mod, slide_armour_hit, sweep_z_offset, uninterruptible, use_precision_sweep
- `action_one.punch_auto`: additional_critical_strike_chance, allowed_chain_actions (7), buff_data, damage_profile, dedicated_target_range, hit_mass_count, range_mod, slide_armour_hit, sweep_z_offset, uninterruptible, use_precision_sweep
- `action_one.push`: allowed_chain_actions (10), buff_data, chain_condition_func, charge_value, damage_profile_inner, damage_profile_outer, damage_window_end, damage_window_start, dedicated_target_range, kind, outer_push_angle, push_angle, push_radius, total_time

**Tied to the base's animations, models or career skills: stays**

- `display_unit` = "units/weapons/weapon_display/display_2h_swords"
- `required_projectile_unit_templates` (all of it)
- `right_hand_attachment_node_linking` (all of it)
- `right_hand_unit` = "units/weapons/player/wpn_greatsword/wpn_greatsword"
- `state_machine` = "units/beings/player/first_person_base/state_machines/melee/bastard_sword"
- `wield_anim` = "to_bastard_sword"
- `wwise_dep_right_hand` (all of it)
- `action_career_es_4.default` (all of it)
- `action_inspect.action_inspect_hold` (all of it)
- `action_inspect.default` (all of it)
- `action_one.bash`: anim_end_event, anim_end_event_condition_func, anim_event, anim_time_scale, baked_sweep, first_person_hit_anim, hit_shield_stop_anim, hit_stop_anim
- `action_one.default`: anim_end_event, anim_end_event_condition_func, anim_event
- `action_one.punch`: anim_end_event, anim_end_event_condition_func, anim_event, anim_time_scale, baked_sweep, first_person_hit_anim, hit_shield_stop_anim, hit_stop_anim
- `action_one.punch_auto`: anim_end_event, anim_end_event_condition_func, anim_event, anim_time_scale, baked_sweep, first_person_hit_anim, hit_shield_stop_anim, hit_stop_anim
- `action_one.push`: anim_end_event, anim_end_event_condition_func, anim_event, weapon_action_hand

**The game's own hit effects and sounds**

- `action_one.bash`: hit_effect, impact_sound_event, no_damage_impact_sound_event
- `action_one.punch`: hit_effect, impact_sound_event, no_damage_impact_sound_event
- `action_one.punch_auto`: hit_effect, impact_sound_event, no_damage_impact_sound_event
- `action_one.push`: hit_effect, impact_sound_event, no_damage_impact_sound_event

**Menus and tooltips**

- `tooltip_compare.heavy.action_name` = "action_one"
- `tooltip_compare.light.action_name` = "action_one"
- `tooltip_detail.heavy.action_name` = "action_one"
- `tooltip_detail.light.action_name` = "action_one"
- `tooltip_keywords.1` = "weapon_keyword_high_damage"
- `weapon_diagram.heavy_attack.2` = 4
- `weapon_diagram.light_attack.3` = 3

**Unclear**

- `action_wield.default` (all of it)
- `action_one.bash`: enter_function
- `action_one.punch`: enter_function
- `action_one.punch_auto`: enter_function
- `action_one.push`: enter_function

## shield_gun_bw

`ut_shield_gun_bw_template`, a copy of `bw_ghost_scythe` (`staff_scythe`).

New sub-actions: `action_one.bash` (like the base's action_one.default); `action_one.punch` (like the base's action_one.default); `action_one.punch_auto` (like the base's action_one.default).

**Gameplay: should be set explicitly**

- `aim_assist_settings` (all of it)
- `attack_meta_data.hold_attack.arc` = 2
- `buff_type` = "MELEE_2H"
- `buffs` (all of it)
- `crosshair_style` = "dot"
- `dodge_count` = 2
- `max_fatigue_points` = 6
- `outer_block_angle` = 360
- `outer_block_fatigue_point_multiplier` = 2
- `weapon_type` = "MACE_2H"
- `action_three.default` (all of it)
- `action_three.special_action_attack` (all of it)
- `action_two.default` (all of it)
- `action_one.bash`: allowed_chain_actions (6), attack_hold_input, buff_data
- `action_one.default`: allowed_chain_actions (9), attack_hold_input, total_time
- `action_one.punch`: allowed_chain_actions (7), attack_hold_input, buff_data
- `action_one.punch_auto`: allowed_chain_actions (7), attack_hold_input, buff_data
- `action_one.push`: allowed_chain_actions (11), buff_data, chain_condition_func, damage_profile_inner, damage_profile_outer, damage_window_end, damage_window_start, dedicated_target_range, kind, outer_push_angle, push_angle, push_radius, total_time

**Tied to the base's animations, models or career skills: stays**

- `display_unit` = "units/weapons/weapon_display/display_2h_hammers"
- `required_projectile_unit_templates` (all of it)
- `right_hand_attachment_node_linking` (all of it)
- `right_hand_unit` = "units/weapons/player/wpn_empire_short_sword/wpn_empire_short_sword"
- `state_machine` = "units/beings/player/first_person_base/state_machines/melee/ghost_scythe"
- `wield_anim` = "to_quarter_staff_wield"
- `wwise_dep_right_hand` (all of it)
- `action_career_bw_1.default` (all of it)
- `action_career_bw_necromancer.default` (all of it)
- `action_inspect.action_inspect_hold` (all of it)
- `action_inspect.default` (all of it)
- `action_one.bash`: anim_end_event_condition_func
- `action_one.default`: anim_end_event, anim_end_event_condition_func, anim_event
- `action_one.punch`: anim_end_event_condition_func
- `action_one.punch_auto`: anim_end_event_condition_func
- `action_one.push`: anim_end_event, anim_end_event_condition_func, anim_event, weapon_action_hand

**The game's own hit effects and sounds**

- `action_one.push`: hit_effect, impact_sound_event, no_damage_impact_sound_event

**Menus and tooltips**

- `tooltip_compare.heavy.action_name` = "action_one"
- `tooltip_compare.light.action_name` = "action_one"
- `tooltip_detail.heavy.action_name` = "action_one"
- `tooltip_detail.light.action_name` = "action_one"
- `weapon_diagram.light_attack.2` = 3

**Unclear**

- `custom_data` (all of it)
- `on_wield` = [function]
- `update` = [function]
- `action_wield.default` (all of it)
- `action_one.bash`: enter_function
- `action_one.default`: enter_function
- `action_one.punch`: enter_function
- `action_one.punch_auto`: enter_function

## shield_gun_dr

`ut_shield_gun_dr_template`, a copy of `dr_2h_cog_hammer` (`two_handed_cog_hammers_template_1`).

New sub-actions: `action_one.bash` (like the base's action_one.heavy_attack_left); `action_one.punch` (like the base's action_one.heavy_attack_left); `action_one.punch_auto` (like the base's action_one.heavy_attack_left).

**Gameplay: should be set explicitly**

- `aim_assist_settings` (all of it)
- `buff_type` = "MELEE_2H"
- `buffs` (all of it)
- `crosshair_style` = "dot"
- `dodge_count` = 2
- `max_fatigue_points` = 6
- `outer_block_angle` = 360
- `outer_block_fatigue_point_multiplier` = 2
- `weapon_type` = "AXE_2H"
- `action_two.default` (all of it)
- `action_one.bash`: allowed_chain_actions (10), buff_data, charge_value, damage_profile, dedicated_target_range, range_mod, uninterruptible, use_precision_sweep, width_mod
- `action_one.default`: aim_assist_max_ramp_multiplier, aim_assist_ramp_decay_delay, aim_assist_ramp_multiplier, allowed_chain_actions (6), attack_hold_input, total_time
- `action_one.punch`: allowed_chain_actions (11), buff_data, charge_value, damage_profile, dedicated_target_range, range_mod, uninterruptible, use_precision_sweep, width_mod
- `action_one.punch_auto`: allowed_chain_actions (11), buff_data, charge_value, damage_profile, dedicated_target_range, range_mod, uninterruptible, use_precision_sweep, width_mod
- `action_one.push`: allowed_chain_actions (10), buff_data, chain_condition_func, charge_value, damage_profile_inner, damage_profile_outer, damage_window_end, damage_window_start, dedicated_target_range, kind, outer_push_angle, push_angle, push_radius, total_time

**Tied to the base's animations, models or career skills: stays**

- `display_unit` = "units/weapons/weapon_display/display_2h_axes"
- `required_projectile_unit_templates` (all of it)
- `right_hand_attachment_node_linking` (all of it)
- `right_hand_unit` = "units/weapons/player/wpn_empire_short_sword/wpn_empire_short_sword"
- `state_machine` = "units/beings/player/first_person_base/state_machines/melee/cog_hammer"
- `wield_anim` = "to_cog_hammer"
- `wwise_dep_left_hand` (all of it)
- `wwise_dep_right_hand` (all of it)
- `action_career_dr_3.default` (all of it)
- `action_career_dr_4.default` (all of it)
- `action_inspect.action_inspect_hold` (all of it)
- `action_inspect.default` (all of it)
- `action_one.bash`: anim_end_event, anim_end_event_condition_func, anim_event, anim_time_scale, baked_sweep, first_person_hit_anim, hit_stop_anim
- `action_one.default`: anim_end_event, anim_end_event_condition_func, anim_event
- `action_one.punch`: anim_end_event, anim_end_event_condition_func, anim_event, anim_time_scale, baked_sweep, first_person_hit_anim, hit_stop_anim
- `action_one.punch_auto`: anim_end_event, anim_end_event_condition_func, anim_event, anim_time_scale, baked_sweep, first_person_hit_anim, hit_stop_anim
- `action_one.push`: anim_end_event, anim_end_event_condition_func, anim_event, weapon_action_hand

**The game's own hit effects and sounds**

- `action_one.bash`: hit_effect, impact_sound_event, no_damage_impact_sound_event
- `action_one.punch`: hit_effect, impact_sound_event, no_damage_impact_sound_event
- `action_one.punch_auto`: hit_effect, impact_sound_event, no_damage_impact_sound_event
- `action_one.push`: hit_effect, impact_sound_event, no_damage_impact_sound_event

**Menus and tooltips**

- `tooltip_compare.heavy.action_name` = "action_one"
- `tooltip_compare.light.action_name` = "action_one"
- `tooltip_detail.heavy.action_name` = "action_one"
- `tooltip_detail.light.action_name` = "action_one"
- `tooltip_keywords.1` = "weapon_keyword_high_damage"
- `tooltip_keywords.3` = "weapon_keyword_armour_piercing"
- `weapon_diagram.heavy_attack.5` = 6

**Unclear**

- `action_wield.default` (all of it)
- `action_one.bash`: enter_function
- `action_one.punch`: enter_function
- `action_one.punch_auto`: enter_function

## shield_gun_we

`ut_shield_gun_we_template`, a copy of `we_spear` (`two_handed_spears_elf_template_1`).

New sub-actions: `action_one.bash` (like the base's action_one.heavy_attack_left); `action_one.punch` (like the base's action_one.heavy_attack_left); `action_one.punch_auto` (like the base's action_one.heavy_attack_left).

**Gameplay: should be set explicitly**

- `aim_assist_settings` (all of it)
- `attack_meta_data.hold_attack.arc` = 2
- `buff_type` = "MELEE_2H"
- `buffs` (all of it)
- `crosshair_style` = "dot"
- `dodge_count` = 3
- `max_fatigue_points` = 6
- `outer_block_angle` = 360
- `outer_block_fatigue_point_multiplier` = 2
- `weapon_type` = "POLEARM"
- `action_two.default` (all of it)
- `action_one.bash`: additional_critical_strike_chance, allowed_chain_actions (6), buff_data, charge_value, damage_profile, dedicated_target_range, hit_mass_count, range_mod, sweep_z_offset, use_precision_sweep, width_mod
- `action_one.default`: allowed_chain_actions (6), attack_hold_input, total_time
- `action_one.punch`: additional_critical_strike_chance, allowed_chain_actions (6), buff_data, charge_value, damage_profile, dedicated_target_range, hit_mass_count, range_mod, sweep_z_offset, use_precision_sweep, width_mod
- `action_one.punch_auto`: additional_critical_strike_chance, allowed_chain_actions (6), buff_data, charge_value, damage_profile, dedicated_target_range, hit_mass_count, range_mod, sweep_z_offset, use_precision_sweep, width_mod
- `action_one.push`: allowed_chain_actions (10), buff_data, chain_condition_func, charge_value, damage_profile_inner, damage_profile_outer, damage_window_end, damage_window_start, dedicated_target_range, kind, outer_push_angle, push_angle, push_radius, total_time

**Tied to the base's animations, models or career skills: stays**

- `display_unit` = "units/weapons/weapon_display/display_2h_spears_wood_elf"
- `required_projectile_unit_templates` (all of it)
- `right_hand_attachment_node_linking` (all of it)
- `right_hand_unit` = "units/weapons/player/wpn_empire_short_sword/wpn_empire_short_sword"
- `state_machine` = "units/beings/player/first_person_base/state_machines/melee/spear"
- `wield_anim` = "to_spear"
- `wwise_dep_right_hand` (all of it)
- `action_career_we_3.default` (all of it)
- `action_career_we_3_piercing.default` (all of it)
- `action_career_we_thornsister.default` (all of it)
- `action_inspect.action_inspect_hold` (all of it)
- `action_inspect.default` (all of it)
- `action_one.bash`: anim_end_event_condition_func, anim_time_scale, baked_sweep, first_person_hit_anim, hit_armor_anim, hit_shield_stop_anim, hit_stop_anim
- `action_one.default`: anim_end_event, anim_end_event_condition_func, anim_event
- `action_one.punch`: anim_end_event_condition_func, anim_time_scale, baked_sweep, first_person_hit_anim, hit_armor_anim, hit_shield_stop_anim, hit_stop_anim
- `action_one.punch_auto`: anim_end_event_condition_func, anim_time_scale, baked_sweep, first_person_hit_anim, hit_armor_anim, hit_shield_stop_anim, hit_stop_anim
- `action_one.push`: anim_end_event, anim_end_event_condition_func, anim_event, weapon_action_hand

**The game's own hit effects and sounds**

- `action_one.bash`: hit_effect, impact_sound_event, no_damage_impact_sound_event
- `action_one.punch`: hit_effect, impact_sound_event, no_damage_impact_sound_event
- `action_one.punch_auto`: hit_effect, impact_sound_event, no_damage_impact_sound_event
- `action_one.push`: hit_effect, impact_sound_event, no_damage_impact_sound_event

**Menus and tooltips**

- `tooltip_compare.heavy.action_name` = "action_one"
- `tooltip_compare.light.action_name` = "action_one"
- `tooltip_detail.heavy.action_name` = "action_one"
- `tooltip_detail.light.action_name` = "action_one"
- `weapon_diagram.heavy_attack.2` = 4
- `weapon_diagram.light_attack.2` = 3
- `weapon_diagram.light_attack.5` = 3

**Unclear**

- `action_wield.default` (all of it)
- `action_one.bash`: enter_function, weapon_up_offset_mod
- `action_one.punch`: enter_function, weapon_up_offset_mod
- `action_one.punch_auto`: enter_function, weapon_up_offset_mod

## shield_gun_wh

`ut_shield_gun_wh_template`, a copy of `wh_2h_billhook` (`two_handed_billhooks_template`).

New sub-actions: `action_one.bash` (like the base's action_one.default); `action_one.punch` (like the base's action_one.default); `action_one.punch_auto` (like the base's action_one.default).

**Gameplay: should be set explicitly**

- `aim_assist_settings` (all of it)
- `attack_meta_data.hold_attack.arc` = 2
- `buff_type` = "MELEE_2H"
- `buffs` (all of it)
- `crosshair_style` = "dot"
- `dodge_count` = 3
- `max_fatigue_points` = 6
- `outer_block_angle` = 360
- `outer_block_fatigue_point_multiplier` = 2
- `weapon_type` = "POLEARM"
- `action_three.default` (all of it)
- `action_one.bash`: allowed_chain_actions (6), attack_hold_input, buff_data
- `action_one.default`: allowed_chain_actions (6), attack_hold_input, total_time
- `action_one.punch`: allowed_chain_actions (4), attack_hold_input, buff_data
- `action_one.punch_auto`: allowed_chain_actions (4), attack_hold_input, buff_data
- `action_one.push`: allowed_chain_actions (11), buff_data, chain_condition_func, charge_value, damage_profile_inner, damage_profile_outer, damage_window_end, damage_window_start, dedicated_target_range, kind, outer_push_angle, push_angle, push_radius, total_time
- `action_two.default`: allowed_chain_actions, buff_data, cooldown, hold_input, kind, minimum_hold_time, total_time

**Tied to the base's animations, models or career skills: stays**

- `display_unit` = "units/weapons/weapon_display/display_2h_billhooks"
- `required_projectile_unit_templates` (all of it)
- `right_hand_attachment_node_linking` (all of it)
- `right_hand_unit` = "units/weapons/player/wpn_empire_short_sword/wpn_empire_short_sword"
- `state_machine` = "units/beings/player/first_person_base/state_machines/melee/2h_billhook"
- `wield_anim` = "to_2h_billhook"
- `wwise_dep_right_hand` (all of it)
- `action_career_wh_2.default` (all of it)
- `action_career_wh_priest.default` (all of it)
- `action_inspect.action_inspect_hold` (all of it)
- `action_inspect.default` (all of it)
- `action_one.bash`: anim_end_event, anim_event
- `action_one.default`: anim_end_event, anim_event, anim_event_3p
- `action_one.punch`: anim_end_event, anim_event
- `action_one.punch_auto`: anim_end_event, anim_event
- `action_one.push`: anim_end_event, anim_event
- `action_two.default`: anim_end_event, anim_event

**The game's own hit effects and sounds**

- `action_one.push`: hit_effect, impact_sound_event, no_damage_impact_sound_event

**Menus and tooltips**

- `tooltip_compare.heavy.action_name` = "action_one"
- `tooltip_compare.light.action_name` = "action_one"
- `tooltip_detail.heavy.action_name` = "action_one"
- `tooltip_detail.light.action_name` = "action_one"
- `tooltip_special_action_description` = "special_action_billhook"
- `weapon_diagram.light_attack.3` = 3

**Unclear**

- `action_wield.default` (all of it)
- `action_two.default`: enter_function

## shock_rifle

`ut_shock_rifle_template`, a copy of `bw_skullstaff_beam` (`staff_blast_beam_template_1`).

**Gameplay: should be set explicitly**

- `aim_assist_settings` (all of it)
- `attack_meta_data.aim_at_node` = "j_head"
- `attack_meta_data.aim_at_node_charged` = "j_spine1"
- `attack_meta_data.aim_data` (all of it)
- `attack_meta_data.aim_data_charged` (all of it)
- `attack_meta_data.charge_when_obstructed` = true
- `attack_meta_data.charge_when_outside_max_range_charged` = false
- `attack_meta_data.effective_against_charged` = 0
- `attack_meta_data.ignore_enemies_for_obstruction` = false
- `attack_meta_data.ignore_enemies_for_obstruction_charged` = false
- `attack_meta_data.max_range` = 50
- `attack_meta_data.max_range_charged` = 6
- `attack_meta_data.minimum_charge_time` = 0.20999999999999999
- `attack_meta_data.obstruction_fuzzyness_range` = 1
- `attack_meta_data.obstruction_fuzzyness_range_charged` = 6
- `buff_type` = "RANGED"
- `buffs` (all of it)
- `crosshair_style` = "arrows"
- `default_spread_template` = "spear"
- `overcharge_data` (all of it)
- `weapon_type` = "FIRE_STAFF"
- `weapon_reload.default` (all of it)
- `action_one.default`: allowed_chain_actions (2), is_spell
- `action_two.default`: allowed_chain_actions (4)

**Tied to the base's animations, models or career skills: stays**

- `display_unit` = "units/weapons/weapon_display/display_staff"
- `left_hand_attachment_node_linking` (all of it)
- `left_hand_unit` = "units/weapons/player/wpn_fireball/wpn_fireball"
- `right_hand_attachment_node_linking` (all of it)
- `right_hand_unit` = "units/weapons/player/wpn_brw_skullstaff/wpn_brw_skullstaff"
- `state_machine` = "units/beings/player/first_person_base/state_machines/ranged/staff"
- `wield_anim` = "to_staff"
- `wwise_dep_right_hand` (all of it)
- `action_career_bw_1.default` (all of it)
- `action_career_bw_necromancer.default` (all of it)
- `action_inspect.action_inspect_hold` (all of it)
- `action_inspect.default` (all of it)

**Menus and tooltips**

- `tooltip_compare.light` (all of it)
- `tooltip_detail.light` (all of it)
- `tooltip_keywords.1` = "weapon_keyword_sniper"
- `tooltip_keywords.2` = "weapon_keyword_crowd_control"
- `weapon_diagram.light_attack.2` = 1

**Unclear**

- `action_wield.default` (all of it)

