# GO2 ICROS2026 Competition Hub

Last updated: 2026-06-27 KST

This folder is the lightweight hub for the ICROS2026 quadruped robot challenge.
It does not replace the existing workspaces. Keep code, maps, policies, and
robot bringup logic in their current workspaces, and use this folder for the
final strategy, rules summary, run commands, checkpoints, and progress tracking.

## Final Mainline

The competition mainline is fixed as:

```text
MID360 LiDAR
-> FAST-LIO2 SLAM/localization
-> /cloud_registered + /Odometry
-> local height/elevation scan
-> traversability/risk 판단
-> TRG planner
-> path_to_cmd_vel speed limiting
-> Go2 SportClient high-level velocity command
```

This is the best fit for the current Go2 Edu hardware, the existing mapping
work, TRG-planner, and the rule that fixed movement scripts count as
hardcoding.

## Current Decision

- Division: autonomous driving.
- Main locomotion backend: Go2 Sport mode through high-level velocity commands.
- Main navigation approach: SLAM + height/elevation scan + traversability/risk
  + speed control + TRG.
- Main command path: `TRG path -> path_to_cmd_vel -> /rl/cmd_vel ->
  go2_sport_cmd_bridge -> SportClient.Move()`.
- Low-level RL, torque control, and foothold planning are not part of the
  competition mainline.
- Full elevation mapping packages such as ANYbotics `elevation_mapping` are v2
  candidates. For v1, stabilize the current local height scan and TRG
  traversability path first.
- Folder policy: `/home/jairlab/GO2` is a hub. Do not move
  `/home/jairlab/go2_ws`, `/home/jairlab/Unitree_Go2`, or
  `/home/jairlab/go2_roughnav_ws` under this folder.

## Current Runtime Status

As of 2026-06-27 16:50 KST:

- Preliminary-arena saved-map navigation is the active live test preset.
- The red-arrow RViz issue was traced to the `Body Odometry` display plus a real
  localization stability problem under CPU load. The RViz display is now off by
  default.
- The saved-map localizer is now reduced-load by default:
  `icp_period_s=2.0`, `voxel_size=0.15`, `max_points=3000`, one-thread BLAS.
- `ENABLE_MOTOR_PUBLISH=false` now also keeps `go2_sport_cmd_bridge` from
  launching. In this dry-run mode, TRG and `/rl/cmd_vel` can be verified without
  sending `SportClient.Move()` to the Go2.
- Latest live dry-run on the preliminary-arena map:
  `/Odometry max_step=0.0128 m`, `/localized_odometry max_step=0.0128 m`,
  both with `jumps_gt_5cm=0` over 60 s.
- Synthetic 0.55 m goal produced `/trg/output/path` with 4 poses and nonzero
  `/rl/cmd_vel`; `/rl/cmd_vel` had no Sport bridge subscriber.
- Do not enable real Sport movement until the current RViz pose, saved map,
  localized live cloud, and TRG path visually match.

QR/photo mission status from 2026-06-27 06:53 KST:

- The QR/photo mission pipeline has been migrated into `/home/jairlab/go2_ws`
  under the `go2_competition_nav` package.
- The Go2-mounted USB webcam QR flow succeeded on the real LAN setup, and the
  `go2_ws` synthetic test now passes with `state=DONE`,
  `result=qr_success`, and `motion_commanded=false`.
- One-command QR runner:
  `cd /home/jairlab/go2_ws && ./scripts/start_icros2026_qr_mission_remote.sh test`.
- The next runtime work is the measured semantic map:
  `maps/icros2026_measured_semantic_map.template.yaml` ->
  `maps/icros2026_competition_day1_semantics.yaml`.
- The zone/mission workflow is documented in
  `/home/jairlab/go2_ws/docs/runbooks/ICROS2026_MISSION_ZONE_PIPELINE.md`.

Previous live navigation status from 2026-06-26 15:06 KST:

- The active map preset is `dongari`.
- RViz manual 2D Goal mode is armed with:
  `CONFIRM_CLEAR=true ACTION=manual_start ./scripts/step7_sport_short_goal_smoke.sh`.
- RViz also has a `Publish Point` tool. A clicked `/clicked_point` is converted
  to `/goal_pose` by `rviz_clicked_point_goal_bridge`, then goes through the
  same TRG path guard and Sport auto gate.
