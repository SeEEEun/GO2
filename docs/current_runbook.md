# Current Competition Runbook

Last updated: 2026-06-26 KST

This runbook is for the current main strategy: Sport-based autonomous driving.
It intentionally separates offline rehearsal, real sensor dry-run, and real
Sport movement.

## Safety Defaults

- Keep low-level SDK motor publish disabled unless explicitly doing a harnessed
  low-level experiment.
- Use Sport backend for the competition mainline.
- Do not run fixed-distance or fixed-turn scripts as competition behavior.
  Motion must come from organizer messages, measured map semantics, TRG path
  following, and live feedback.
- The main runtime profile is documented in
  `/home/jairlab/GO2/docs/icros2026_runtime_profile.md`.
- Start every real-robot session by checking that no stale command publisher is
  running.
- Stop the stack before returning to joystick/manual operation.

Stop current navigation stack:

```bash
cd /home/jairlab/go2_ws
ACTION=stop ./scripts/start_saved_map_trg_rl_stack.sh
```

Check for local command publishers:

```bash
pgrep -af 'go2_sport_cmd_bridge|go2_sdk2_bridge|onnx_policy_node|path_to_cmd_vel|trg_ros2_node|deploy_go2_icros|lowcmd|ros2 launch|ros2 run'
```

## 1. Readiness Audit

```bash
cd /home/jairlab/go2_ws
PRESET=practice MODE=presport ./scripts/icros2026_readiness_audit.sh
```

Record the result in `/home/jairlab/GO2/docs/progress_log.md`.

If the audit reports missing ROS packages, rebuild/source `go2_ws` and
`go2_roughnav_ws` before moving to the robot.

## 2. Offline Reference Rehearsal

Use this before touching the real robot.

```bash
cd /home/jairlab/go2_ws
./scripts/start_icros2026_reference_sim.sh
```

Current Step 5 wrapper for the no-RL mainline:

```bash
cd /home/jairlab/GO2
ROUTE_CARD=A ACTION=start ./scripts/step5_reference_rehearsal.sh
```

This wrapper:

- stops conflicting live MID360/reference-sim processes,
- validates `maps/icros2026_reference_semantic_map.yaml`,
- starts the public reference map in RViz,
- starts TRG and `height_scan_bridge`,
- starts `path_to_cmd_vel` against `/trg/output/path`,
- starts `icros2026_goal_adapter` and `icros2026_route_sequencer`,
- keeps `onnx_policy_node`, `go2_sdk2_bridge`, and Sport command bridge off.

Stop:

```bash
cd /home/jairlab/GO2
ACTION=stop ./scripts/step5_reference_rehearsal.sh
```

What to check in RViz:

- Reference ICROS2026 terrain appears.
- TRG graph/path appears.
- Route A/B/C zone goals can be published.
- Goal snapping lands on walkable terrain.
- Central cross and bridge-like terrain are represented as traversable terrain,
  not erased as noise.
- Route A/B/C zone-only goals produce `/goal_pose`,
  `/trg/input/snapped_goal_pose`, and a non-empty `/trg/output/path`.

Stop:

```bash
cd /home/jairlab/go2_ws
ACTION=stop ./scripts/start_icros2026_reference_sim.sh
```

## 3. Mapping Procedure

Use the existing `go2_ws` mapping flow.

Start FAST-LIO2 mapping:

```bash
cd /home/jairlab/go2_ws
./scripts/run_go2_fastlio_mapping.sh
```

Recommended collection pattern:

- Stand still for about 10 seconds after startup.
- Move slowly.
- Revisit obstacle regions from multiple headings.
- Keep people out of the repeated mapping passes.
- Record separate passes if time allows.

Record pass bags:

```bash
cd /home/jairlab/go2_ws
./scripts/record_erasor2_clubroom_bag.sh ${ENV}_pass1
./scripts/record_erasor2_clubroom_bag.sh ${ENV}_pass2
./scripts/record_erasor2_clubroom_bag.sh ${ENV}_pass3
```

Diagnose bags:

