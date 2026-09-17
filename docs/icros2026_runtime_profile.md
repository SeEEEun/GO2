# ICROS2026 Runtime Profile

Last updated: 2026-06-26 KST

This is the current competition runtime profile after the `동아리방` remap.
The profile is designed for random route assignment, saved-map localization
error, and the obstacle dimensions shown in the rules/orientation material.

## Main Runtime Loop

```text
organizer ROS2 message
-> icros2026_mission_normalizer
-> /icros2026/goal_zone or direct goal
-> icros2026_goal_adapter with measured semantic map
-> /goal_pose
-> goal_snapper
-> /trg/input/snapped_goal_pose
-> TRG planner on saved map + live cloud
-> /trg/output/path
-> path_to_cmd_vel with localization + live height scan gates
-> /rl/cmd_vel
-> go2_sport_cmd_bridge
-> Unitree SportClient.Move
```

The real route is not replayed. Route A/B/C sequencing is only a rehearsal tool.
During the match, each next target is accepted from the organizer message. Zone
1 is the common start/end condition, but the next zones are not assumed by the
motion stack.

## Map Error Handling

The robot does not drive from the saved PCD alone.

- FAST-LIO keeps live `/Odometry` and `/cloud_registered`.
- `scan_to_map_localizer` aligns live scans against the saved map and publishes
  `/localized_odometry` plus `/cloud_registered_map`.
- TRG uses `/localized_odometry` and `/cloud_registered_map`, so path generation
  tracks the live-localized frame.
- `height_scan_bridge` uses the same localized cloud/odom pair for front terrain
  risk.
- Repeated ICP correction is enabled by default:
  - `freeze_after_localized=false`
  - `icp_period_s=1.0`
  - `max_update_translation_m=0.35`
  - `max_update_yaw_rad=0.35`
- Automatic initial alignment is enabled:
  - search yaw over `-180..180 deg`,
  - recompute map-to-live translation for every yaw candidate,
  - run coarse ICP before publishing the first accepted transform,
  - relocalize after repeated rejected jumps if the candidate stays inside the
    reinitialization safety limits.

Large localization jumps are rejected. The odometry watchdog still stops the
stack if raw or localized odometry steps become physically unreasonable.

In the Sport saved-map stack, `path_to_cmd_vel` also requires localization
quality before movement:

```text
localization_status_topic = /icros2026/localization/status
require_localization_ok   = true
localization_ok_states    = OK,RELOCALIZED
localization_min_fitness  = 0.35
localization_max_rmse     = 0.55
localization_timeout_s    = 1.5
```

If localization is missing, stale, rejected, low-fitness, or high-RMSE,
`path_to_cmd_vel` publishes stop instead of a nonzero `/rl/cmd_vel`.

## Obstacle Height Gates

These values are runtime safety gates, not route hardcoding.

| Terrain | Rule/PDF cue | Runtime treatment |
| --- | --- | --- |
| Flat floor | normal course floor | `flat`, conservative speed |
| Crosswalk low bars | about 38 mm class repeated unevenness | `approach` or `cross`, slow traversal |
| Rough tile | about 0.15 m rough/tile feature | `cross`, slow traversal |
| Bridge entry/support | rules list 0.2 m class support blocks | `cross` or `high_risk`, centered slow traversal only |
| Center stair/slope | 0.45 m central structure | `high_risk`, very slow attempt only after practice success |
| Wall/boundary | 0.6 m wall class | `blocked`, avoid/stop/pass |
| Hidden/gap | private obstacle | live sensing; unknown/blocked can stop and trigger pass decision |

Current `path_to_cmd_vel` thresholds:

```text
height_step_slow_m      = 0.05
height_step_cross_m     = 0.15
height_step_block_m     = 0.30
height_step_wall_m      = 0.55
height_roughness_slow_m = 0.10
height_roughness_cross_m= 0.20
height_roughness_block_m= 0.34
height_roughness_wall_m = 0.60
unknown_stop_ratio      = 0.72
high_risk_speed_scale   = 0.22
allow_high_risk_terrain = true
```

Interpretation:

- Below slow/cross thresholds: normal bounded path following.
- Above cross threshold: reduce speed, keep Sport mode balance controller.
- Above block threshold but below wall threshold: publish `high_risk` and crawl.
- Above wall threshold: publish `blocked`, stop, replan or pass.

## Current `동아리방` Preset

The current practice map can be launched with the new preset:

```bash
cd /home/jairlab/go2_ws
CONTROL_BACKEND=sport ./scripts/start_saved_map_trg_rl_stack.sh dongari
```

This uses:

- localization map:
  `/home/jairlab/go2_ws/maps/dongari_room_20260626_clean_level.pcd`
- localization meta:
  `/home/jairlab/go2_ws/maps/dongari_room_20260626_clean_level_meta.json`
- planner source:
  `/home/jairlab/go2_ws/maps/dongari_room_20260626_planner_source.pcd`
- TRG safe map/config:
  `dongari_room_20260626_v3_traversable_safe`

For organizer-message rehearsal on a measured semantic map:

```bash
cd /home/jairlab/go2_ws
CONTROL_BACKEND=sport \
ARENA_SEMANTICS_PATH=/absolute/path/to/icros2026_semantic_map.yaml \
LAUNCH_GOAL_ADAPTER=true \
LAUNCH_MISSION_NORMALIZER=true \
LAUNCH_FRONT_CAMERA_BRIDGE=true \
LAUNCH_MISSION_EXECUTOR=true \
./scripts/start_saved_map_trg_rl_stack.sh dongari
```

For route-card rehearsal only:

```bash
cd /home/jairlab/go2_ws
CONTROL_BACKEND=sport \
ARENA_SEMANTICS_PATH=/absolute/path/to/icros2026_semantic_map.yaml \
LAUNCH_GOAL_ADAPTER=true \
LAUNCH_ROUTE_SEQUENCER=true \
ROUTE_CARD=A \
./scripts/start_saved_map_trg_rl_stack.sh dongari
```

## Competition Map Swap

At the venue, replace the `dongari` preset inputs with the measured course map:

```bash
LOCALIZATION_MAP_PATH=/path/to/course_clean_level.pcd
LOCALIZATION_LEVEL_META=/path/to/course_clean_level_meta.json
PLANNER_SOURCE_MAP_PATH=/path/to/course_planner_source.pcd
TRG_SAFE_MAP_PATH=/path/to/course_traversable_safe.pcd
MAP_CONFIG=course_traversable_safe
ARENA_SEMANTICS_PATH=/path/to/course_semantic_map.yaml
CONTROL_BACKEND=sport
LAUNCH_GOAL_ADAPTER=true
LAUNCH_MISSION_NORMALIZER=true
LAUNCH_FRONT_CAMERA_BRIDGE=true
LAUNCH_MISSION_EXECUTOR=true
./scripts/start_saved_map_trg_rl_stack.sh competition
```

The route remains message-driven. The measured semantic map supplies zone
goals, walls, QR sides, and risk regions; it must not contain guessed PDF
coordinates for the final run.