- The auto gate keeps `/rl/sport_stop=true` while idle, validates each new TRG
  path, releases Sport movement for at most 6 s, then returns to stop.
- A guarded 2.0 s short-goal smoke test sent SportClient `Move` 40 times and
  measured `odom_delta dxy=0.080 m, dyaw=0.171 rad`.
- A clicked-point smoke test sent SportClient `Move` 120 times and measured
  `odom_delta dxy=0.044 m, dyaw=0.161 rad`.
- `go2_sport_cmd_bridge` now requires a live stop heartbeat. If the gate or
  runner dies, movement closes automatically through `stop_stale=True`.
- `path_to_cmd_vel` now uses p10-p90 robust height statistics for terrain speed
  limiting, so isolated wall/furniture height cells do not force unnecessary
  `high_risk` speed.
- RViz saved-map display uses the same cleaned/leveled map as localization for
  alignment debugging. TRG still uses the separate traversability-safe map.
- Go2 onboard camera is available as `/go2/front_camera/image_raw`, `1920x1080`,
  `bgr8`. No onboard RGB-D/depth topic is available in the current live stack.

## Hardcoding Boundary

Do not use these as competition behavior:

- fixed forward distance, such as "walk forward N meters",
- fixed turn angle, such as "turn N degrees",
- fixed time motion, such as "move left for N seconds",
- fixed zone coordinates guessed from the PDF,
- replayed route scripts,
- blind timed wall-touch motion.

Allowed as safety/control limits:

- maximum velocity,
- timeout guards,
- tilt/slip/stuck thresholds,
- sensor freshness limits,
- map-derived goal tolerance,
- 4-minute pass timing from the rules.

The robot must decide where to go from organizer messages, measured semantic
map data, live localization, TRG, and safety feedback.

## Rules And Mission Interpretation

- The field is a factory inspection style course with four mission zones and a
  central obstacle structure.
- Mission areas are `1.2 m x 1.2 m`.
- Stack-light state is orange or red.
- Mission state comes from organizer ROS2 messages. Camera color recognition is
  useful for verification/evidence, not the only source of truth.
- Example missions from the orientation material:
  - zone 2 orange: touch left wall,
  - zone 2 red: touch right wall,
  - zone 3 orange: take QR/photo on right wall,
  - zone 3 red: take QR/photo on left wall.
- If progress becomes unsafe or repeatedly blocked, use the legal pass strategy
  rather than forcing a damaging obstacle attempt.

## Obstacle Strategy

Treat Sport mode as conditionally capable, not guaranteed.

- Low uneven/crosswalk terrain: candidate for conservative Sport traversal.
- Rough tile: candidate for traversal with height-scan speed limiting.
- 0.2 m bridge entry block: only after centered approach and low-speed test.
- Shaking bridge: require centered corridor, low speed, and lateral drift/roll
  abort checks.
- Central 0.45 m stair/slope cross: high risk. Attempt only after repeated
  practice success; otherwise score partial progress and pass.
- Foot-drop/gap-like terrain: high risk. Sport mode does not plan individual
  footholds, so stop/pass if live sensing or body attitude indicates danger.

## Architecture

### Localization And SLAM

- Use MID360 + FAST-LIO2 as the main SLAM/localization path.
- Use `/cloud_registered` and `/Odometry` as the core planning inputs.
- Reuse previous mapping results for semantic-map and TRG-map creation only
  after frame alignment is checked.
- The previous mapping note in `이전 mapping` is part of Step 5. Keep raw PCD
  maps immutable, build cleaned/TRG maps under new names, use multi-pass
  temporal confidence when possible, preserve low tiles/ramps/rough terrain,
  and validate TRG nodes/edges in RViz before any real movement.
- Current `dongari` preset follows that split:
  `dongari_room_20260626_clean_level.pcd` for saved-map localization,
  `dongari_room_20260626_planner_source.pcd` for visualization/source
  geometry, and `dongari_room_20260626_v3_traversable_safe.pcd` for TRG.

### Terrain Representation

- v1: use `height_scan_bridge` for robot-centric local height/elevation scan.
- v1.5: use `traversability_node` as diagnostic risk map and promote it only if
  it proves useful in live testing.
- `path_to_cmd_vel` publishes `/roughnav/terrain_state` from the front-center
  height scan band for the current speed/stop decision.