```bash
cd /home/jairlab/go2_ws
./scripts/diagnose_fastlio_bag.py /home/jairlab/go2_ws/bags/${ENV}_pass1
```

Save/stop mapping:

```bash
cd /home/jairlab/go2_ws
./scripts/stop_go2_fastlio_mapping.sh
```

Important:

- Do not overwrite raw maps.
- Save cleaned maps with new names.
- Keep localization dense map and TRG planner source map separate.
- Preserve the useful parts from the previous mapping workflow in
  `/home/jairlab/GO2/이전 mapping`:
  - multi-pass temporal confidence for dynamic object rejection,
  - robust upper-percentile cell height instead of raw max height,
  - low tile/ramp/rough-terrain preservation,
  - separate raw, cleaned, temporal-static, and TRG planner map outputs,
  - RViz validation of walkable surface, obstacle mask, nodes, edges, and path.

## 4. TRG Map Build

For existing practice and clubroom maps:

```bash
cd /home/jairlab/go2_ws
./scripts/rebuild_icros2026_trg_maps.sh practice
./scripts/rebuild_icros2026_trg_maps.sh clubroom
```

Latest practice rebuild from the previous mapping workflow:

```text
input: /home/jairlab/go2_ws/maps/go2_dual_lidar_clean_level_detail_surface.pcd
output: /home/jairlab/go2_ws/maps/go2_dual_lidar_icros2026_traversable_safe.pcd
config: /home/jairlab/go2_ws/src/TRG-planner/config/go2_dual_lidar_icros2026_traversable_safe.yaml
walkable_cells: 3113
```

For a newly measured competition map, follow the same map-cleaning principles:

- level the raw map,
- remove ceiling/high clutter from planner source,
- preserve low terrain details,
- fill removed dynamic-person areas only when surrounding floor evidence
  supports it,
- use robust upper-percentile height for traversable cells,
- build traversable map and obstacle mask,
- validate in RViz before real movement.

Relevant existing runbooks:

- `/home/jairlab/go2_ws/docs/runbooks/FASTLIO_GO2_RUNBOOK.md`
- `/home/jairlab/go2_ws/docs/runbooks/saved_map_trg_rl_runbook.md`
- `/home/jairlab/go2_ws/docs/runbooks/ERASOR2_GO2_STATIC_MAP_PIPELINE.md`

## 5. Real Sensor And Localization Dry-Run

Use this before Sport movement. This starts real FAST-LIO and localization but
does not start the Sport walking bridge and does not publish low-level SDK
commands.

Before this dry-run, build or load the correct map. The previous practice map is
useful for pipeline checks, but it is not the current arena map.

### 5.1 Current / Competition Pre-Mapping

Run this when RViz is showing an old map, or at the competition before route
rehearsal.

```bash
cd /home/jairlab/GO2
ACTION=start ./scripts/step6_current_mapping.sh
```

Expected:

```text
RViz opens with FAST-LIO live map
/livox/lidar is about 10 Hz
/cloud_registered is live
/map_save service exists
/rl/cmd_vel is unknown or has zero publishers
no go2_sport_cmd_bridge
no go2_sdk2_bridge
no onnx_policy_node
```

Move the robot slowly through the target area using a separate guarded operator
workflow. This mapping wrapper itself never starts Sport, SDK, policy, or
`/rl/cmd_vel`.

Save while continuing to map:

```bash
cd /home/jairlab/GO2
ACTION=save ./scripts/step6_current_mapping.sh
```

Save and stop:

```bash
cd /home/jairlab/GO2
ACTION=save_stop ./scripts/step6_current_mapping.sh
```

Current named map:

```text
/home/jairlab/go2_ws/maps/current_mapping/동아리방.pcd
saved: 2026-06-26 11:07 KST
points: 1382290
size: 44233533 bytes
latest symlink: /home/jairlab/go2_ws/maps/current_mapping/latest_current_fastlio_map.pcd
previous same-name backup: /home/jairlab/go2_ws/maps/current_mapping/동아리방_backup_20260626_110710.pcd
```

After saving the full course map, derive:

