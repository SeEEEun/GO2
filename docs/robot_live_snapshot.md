# Go2 Live Snapshot

Captured: 2026-06-26 KST. Updated after the current `동아리방` map
sensor-only dry-run at about 11:20 KST.

Scope: read-only diagnostics while the robot was connected over LAN. No motion
command was sent.

## Network

- Wired interface: `enp46s0`, `192.168.123.99/24`.
- Wi-Fi interface: `wlp0s20f3`, `192.168.0.10/24`.
- MID360 candidate IP `192.168.123.20`: ping OK, 0 percent packet loss,
  average round-trip about 1.45 ms in the latest check.
- Go2 candidate IP `192.168.123.161`: ping OK, 0 percent packet loss, average
  round-trip about 3.08 ms in the latest check.

## Unitree SDK Read-Only State

- `rt/lowstate`: received 1503 samples during the short SDK check.
- Latest `rt/lowstate` recheck: 262 samples during a 0.5 second read-only
  snapshot.
- `rt/sportmodestate`: received 596 samples in about 2 seconds.
- `rt/lf/sportmodestate`: received 40 samples in about 2 seconds.
- Sport mode sample:
  - mode: `0`
  - progress: `0.0`
  - position: `[-0.0038, 0.0078, 0.3098]`
  - velocity: `[0.0, 0.0, -0.0]`
- LowState sample:
  - battery SOC: `94`
  - voltage: `31.465 V`
  - IMU quaternion: `[0.99498, 0.0929, -0.037, 0.00344]`
  - IMU RPY rad: `[0.1862, -0.07433, -0.00004]`
  - motor temperatures first 12: `[27, 28, 29, 27, 27, 28, 43, 30, 30, 46, 31, 31]`
- Latest LowState recheck:
  - IMU quaternion `[w,x,y,z]`: `[0.999688, -0.023968, 0.005791, 0.003956]`
  - estimated body tilt: `2.83 deg`
  - largest default-pose mismatches for the legacy low-level RL config were
    rear thigh joints: `0.3360 rad` and `0.2958 rad`.

Operational note: the latest tilt is near level. The default-pose mismatch still
supports the decision to keep low-level RL out of the competition mainline.

## Camera

- Go2 SDK `VideoClient.GetImageSample()` worked on a dedicated retry:
  - return code: `0`
  - JPEG bytes: `165223`
- `icros2026_front_camera_bridge` recheck:
  - `/icros2026/front_camera/status`: `state=OK shape=1920x1080`
  - `/go2/front_camera/image_raw`: `width=1920`, `height=1080`
- A previous combined check returned code `3104` with no image. Treat the camera
  as available but retry/status handling is required. The new front-camera bridge
  should publish status instead of silently assuming an image exists.

## ROS2 Graph

Visible relevant topics included:

- `/sportmodestate`
- `/lf/sportmodestate`
- `/lowstate`
- `/lf/lowstate`
- `/utlidar/cloud`
- `/utlidar/cloud_base`
- `/utlidar/cloud_deskewed`
- `/utlidar/height_map`
- `/utlidar/imu`
- `/utlidar/range_info`
- `/utlidar/robot_pose`
- `/utlidar/robot_odom`
- `/uslam/frontend/odom`
- `/uslam/localization/odom`
- `/uslam/cloud_map`

Verified sample:

- `/utlidar/robot_pose`: one PoseStamped message received in frame `odom`.
- `/utlidar/range_info`: one PointStamped message received:
  point approximately `(0.600, 0.300, 0.250)`.

Not validated in the latest short read-only counter:

- `/utlidar/cloud`
- `/utlidar/cloud_deskewed`
- `/utlidar/height_map`
- `/utlidar/imu`
- `/utlidar/robot_odom`
- `/uslam/frontend/odom`
- `/uslam/localization/odom`
- `/uslam/frontend/cloud_world_ds`
- `/uslam/localization/cloud_world`

Later recheck with the correct ROS2 workspace, CycloneDDS interface pinning, and
`/tmp/MID360_config_livox.json` enabled live LiDAR streams. Built-in UTLiDAR raw
topics sampled in that environment, but FAST-LIO over `/utlidar/cloud` diverged
badly and is rejected for the competition mainline.

## MID360 FAST-LIO Mainline

Current validated mainline:

```text
MID360 -> Livox driver -> FAST-LIO2 -> /cloud_registered + /Odometry
```

Environment used:

```bash
source /opt/ros/humble/setup.bash
source /home/jairlab/go2_ws/install/setup.bash
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export CYCLONEDDS_URI=file:///tmp/cyclonedds_livox.xml
export LIVOX_CONFIG_PATH=/tmp/MID360_config_livox.json
```

Live evidence:

- `/livox/lidar`: about `9.9-10.0 Hz`.
- `/cloud_registered`: about `6.5 Hz`.
- `/Odometry`: about `6.6 Hz`.
- Latest sampled `/Odometry` while stationary:
  - frame: `camera_init`
  - child frame: `body`
  - position about `(0.0047, -0.0045, -0.0051) m`
  - orientation close to identity.