- `traversability_node` can optionally publish `/traversability_map` and
  `/roughnav/terrain_flags` as a broader diagnostic grid.
- v2: consider full `elevation_mapping` integration if v1 needs a richer
  elevation map.

### Traversability And Planning

- Use TRG-planner as the main planner.
- TRG should consume point cloud or traversability-aware map inputs, not a
  simple 2D-only obstacle model.
- Mark central stair, shaking bridge, rough tile, and hidden/gap regions in the
  measured semantic map as risk regions.

### Velocity Control

- `path_to_cmd_vel` follows the TRG path and applies speed limits from local
  terrain state.
- In the Sport saved-map stack, `path_to_cmd_vel` also requires
  `/icros2026/localization/status` to be `OK` or `RELOCALIZED` with acceptable
  fitness/RMSE before it can publish nonzero `/rl/cmd_vel`.
- Competition config requires fresh height scan for motion. Missing, stale, or
  mostly unknown front terrain becomes a stop gate instead of a blind drive.
- Expected terrain states:
  - `flat`: normal conservative speed,
  - `approach`: slow down near rough/step terrain,
  - `cross`: very slow, only if traversal gate is satisfied,
  - `high_risk`: crawl over measured competition obstacles such as the central
    0.45 m structure only after practice clearance,
  - `unknown`: slow or stop depending on progress,
  - `blocked`: stop and prepare pass/replan.
- `go2_sport_cmd_bridge` is the only competition movement backend for the
  mainline.

### Mission Handling

- Organizer ROS2 messages must be normalized into:
  - target zone,
  - stack-light color,
  - mission type,
  - side or wall target,
  - deadline/pass state.
- Zone-only goals require a validated measured semantic map.
- Direct organizer `PoseStamped`, `PointStamped`, or XY goals can be forwarded
  because the organizer is providing target geometry directly.
- QR/photo missions use the external USB RGB camera for the current competition
  prep path. The Go2 front camera bridge remains available as a fallback.
- QR recognition has a GO2-local vision node:
  `tools/icros2026_qr_vision_node.py`.
  It uses YOLO only to detect the QR bounding box and OpenCV
  `QRCodeDetector` to decode the actual QR text.
- QR mission completion has a motion-free monitor:
  `tools/icros2026_qr_mission_monitor.py`.
  It listens to mission request JSON and QR vision output, then publishes
  `/icros2026/mission_done` as `std_msgs/Bool` only after QR evidence is
  detected/decoded.
- Detailed QR mission evidence is published on `/icros2026/mission/result`
  and copied under `artifacts/mission_evidence/`.
- Current QR model path:
  `models/qr/best.pt`, copied from `scardonac/qr_code_detection`
  commit `84d38c5c65b6f9e4810114684e369cc1a417485d`.
- QR outputs:
  `/icros2026/vision/qr/status`,
  `/icros2026/vision/qr/result`, and
  `/icros2026/vision/qr/debug_image`.
- QR evidence is saved under `artifacts/qr_evidence/`.
- Wall touch must be guarded by map/odom/range/contact/stall feedback, not blind
  timed movement.

## Current Go2 Snapshot

Latest read-only snapshot is recorded in `docs/robot_live_snapshot.md`.

- PC wired interface: `enp46s0 = 192.168.123.99/24`.
- MID360 candidate IP `192.168.123.20`: ping OK in the latest check.
- Go2 candidate IP `192.168.123.161`: ping OK in the latest check.
- SDK LowState and Go2 front camera were reachable.
- Go2 front camera bridge published `/go2/front_camera/image_raw` at
  `1920x1080`, `bgr8`.
- The onboard camera path is RGB/BGR image-only through Unitree `VideoClient`.
  Use it for QR/photo capture, not depth estimation.
- Step 6 real sensor-only dry-run now passes both on the previous practice map
  and on the current `동아리방` map.
- Saved-map localization now performs automatic coarse initial alignment instead
  of requiring a hand-tuned offset: full yaw search, yaw-dependent translation
  estimate, ICP refinement, and bounded relocalization after repeated rejected
  jumps.
- Sport saved-map movement now requires localization quality in
  `path_to_cmd_vel`: missing, stale, rejected, low-fitness, or high-RMSE
  localization blocks nonzero `/rl/cmd_vel`.