- cleaned/leveled localization map,
- measured semantic map with zones, walls, QR sides, and risk regions,
- TRG traversability map.

Then rerun Step 5 route rehearsal and Step 6 sensor-only dry-run with the
measured map.

Current `동아리방` derived map set:

```text
raw saved map:
  /home/jairlab/go2_ws/maps/current_mapping/동아리방.pcd
cleaned:
  /home/jairlab/go2_ws/maps/dongari_room_20260626_clean.pcd
cleaned + leveled:
  /home/jairlab/go2_ws/maps/dongari_room_20260626_clean_level.pcd
planner source:
  /home/jairlab/go2_ws/maps/dongari_room_20260626_planner_source.pcd
selected TRG map:
  /home/jairlab/go2_ws/maps/dongari_room_20260626_v3_traversable_safe.pcd
selected TRG config:
  /home/jairlab/go2_ws/src/TRG-planner/config/dongari_room_20260626_v3_traversable_safe.yaml
```

The direct ICROS-profile build
`dongari_room_20260626_traversable_safe` produced only `1` walkable cell and is
not selected. The current selected rehearsal map is
`dongari_room_20260626_v3_traversable_safe` with `859` walkable cells.

Current map visualization/rehearsal command, no Sport movement:

```bash
setsid bash -lc '
  export ROS_DOMAIN_ID=88
  export RVIZ=true
  export GAZEBO=false
  export TRG_DIRECT_FALLBACK=0
  export MAP_PATH=/home/jairlab/go2_ws/maps/dongari_room_20260626_planner_source.pcd
  export WALKABLE_MAP_PATH=/home/jairlab/go2_ws/maps/dongari_room_20260626_v3_traversable_safe.pcd
  export WALKABLE_MAP_IS_PRESCREENED=true
  export MAP_CONFIG=dongari_room_20260626_v3_traversable_safe
  export WALKABLE_GRID_RESOLUTION=0.10
  export START_X=0.187
  export START_Y=-0.325
  cd /home/jairlab/go2_ws
  exec ./scripts/start_map_policy_sim.sh isaaclab_best_45000 \
    run_policy:=false run_sdk2_dryrun:=false run_cmd:=false \
    run_health:=true launch_rviz:=true
' >/tmp/dongari_room_step5_visualization_v3.log 2>&1 &
```

Latest visualization check:

```text
TRG prebuilt map: 859 nodes
prebuilt graph: 859 nodes, 6306 edges
/Odometry: OK at approximately (0.187, -0.325, 0.234)
/cloud_registered: OK, 80000 points in simulation
/rl/height_scan: OK, 273 cells
/rl/cmd_vel: 0 publishers
test goal: approximately (0.937, -3.276)
/trg/output/path: 12 poses
```

### 5.2 Sensor-Only Localization/TRG Dry-Run

Current validated live sensor gate uses the external MID360 mainline, not the
built-in UTLiDAR FAST-LIO path:

```bash
source /opt/ros/humble/setup.bash
source /home/jairlab/go2_ws/install/setup.bash
source /home/jairlab/go2_roughnav_ws/install/setup.bash
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export CYCLONEDDS_URI=file:///tmp/cyclonedds_livox.xml
export LIVOX_CONFIG_PATH=/tmp/MID360_config_livox.json
```

Live MID360 FAST-LIO visualization without movement:

```bash
cd /home/jairlab/go2_ws
./scripts/setup_livox_cyclonedds.sh
FASTLIO_CONFIG=/home/jairlab/go2_ws/src/FAST_LIO_ROS2/FAST_LIO/config/mid360.yaml \
AUTO_SAVE_ON_EXIT=false \
RVIZ=false \
STARTUP_HEALTH_CHECK=false \
./scripts/start_go2_fastlio_mapping.sh
```

Visualize:

```bash
rviz2 -d /home/jairlab/go2_ws/src/FAST_LIO_ROS2/FAST_LIO/rviz_cfg/fastlio.rviz
```

Attach read-only diagnostics:

```bash
ros2 run go2_roughnav height_scan_bridge --ros-args \
  -p cloud_topic:=/cloud_registered \
  -p odom_topic:=/Odometry \
  -p out_topic:=/rl/height_scan \
  -p point_stride:=3

ros2 run go2_roughnav traversability_node --ros-args \
  -p pointcloud_topic:=/cloud_registered \
  -p terrain_flags_topic:=/roughnav/terrain_flags \
  -p map_topic:=/traversability_map
```

Expected live rates from the latest check:

```text
/livox/lidar       about 10 Hz
/cloud_registered about 6.5 Hz
/Odometry          about 6.6 Hz
/rl/height_scan    fresh
/roughnav/terrain_flags fresh diagnostic JSON
```

Do not use the built-in UTLiDAR FAST-LIO path as the competition mainline. It
sampled topics in the correct environment, but the tested FAST-LIO odometry
diverged badly.

Step 6 repeatable wrapper:

```bash
cd /home/jairlab/GO2
ACTION=start ./scripts/step6_real_sensor_only_dry_run.sh
```

Current `동아리방` map sensor-only dry-run:

```bash
cd /home/jairlab/GO2
LOCALIZATION_MAP_PATH=/home/jairlab/go2_ws/maps/dongari_room_20260626_clean_level.pcd \
LOCALIZATION_LEVEL_META=/home/jairlab/go2_ws/maps/dongari_room_20260626_clean_level_meta.json \
VIS_MAP_PATH=/home/jairlab/go2_ws/maps/dongari_room_20260626_planner_source.pcd \
MAP_CONFIG=dongari_room_20260626_v3_traversable_safe \
RVIZ=true \
ACTION=start ./scripts/step6_real_sensor_only_dry_run.sh
```

RViz map layers:

- `/saved_pcd_map`: lightweight planner/visualization map, usually the
  `planner_source` PCD.
- `/localization_saved_pcd_map`: dense saved map used by localization, shown by
  default so the original mapping result can be compared against live
  `/cloud_registered_map`.
- `/cloud_registered_map`: localized live FAST-LIO cloud. This must overlap the
  saved map. If this separates from the saved map, localization is not ready for
  movement.

If the saved mapping result appears missing, verify both topics before
remapping:

```bash
ros2 topic list | grep -E 'saved_pcd_map|localization_saved_pcd_map'
tail -n 5 /tmp/icros2026_step6_saved_pcd_map.log
tail -n 5 /tmp/icros2026_step6_localization_saved_pcd_map.log
ros2 topic echo /icros2026/localization/status --once
```

Expected:

```text
localization state=OK
TRG obsCloud=/cloud_registered_map
TRG egoOdom=/localized_odometry
/rl/height_scan is fresh
/roughnav/terrain_flags is fresh diagnostic JSON
/trg/output/path publishes after a test goal
/rl/cmd_vel publisher count is 0
no path_to_cmd_vel
no go2_sport_cmd_bridge
no go2_sdk2_bridge
no onnx_policy_node
```

Latest current-map Step 6 result from 2026-06-26 11:20 KST:

```text
map                         dongari_room_20260626_v3_traversable_safe
/livox/lidar                sampled around 7-9 Hz
/cloud_registered           sampled around 9-10 Hz
/Odometry                   sampled around 8-10 Hz
/localized_odometry         sampled around 9-10 Hz
/cloud_registered_map       fresh
/rl/height_scan             fresh, 273 cells
TRG graph                   initialized
test goal                   approximately (0.937, -3.276)
/trg/output/path            24 poses
/rl/cmd_vel                 0 publishers
movement backend            not started
```

Watch item:

```text
FAST-LIO prints repeated IMU dt warnings. Treat this as sensor-only ready, not
movement-ready, until stationary drift and short-goal Sport tests are checked.
```

Latest Step 6 result from 2026-06-26 10:37 KST:

```text
/livox/lidar              10.2 Hz
/cloud_registered          5.6 Hz
/cloud_registered_map      0.8 Hz
/Odometry                  5.6 Hz
/localized_odometry        5.6 Hz
/rl/height_scan            0.8 Hz
/roughnav/terrain_flags    5.7 Hz
raw odom drift over 8 s    0.002 m
localized drift over 8 s   0.004 m
/rl/cmd_vel                0 publishers, 0 observed messages
temporary TRG goal         path_count=5, latest path_len=2
```

Terrain risk check:

```bash
ros2 topic hz /rl/height_scan
ros2 topic echo --once /roughnav/terrain_flags
ros2 topic info /rl/cmd_vel -v
```

Pass condition:

- `/rl/cmd_vel` has zero publishers.
- Sport/SDK/policy/path tracking nodes are absent.
- TRG graph is loaded from the previous mapping ICROS2026 map.
- Saved-map localization state is `OK`.
- A temporary `/goal_pose` can produce `/trg/output/path` without movement.
- `terrain_flags` publishes JSON with `state`, `reason`, `unknown_ratio`,
  `blocked_ratio`, `rough_ratio`, and `observed_cells`.
- `flat`, `approach`, and `cross` may be used for slow path tracking.
- `unknown` requires slow sensor-only inspection.
- `blocked`, missing scan, or stale scan means no Sport movement.

Stop before changing modes:

```bash
cd /home/jairlab/GO2
ACTION=stop ./scripts/step6_real_sensor_only_dry_run.sh
```

## 6. Sport Movement Gate

Only use after:

- Go2 is standing normally.
- Go2 LAN interface is up.
- No stale local command publisher remains.
- Localization and TRG path are already verified.
- A human is ready to stop the robot.

Check robot Sport mode:

```bash
cd /home/jairlab/go2_ws
ACTION=check NETWORK_INTERFACE=enp46s0 ./scripts/recover_go2_sport_mode.sh
```

Start Sport backend with conservative limits:

```bash
cd /home/jairlab/GO2
ACTION=start ./scripts/step7_sport_short_goal_smoke.sh
```

Manual RViz 2D Goal test:

```bash
cd /home/jairlab/GO2
CONFIRM_CLEAR=true ACTION=manual_start ./scripts/step7_sport_short_goal_smoke.sh
```

Expected chain:

```text
/goal_pose -> /trg/input/snapped_goal_pose -> /trg/output/path
-> /rl/cmd_vel -> go2_sport_cmd_bridge -> SportClient.Move()
```

Use this mode only for a short reachable goal on clear floor. The auto gate
returns `/rl/sport_stop=true` after path completion or timeout.

Short goal smoke:

```bash
cd /home/jairlab/GO2
CONFIRM_CLEAR=true ACTION=run ./scripts/step7_sport_short_goal_smoke.sh
```

Pass condition:

- The robot moves toward the goal without tilt, slip, or command runaway.
- `/rl/sport_stop` returns true after the test.
- `go2_sport_cmd_bridge/status` shows bounded commands.

Fail condition:

- Localization jumps.
- Robot is stuck and recovery repeats.
- Joystick/manual control becomes unavailable.
- Any unexpected local publisher remains after stopping.

## 7. Semantic Map Gate

Before accepting zone-only organizer messages, create and validate a measured
semantic map.

Start from the template:

```bash
cd /home/jairlab/GO2
cp templates/icros2026_semantic_map.template.yaml /tmp/icros2026_semantic_map.yaml
```

Fill it with measured values from the aligned course map, then validate:

```bash
cd /home/jairlab/GO2
python3 tools/validate_icros2026_semantic_map.py /absolute/path/to/icros2026_semantic_map.yaml
```

Pass condition:

- all four zones have finite measured goals,
- measurement source and frame are recorded,
- wall/mission/risk semantics contain no `TODO` or `null`,
- validator exits with `OK`.

Launch the Sport mainline with the measured map:

```bash
cd /home/jairlab/go2_ws
CONTROL_BACKEND=sport \
ARENA_SEMANTICS_PATH=/absolute/path/to/icros2026_semantic_map.yaml \
LAUNCH_GOAL_ADAPTER=true \
LAUNCH_MISSION_NORMALIZER=true \
LAUNCH_FRONT_CAMERA_BRIDGE=true \
LAUNCH_MISSION_EXECUTOR=true \
./scripts/start_saved_map_trg_rl_stack.sh competition
```