- FAST-LIO config used for live visualization:
  `/home/jairlab/go2_ws/src/FAST_LIO_ROS2/FAST_LIO/config/mid360.yaml`.
  This has `pcd_save_en: false`, so the current visualization run does not
  overwrite raw map files.

Operational note: FAST-LIO logs periodic IMU dt warnings. The odometry remained
near the stationary pose during the short check, but this warning should be
watched during Step 6 sensor-only dry-run.

## Live Height And Traversability Diagnostics

- `height_scan_bridge` is running from `/cloud_registered` + `/Odometry`.
- Latest `/rl/height_scan` sample:
  - cells: `273`
  - valid cells: `48`
  - valid height range: about `-0.379` to `0.191 m`
- `traversability_node` is publishing `/roughnav/terrain_flags`.
- Latest terrain diagnostic sample:
  - `state`: `blocked`
  - `reason`: `grid_blocked_ratio`
  - `unknown_ratio`: about `0.837`
  - `blocked_ratio`: about `0.096`
  - `rough_ratio`: about `0.014`
  - `observed_cells`: about `1177`

Planning note: this traversability diagnostic is intentionally conservative in
the current static room view. Do not use it as a hard movement gate until the
region of interest, unknown handling, and step threshold are tuned against the
course map.

## Visualization

- Current RViz is the sensor-only saved-map/TRG view using:
  `/home/jairlab/go2_ws/src/go2_competition_nav/rviz/map_policy_sim.rviz`.
- Current map config:
  `dongari_room_20260626_v3_traversable_safe`.
- `/cloud_registered` has one FAST-LIO publisher and localization/
  traversability subscriptions.
- `/cloud_registered_map` and `/localized_odometry` are the saved-map
  localization outputs used by TRG and `height_scan_bridge`.
- Current background logs:
  - `/tmp/icros2026_step6_fastlio.log`
  - `/tmp/icros2026_step6_scan_to_map_localizer.log`
  - `/tmp/icros2026_step6_trg_sensor_only.log`
  - `/tmp/icros2026_step6_traversability.log`

## Step 6 Sensor-Only Dry-Run Snapshot

Captured: `2026-06-26 11:20 KST`.

Command:

```bash
cd /home/jairlab/GO2
LOCALIZATION_MAP_PATH=/home/jairlab/go2_ws/maps/dongari_room_20260626_clean_level.pcd \
LOCALIZATION_LEVEL_META=/home/jairlab/go2_ws/maps/dongari_room_20260626_clean_level_meta.json \
VIS_MAP_PATH=/home/jairlab/go2_ws/maps/dongari_room_20260626_planner_source.pcd \
MAP_CONFIG=dongari_room_20260626_v3_traversable_safe \
RVIZ=true \
ACTION=start ./scripts/step6_real_sensor_only_dry_run.sh
```

Configuration:

- MID360: `192.168.123.20`, ping OK.
- Go2: `192.168.123.161`, ping OK.
- Localization map:
  `/home/jairlab/go2_ws/maps/dongari_room_20260626_clean_level.pcd`.
- Localization meta:
  `/home/jairlab/go2_ws/maps/dongari_room_20260626_clean_level_meta.json`.
- RViz visual map:
  `/home/jairlab/go2_ws/maps/dongari_room_20260626_planner_source.pcd`.
- TRG map config:
  `dongari_room_20260626_v3_traversable_safe`.

Live evidence:

```text
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
```

Movement safety:

- `go2_sport_cmd_bridge`, `go2_sdk2_bridge`, `onnx_policy_node`,
  `path_to_cmd_vel`, and low-level command publishers were not started.
- FAST-LIO still prints repeated IMU dt warnings. Treat this as a sensor-only
  pass, not a movement clearance.

## Previous Step 6 Sensor-Only Dry-Run Snapshot

Captured: `2026-06-26 10:37 KST`.

Command:

```bash
cd /home/jairlab/GO2
ACTION=start ./scripts/step6_real_sensor_only_dry_run.sh
```

Configuration:

- MID360: `192.168.123.20`, ping OK.
- Go2: `192.168.123.161`, ping OK.
- Localization map:
  `/home/jairlab/go2_ws/maps/go2_dual_lidar_clean_level.pcd`.
- Localization meta:
  `/home/jairlab/go2_ws/maps/go2_dual_lidar_clean_level_meta.json`.
- RViz visual map:
  `/home/jairlab/go2_ws/maps/go2_dual_lidar_clean_level_detail_surface.pcd`.
- TRG map config:
  `go2_dual_lidar_icros2026_traversable_safe`.
- RViz config:
  `/home/jairlab/go2_ws/src/go2_competition_nav/rviz/map_policy_sim.rviz`.

8 second probe:

```text
/livox/lidar              10.18 Hz
/cloud_registered          5.63 Hz
/cloud_registered_map      0.77 Hz
/Odometry                  5.63 Hz
/localized_odometry        5.59 Hz
/rl/height_scan            0.80 Hz
/roughnav/terrain_flags    5.71 Hz
/rl/cmd_vel                0.00 Hz
raw odom drift             0.0024 m
localized odom drift       0.0037 m
```

Latest localization status:

```json
{"state":"OK","accepted":true,"fitness":1.0,"rmse":0.0,"x":1.982,"y":0.23,"z":0.0,"yaw":0.4434}
```

Latest height scan:

```text
cells=273
valid=44
valid_range=-0.3978 to 0.3331 m
```

Latest traversability diagnostic:

```json
{"state":"blocked","reason":"grid_blocked_ratio","blocked_ratio":0.096,"rough_ratio":0.014,"unknown_ratio":0.84,"max_step_m":3.134,"observed_cells":1153}
```

Planning note: the traversability diagnostic is still too conservative in the
static room view and must be tuned before it becomes a movement gate.

Temporary TRG path probe:

```text
published /goal_pose at map x=2.582, y=0.230
/trg/output/path messages=5
latest path length=2 poses
```

Movement safety evidence:

- `/rl/cmd_vel` publisher count: `0`.
- `go2_sport_cmd_bridge/status`: unknown topic.
- `/lowcmd`: unknown topic.
- `path_to_cmd_vel`, `go2_sport_cmd_bridge`, `go2_sdk2_bridge`, and
  `onnx_policy_node` were not running.

## Current Mapping Snapshot

Captured: `2026-06-26 10:45 KST`.

Reason:

- The Step 6 RViz view was using the previous practice map, not the current
  room/arena layout.
- Switched to pure live FAST-LIO mapping so RViz shows the map being built from
  the currently connected MID360.

Command:

```bash
cd /home/jairlab/GO2
ACTION=start ./scripts/step6_current_mapping.sh
ACTION=save ./scripts/step6_current_mapping.sh
```

Current mapping stack status:

```text
mapping stack stopped after save
current active stack is Step 6 sensor-only localization/TRG/RViz
```

Movement safety:

```text
/rl/cmd_vel: 0 publishers in the latest sensor-only check
go2_sport_cmd_bridge: not started
go2_sdk2_bridge: not started
onnx_policy_node: not started
path_to_cmd_vel: not started
```

Saved initial snapshot:

```text
/home/jairlab/go2_ws/maps/current_mapping/go2_current_fastlio_20260626_104528.pcd
size: 24377179 bytes
points: 761779
fields: x y z intensity normal_x normal_y normal_z curvature
```

Previous same-name saved map backup:

```text
/home/jairlab/go2_ws/maps/current_mapping/동아리방_backup_20260626_110710.pcd
size: 250081725 bytes
points: 7815046
fields: x y z intensity normal_x normal_y normal_z curvature
```

Current saved named map after remapping:

```text
/home/jairlab/go2_ws/maps/current_mapping/동아리방.pcd
saved: 2026-06-26 11:07 KST
size: 44233533 bytes
points: 1382290
fields: x y z intensity normal_x normal_y normal_z curvature
```

Latest symlink:

```text
/home/jairlab/go2_ws/maps/current_mapping/latest_current_fastlio_map.pcd -> /home/jairlab/go2_ws/maps/current_mapping/동아리방.pcd
```

For a competition-ready map, repeat this process on the real course: move the
robot slowly through the whole course, then save with:

```bash
cd /home/jairlab/GO2
ACTION=save_stop ./scripts/step6_current_mapping.sh
```

## ROS2 Message Environment

The currently sourced ROS2 environment did not contain `unitree_go`:

```text
Package not found
Unknown package 'unitree_go'
```

This means ROS2 CLI cannot decode `/lowstate` or `/sportmodestate` until the
Unitree message package is sourced or installed. For now, use the Unitree SDK
path for Go2 state and control readiness checks.

## Local Command Publishers

Filtered process check before Step 4 found no active movement publishers. During
the Step 4 live visualization run, these non-movement processes were active:

```text
rviz2
start_go2_fastlio_mapping.sh
livox_ros_driver2_node
fastlio_mapping
height_scan_bridge
traversability_node
```

`/rl/cmd_vel` was unknown in the live check, which means no local velocity
publisher was present. `path_to_cmd_vel` and `go2_sport_cmd_bridge` were not
running. No Sport or low-level movement command was sent.

## Planning Impact

- Go2 state, joint/IMU/battery telemetry, Sport state, and onboard camera are
  reachable through Unitree SDK on `enp46s0`.
- MID360 network connectivity and MID360 FAST-LIO are good enough to proceed to
  Step 5 offline route rehearsal and Step 6 sensor-only dry-run.
- Go2 network connectivity is now good by ping as well.
- ROS2 Unitree message decoding remains open. Use SDK state or fix/source
  `unitree_go` before relying on ROS2 CLI decoding of Unitree state.
- Real motion should stay blocked until Step 5 offline route rehearsal and Step
  6 sensor-only dry-run pass with the measured semantic/TRG map.