- MID360 + Livox driver + FAST-LIO2 passed the live sensor gate:
  `/livox/lidar` was about 10 Hz, `/cloud_registered` about 5.6 Hz, and
  `/Odometry` about 5.6 Hz in the latest read-only check.
- Current `동아리방` remap was saved and converted into a TRG rehearsal map.
- RViz is currently running the real sensor-only stack with
  `dongari_room_20260626_v3_traversable_safe`, live MID360/FAST-LIO clouds,
  saved-map localization, TRG graph/path topics, and local diagnostics.
- Step 6 RViz now shows two saved-map layers by default:
  `/saved_pcd_map` is the lightweight planner/visual map, and
  `/localization_saved_pcd_map` is the dense saved mapping result used for
  localization. If the existing mapping result looks missing, check the dense
  map display before remapping.
- Step 6 also shows `/cloud_registered_map` as `Localized Live Cloud`. This is
  the topic that must overlap the saved map. If it separates from the saved map,
  treat localization as failed and check `/icros2026/localization/status`
  before any movement.
- Saved-map localization now also supports coarse relocalization after repeated
  ICP metric failures and automatic live-scan z alignment, so large FAST-LIO
  odometry/cloud jumps can be recovered without hand-tuned offsets.
- `height_scan_bridge` is publishing `/rl/height_scan` from
  `/cloud_registered_map` and `/localized_odometry`; latest checks reported
  `273` scan cells.
- `traversability_node` published `/roughnav/terrain_flags`, but current
  diagnostic output is conservative/blocked because unknown ratio is high. Do
  not promote it to a hard movement gate until it is tuned.
- Current-map live sensor-only TRG goal probe produced `/trg/output/path` with
  `24` poses while `/rl/cmd_vel` had `0` publishers.
- Current-environment FAST-LIO mapping is available through
  `scripts/step6_current_mapping.sh`. The current named map is:
  `/home/jairlab/go2_ws/maps/current_mapping/동아리방.pcd`
  with `1382290` points and `44233533` bytes. Mapping remains a
  manual/operator workflow; this script does not start Sport, SDK, policy, or
  `/rl/cmd_vel`.
- Current TRG rehearsal artifacts:
  - raw saved map: `/home/jairlab/go2_ws/maps/current_mapping/동아리방.pcd`,
  - cleaned/leveled map:
    `/home/jairlab/go2_ws/maps/dongari_room_20260626_clean_level.pcd`,
  - planner source:
    `/home/jairlab/go2_ws/maps/dongari_room_20260626_planner_source.pcd`,
  - selected TRG map:
    `/home/jairlab/go2_ws/maps/dongari_room_20260626_v3_traversable_safe.pcd`,
  - selected TRG config:
    `/home/jairlab/go2_ws/src/TRG-planner/config/dongari_room_20260626_v3_traversable_safe.yaml`.
- The first direct ICROS profile TRG build produced only `1` walkable cell and
  is not the selected map. The v3 build produced `859` walkable cells, TRG graph
  initialization passed, and a test goal generated a `12`-pose
  `/trg/output/path` while `/rl/cmd_vel` had `0` publishers.
- Built-in `/utlidar/*` topics exist and can sample in the correct ROS2/DDS
  environment, but FAST-LIO over `/utlidar/cloud` diverged and is not the
  competition mainline.
- The currently sourced ROS2 environment did not contain `unitree_go` message
  definitions. Use SDK state path or fix/source the message package before
  relying on ROS2 CLI for Go2 state topics.

## Current Implemented Artifacts