Do not set `allow_legacy_zone_params:=true` for competition runs.

## 8. Non-Hardcoded Mission Gate

Before enabling full autonomous missions, confirm:

- Organizer ROS2 message spec is known or wrapped by
  `icros2026_mission_normalizer`.
- Zone goals come from organizer pose/point/XY or a measured semantic map, not
  built-in default coordinates.
- Stack-light color is read from the organizer message and optionally verified
  with Go2 onboard camera.
- Photo missions use the Go2 front camera SDK stream, not the laptop camera.
- Wall-touch missions use map/range/odom/contact feedback, not blind timed
  lateral movement.
- Current normalizer forwards QR/photo missions to the executor. Wall-touch
  missions are normalized but blocked from the executor until guarded touch
  execution exists.
- Sport saved-map movement must keep `path_to_cmd_vel.require_localization_ok`
  enabled so rejected/stale/low-quality scan-to-map alignment cannot produce a
  nonzero `/rl/cmd_vel`.

Normalizer input/output topics:

```text
/icros2026/organizer/mission      raw String JSON/key-value input
/icros2026/organizer/zone         optional Int32 target zone
/icros2026/organizer/color        optional String orange/red
/icros2026/organizer/mission_type optional String mission type
/icros2026/mission/normalized     normalized JSON output
/icros2026/mission/request        executor request for supported missions
/icros2026/goal_zone              target zone for goal adapter
```

Reference:

```text
/home/jairlab/GO2/docs/non_hardcoded_obstacle_strategy.md
/home/jairlab/GO2/docs/semantic_map_contract.md
```

## 9. Obstacle Feasibility Gate

Treat Sport mode as conditionally capable, not guaranteed.

- Crosswalk/low uneven terrain: test with conservative speed.
- Shaking bridge and 0.2 m entry blocks: require centered map corridor and
  abort on lateral drift or roll spikes.
- Rough tile: allow after height-scan/TRG slow-down is verified.
- Hidden/foot-drop terrain: slow exploration only; stop on repeated foot drop,
  slip, or body attitude spikes.
- Central 0.45 m stair/slope cross: attempt only after a proven practice climb.
  Otherwise use controlled partial progress and 4-minute pass strategy.

Current runtime terrain thresholds:

```text
height_step_slow_m=0.05
height_step_cross_m=0.15
height_step_block_m=0.30
height_step_wall_m=0.55
high_risk_speed_scale=0.22
allow_high_risk_terrain=true
```

This means public low obstacles and rough tile are slow/cross terrain, the
0.45 m center structure is high-risk crawl terrain, and wall-class 0.6 m
features are blocked.

## 10. Joystick And Control Recovery

Stop local autonomy first:

```bash
cd /home/jairlab/go2_ws
ACTION=stop ./scripts/start_saved_map_trg_rl_stack.sh
```

Refresh ROS graph and inspect command topics:

```bash
source /opt/ros/humble/setup.bash
source /home/jairlab/go2_ws/install/setup.bash
export ROS_DOMAIN_ID=88
ros2 daemon stop
ros2 daemon start
ros2 topic info /rl/cmd_vel -v
ros2 topic info /rl/stop -v
```

Recover Sport mode if the robot link is healthy:

```bash
cd /home/jairlab/go2_ws
ACTION=recovery NETWORK_INTERFACE=enp46s0 ./scripts/recover_go2_sport_mode.sh
```

If the LAN interface is down or has no `192.168.123.x` address, treat it as a
connectivity issue before debugging joystick behavior.

## 11. Low-Level RL Track

Do not use low-level RL for the main competition run yet.

Allowed only as a separate experiment:

- harness/off-ground,
- current-hold handoff checked,
- joint order/sign/default posture checked,
- repeated 5-30 cm smoke tests pass without collapse, jump, or red warning.

Current mainline remains Sport backend.