- `docs/semantic_map_contract.md`: measured semantic-map contract.
- `templates/icros2026_semantic_map.template.yaml`: semantic-map template.
- `tools/validate_icros2026_semantic_map.py`: semantic-map validator.
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/go2_roughnav/icros2026_goal_adapter.py`:
  forwards direct organizer pose/point/XY goals and refuses zone-only goals
  unless a measured semantic map with all four zones is configured.
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/go2_roughnav/icros2026_front_camera_bridge.py`:
  publishes the Go2 onboard front camera for QR/photo missions.
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/go2_roughnav/icros2026_mission_normalizer.py`:
  normalizes organizer String/JSON/key-value/std_msgs mission inputs into
  target zone, color, mission type, side/wall, deadline, and executor mode.
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/go2_roughnav/icros2026_mission_executor.py`:
  consumes normalized JSON in `auto` mode and defaults photo missions to
  `/go2/front_camera/image_raw`.
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/go2_roughnav/height_scan_bridge.py`:
  builds the local height/elevation scan from cloud + odometry.
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/go2_roughnav/traversability_node.py`:
  builds a local traversability diagnostic grid from point clouds and publishes
  JSON terrain flags.
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/go2_roughnav/path_to_cmd_vel.py`:
  tracks TRG path, publishes `/roughnav/terrain_state`, and applies height-scan
  speed limiting, localization quality gating, high-risk crawl, or
  blocked-terrain stop gates.
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/go2_roughnav/go2_sport_cmd_bridge.py`:
  converts `/rl/cmd_vel` to Unitree SportClient movement commands.
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/launch/06_real_go2_pipeline.launch.py`:
  accepts `arena_semantics_path`, `launch_front_camera_bridge`,
  `launch_mission_normalizer`, `launch_mission_executor`, and
  `launch_traversability`.
- `scripts/step6_current_mapping.sh`: stops old localization/TRG visual
  stacks, starts current-environment MID360 FAST-LIO mapping with RViz, and
  saves timestamped PCD snapshots under
  `/home/jairlab/go2_ws/maps/current_mapping/`.

## Step-by-Step Roadmap

### Step 1: Non-Hardcoded Goal Contract

Status: completed.

- Use measured semantic map contract, template, and validator.
- If `arena_semantics_path` is empty, zone-only goals must not move the robot.
- Keep Go2 front-camera bridge for QR/photo missions.

### Step 2: Mission Message Normalizer

Status: completed initial implementation.

- Convert organizer messages into target zone, color, mission type, side/wall,
  and deadline/pass fields.
- Support expected String/JSON/key-value messages first, then typed messages
  through std_msgs topics while waiting for the organizer package.
- Treat organizer ROS2 message as primary truth for orange/red.
- Use camera only for verification/evidence.
- QR/photo missions are forwarded to the current executor.
- Wall-touch missions are normalized but not forwarded to the executor by
  default because guarded wall-touch execution is a later step.

### Step 3: Terrain Risk Layer

Status: completed initial implementation. Live threshold tuning is still
required.

- `path_to_cmd_vel` now publishes `/roughnav/terrain_state` JSON with state,
  speed scale, reason, valid cells, unknown ratio, max height, and roughness.
- Height scan is required for motion in the competition config.
- `blocked` terrain stops motion through `/rl/controller_stop`.
- `traversability_node` remains diagnostic-first and publishes structured JSON
  flags on `/roughnav/terrain_flags`.
- Promote traversability output to planner/monitor input only after live checks.
- Publish simple terrain states: `flat`, `approach`, `cross`, `high_risk`,
  `unknown`, `blocked`.
- Current obstacle thresholds are documented in
  `docs/icros2026_runtime_profile.md`. In short, about 5 cm starts slow-down,
  about 15 cm is rough-terrain crossing, above 30 cm is high-risk crawl, and
  about 55 cm or more is treated as wall/drop blocked terrain.

### Step 4: Live Sensor Gate

Status: completed for the MID360 mainline. Keep tuning open for diagnostic
traversability thresholds and ROS2 Unitree message sourcing.

- Use MID360 `/livox/lidar` + `/livox/imu` through FAST-LIO2 for
  `/cloud_registered` and `/Odometry`.
- Latest MID360 live check passed with `/livox/lidar`, `/cloud_registered`,
  `/Odometry`, `/rl/height_scan`, `/roughnav/terrain_flags`, and RViz
  visualization active.
- Built-in UTLiDAR FAST-LIO is rejected for the mainline because the tested
  odometry diverged badly.
- Fix/source `unitree_go` messages or deliberately keep Go2 state on SDK path.
- Do not allow movement if cloud, odometry, height scan, or safety status is
  stale.

### Step 4.5: Current / Competition Pre-Mapping

Status: completed for the current `동아리방` practice remap.

- For the real competition, do this before route rehearsal:
  1. run pure MID360 FAST-LIO mapping,
  2. move the robot slowly through the course manually/operator-controlled,
  3. save the raw PCD,
  4. make a cleaned/leveled map,
  5. derive measured semantic map and TRG traversability map,
  6. run Step 5 and Step 6 against that measured map.
- Added repeatable wrapper:
  `scripts/step6_current_mapping.sh`.
- Current saved map:
  - raw map:
    `/home/jairlab/go2_ws/maps/current_mapping/동아리방.pcd`
  - saved at about `2026-06-26 11:07 KST`
  - points: `1382290`
  - size: `44233533` bytes
  - previous same-name map backup:
    `/home/jairlab/go2_ws/maps/current_mapping/동아리방_backup_20260626_110710.pcd`

### Step 5: Offline Route Rehearsal

Status: reference route contract passed. Previous practice-map rebuild passed.
Current `동아리방` map TRG visualization/path rehearsal also passed. Final
measured competition-course rehearsal is still pending.

- Publish Route A/B/C through semantic-map zone goals.
- Confirm TRG path reaches each mission zone.
- Confirm central stair and hidden/gap regions are risk-marked.
- Define pass conditions before real obstacle tests.
- Reuse the previous mapping workflow from `이전 mapping`: immutable raw maps,
  cleaned planner maps, multi-pass temporal confidence, robust upper-percentile
  cell height, low-terrain preservation, and RViz validation of TRG nodes/edges.
- Added reference-only semantic map:
  `maps/icros2026_reference_semantic_map.yaml`.
- Added repeatable wrapper:
  `scripts/step5_reference_rehearsal.sh`.
- Route A/B/C contract passed in the reference map: zone-only messages resolved
  through the semantic map, snapped goals were generated, and `/trg/output/path`
  was non-empty for every route step.
- Previous mapping was reused through
  `/home/jairlab/go2_ws/maps/go2_dual_lidar_clean_level_detail_surface.pcd`;
  `./scripts/rebuild_icros2026_trg_maps.sh practice` regenerated
  `go2_dual_lidar_icros2026_traversable_safe.pcd` with `3113` walkable cells.
- Current `동아리방` map rehearsal:
  - `dongari_room_20260626_traversable_safe`: failed candidate,
    `walkable_cells=1`,
  - `dongari_room_20260626_v2_traversable_safe`: usable visual candidate,
    `walkable_cells=193`,
  - `dongari_room_20260626_v3_traversable_safe`: selected current candidate,
    `walkable_cells=859`, prebuilt graph `nodes=859`, `edges=6306`,
  - start pose fixed to `(0.187, -0.325)` inside the safe grid,
  - test goal around `(0.937, -3.276)` generated a `12`-pose
    `/trg/output/path`,
  - `/rl/cmd_vel` had `0` publishers, so this remains visualization/rehearsal
    only.

### Step 6: Real Go2 Sensor-Only Dry Run

Status: completed for the previous-mapping practice stack and for the current
`동아리방` map. Re-run after the measured competition-course map is built.

- Run FAST-LIO2/localization/TRG/height scan with no Sport movement.
- Confirm freshness of cloud, odometry, path, height scan, and safety topics.
- Stop if any required input is stale or frame alignment is wrong.
- Added repeatable wrapper:
  `scripts/step6_real_sensor_only_dry_run.sh`.
- Latest Step 6 probe on `동아리방` map:
  - `/livox/lidar`: sampled around `7-9 Hz`
  - `/cloud_registered`: sampled around `9-10 Hz`
  - `/Odometry`: sampled around `8-10 Hz`
  - `/localized_odometry`: sampled around `9-10 Hz`
  - `/cloud_registered_map`: fresh
  - `/rl/height_scan`: fresh, `273` scan cells
  - TRG graph initialized on `dongari_room_20260626_v3_traversable_safe`
  - test goal around `(0.937, -3.276)` generated a `24`-pose
    `/trg/output/path`
  - `/rl/cmd_vel`: `0` publishers
  - `go2_sport_cmd_bridge`, `go2_sdk2_bridge`, `onnx_policy_node`,
    `path_to_cmd_vel`, and low-level command publishers were not running.
  - FAST-LIO still prints IMU dt warnings, so this is a sensor-only pass, not a
    movement clearance.
  - saved-map localization is now configured for repeated ICP correction by
    default instead of one-time freeze, with bounded update jumps.
  - after adding automatic initial alignment, `/icros2026/localization/status`
    returned `state=OK`, `fitness` about `1.0`, and `rmse` about `0.04 m` on the
    current `동아리방` sensor-only stack.

### Step 7: Sport Short-Goal Smoke

Status: active on current `dongari` map.

- Test only short 0.3-0.5 m goals first.
- Confirm bounded `/rl/cmd_vel`, SportClient response, stop topic, and joystick
  recovery.
- Do not enter obstacles before this passes.
- Use the `dongari` preset for current-map practice:

```bash
cd /home/jairlab/GO2
ACTION=start ./scripts/step7_sport_short_goal_smoke.sh
```

The safe waiting stack keeps RViz/TRG/Sport bridge up for inspection. It does
not arm RViz manual goal movement:

Scripted short-goal movement requires an explicit clear-floor confirmation:

```bash
cd /home/jairlab/GO2
CONFIRM_CLEAR=true ACTION=run ./scripts/step7_sport_short_goal_smoke.sh
```

For manual RViz 2D Goal testing, use the separate manual mode. This starts the
same saved-map localization and TRG path chain, but arms the RViz goal auto gate
so one short clicked goal can release `/rl/sport_stop` and then automatically
return to stop:

```bash
cd /home/jairlab/GO2
CONFIRM_CLEAR=true ACTION=manual_start ./scripts/step7_sport_short_goal_smoke.sh
```

Expected 2D Goal chain:

```text
RViz 2D Goal Pose
-> /goal_pose
-> goal_snapper
-> /trg/input/snapped_goal_pose
-> /trg/output/path
-> path_to_cmd_vel
-> /rl/cmd_vel
-> go2_sport_cmd_bridge
-> SportClient.Move()
```

In RViz, `TRG Path` and `Snapped Goal` are enabled by default in
`/home/jairlab/go2_ws/artifacts/rviz/real_saved_map_policy.rviz`.

### Step 8: Obstacle Gate Test

Status: planned.

- Test low uneven terrain and rough tile first.
- Test 0.2 m bridge entry only with aligned low-speed approach.
- Treat central 0.45 m stair/slope as high-risk until repeated success.
- Treat foot-drop/gap terrain as stop/pass unless live sensing proves a safe
  path.

## Primary Commands

Validate a measured semantic map:

```bash
cd /home/jairlab/GO2
python3 tools/validate_icros2026_semantic_map.py path/to/icros2026_semantic_map.yaml
```

Expected behavior: the template fails validation until all measured values are
filled in.

```bash
cd /home/jairlab/GO2
python3 tools/validate_icros2026_semantic_map.py templates/icros2026_semantic_map.template.yaml
```

Readiness audit:

```bash
cd /home/jairlab/go2_ws
PRESET=practice MODE=presport ./scripts/icros2026_readiness_audit.sh
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

MID360 live visualization can be opened with:

```bash
rviz2 -d /home/jairlab/go2_ws/src/FAST_LIO_ROS2/FAST_LIO/rviz_cfg/fastlio.rviz
```

Current-environment mapping with RViz:

```bash
cd /home/jairlab/GO2
ACTION=start ./scripts/step6_current_mapping.sh
```

Save a snapshot while mapping continues:

```bash
cd /home/jairlab/GO2
ACTION=save ./scripts/step6_current_mapping.sh
```

Save and stop mapping:

```bash
cd /home/jairlab/GO2
ACTION=save_stop ./scripts/step6_current_mapping.sh
```

Offline route/TRG rehearsal:

```bash
cd /home/jairlab/GO2
ROUTE_CARD=A ACTION=start ./scripts/step5_reference_rehearsal.sh
```

Stop offline rehearsal:

```bash
cd /home/jairlab/GO2
ACTION=stop ./scripts/step5_reference_rehearsal.sh
```

Real sensor/localization dry-run without movement:

```bash
cd /home/jairlab/GO2
ACTION=start ./scripts/step6_real_sensor_only_dry_run.sh
```

Stop the sensor-only dry-run:

```bash
cd /home/jairlab/GO2
ACTION=stop ./scripts/step6_real_sensor_only_dry_run.sh
```

Launch real pipeline with measured semantic map:

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

Current `동아리방` Sport stack:

```bash
cd /home/jairlab/go2_ws
CONTROL_BACKEND=sport ./scripts/start_saved_map_trg_rl_stack.sh dongari
```

Route-card rehearsal only, not the real match:

```bash
cd /home/jairlab/go2_ws
CONTROL_BACKEND=sport \
ARENA_SEMANTICS_PATH=/absolute/path/to/icros2026_semantic_map.yaml \
LAUNCH_GOAL_ADAPTER=true \
LAUNCH_ROUTE_SEQUENCER=true \
ROUTE_CARD=A \
./scripts/start_saved_map_trg_rl_stack.sh dongari
```

Stop the real stack:

```bash
cd /home/jairlab/go2_ws
ACTION=stop ./scripts/start_saved_map_trg_rl_stack.sh
```

Run QR vision only:

```bash
cd /home/jairlab/GO2
./scripts/start_qr_vision.sh
```

Run QR vision and also start the Go2 front-camera bridge:

```bash
cd /home/jairlab/GO2
LAUNCH_GO2_FRONT_CAMERA_BRIDGE=true ./scripts/start_qr_vision.sh
```

Run QR vision from the external USB camera, not the laptop camera:

```bash
cd /home/jairlab/GO2
./scripts/start_usb_camera_qr_vision.sh
```

Run the full Go2-off QR mission pipeline:

```bash
cd /home/jairlab/GO2
./scripts/start_usb_camera_qr_mission.sh
```

Run the no-camera synthetic end-to-end test:

```bash
cd /home/jairlab/GO2
./scripts/test_qr_mission_synthetic.sh
```

Send a mock zone-3 orange QR/photo mission:

```bash
cd /home/jairlab/GO2
./scripts/mock_qr_photo_mission.sh
```

QR mission details are in `docs/qr_mission_pipeline.md`.

The external USB camera is selected by stable V4L ID first:
`/dev/v4l/by-id/usb-LX-240924-XH_GENERAL_WEBCAM-video-index0`.
Do not depend on `/dev/videoN`; the number can change after reconnecting.

Check for stale local command publishers:

```bash
pgrep -af 'go2_sport_cmd_bridge|go2_sdk2_bridge|onnx_policy_node|path_to_cmd_vel|trg_ros2_node|deploy_go2_icros|lowcmd|ros2 launch|ros2 run'
```

## Documents

- `docs/rules_summary.md`: rules, scoring, routes, and mission summary.
- `docs/autonomy_directions.md`: strategy alternatives and final choice.
- `docs/current_runbook.md`: execution order, safety gates, and recovery.
- `docs/non_hardcoded_obstacle_strategy.md`: hardcoding boundary and obstacle
  feasibility.
- `docs/icros2026_runtime_profile.md`: map-error compensation, random route
  message flow, obstacle thresholds, and launch profiles.
- `docs/semantic_map_contract.md`: measured semantic-map schema and validation.
- `docs/robot_live_snapshot.md`: latest read-only Go2/LiDAR/camera snapshot.
- `docs/progress_log.md`: append-only change and experiment history.
- `workspace_manifest.yaml`: fixed paths to workspaces, scripts, maps, and
  runtime nodes.

## Source Notes

- FAST-LIO2: https://arxiv.org/abs/2107.06829
- ANYbotics elevation mapping: https://github.com/anybotics/elevation_mapping
- TRG-planner paper: https://arxiv.org/abs/2501.01806
- TRG-planner project: https://trg-planner.github.io/
- Foothold/costmap planning reference:
  https://cmastalli.github.io/publications/locomotion20tro.html

## Immediate Next Actions

1. Run manual RViz 2D Goal mode on a short clear-floor goal and verify
   `/trg/output/path`, `/rl/cmd_vel`, and automatic stop behavior.
2. Create the measured semantic map for the current `동아리방` map or the final
   competition map: zones, walls, QR/photo sides, and risk regions.
3. Build competition maps with the `이전 mapping` contract: raw map immutable,
   cleaned localization map, planner source map, TRG safe map, obstacle mask,
   and RViz path/edge validation.
4. Tune the traversability diagnostic so unknown/static-room cells do not
   falsely dominate the state before it becomes a movement gate.
5. Source/install `unitree_go` ROS2 messages or keep Go2 state on the SDK bridge
   path deliberately.
6. Re-run Step 5 and Step 6 against the final measured competition semantic/TRG
   map before any obstacle entry.

## Update Rule

When code, maps, parameters, or experiment results change, append a dated entry
to `docs/progress_log.md` and update only the affected section of this hub.
