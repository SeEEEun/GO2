# Progress Log

This file is append-only. Do not rewrite old entries unless correcting a clear
typo. Add new entries at the top of the log section or directly below the
latest date.

## 2026-06-27 16:50 KST

Context:
- RViz showed many red odometry arrows and the Go2 appeared to float or
  teleport while the real saved-map navigation stack was running.
- The visual arrows were from the RViz `Body Odometry` display, but the runtime
  issue was real: FAST-LIO odometry had previously jumped under load and the
  old scan-to-map localizer settings consumed excessive CPU.

Files changed in `/home/jairlab/go2_ws`:
- `scripts/start_saved_map_trg_rl_stack.sh`
- `scripts/start_preliminary_arena_saved_map_sport_nav.sh`
- `artifacts/rviz/real_saved_map_policy.rviz`

Runtime changes:
- Disabled noisy RViz TF axes, `Body Odometry`, and snapped-goal marker displays
  by default in the real saved-map RViz config.
- Reduced saved-map localizer load:
  `icp_period_s=2.0`, `voxel_size=0.15`, `max_points=3000`,
  `coarse_yaw_search_deg=120`, `coarse_yaw_step_deg=20`, and one-thread BLAS
  environment.
- Added `LAUNCH_SPORT_CMD_BRIDGE`; when `ENABLE_MOTOR_PUBLISH=false`, the
  stack still generates TRG paths and `/rl/cmd_vel` but does not start
  `go2_sport_cmd_bridge`.
- Updated the preliminary-arena wrapper to use the same reduced localizer
  defaults and to avoid global XY search by default.

Verification:
- FAST-LIO-only `/Odometry` probe: 20 s, `max_step=0.0066 m`,
  `jumps_gt_5cm=0`.
- FAST-LIO + optimized localizer probe: 60 s, `/Odometry max_step=0.0128 m`,
  `/localized_odometry max_step=0.0128 m`, both with `jumps_gt_5cm=0`.
- Full preliminary-arena stack with `ENABLE_MOTOR_PUBLISH=false`:
  localization state `OK`, TRG input `/cloud_registered_map`,
  TRG odom `/localized_odometry`, frame `map`.
- Small synthetic goal produced `PATH_POSES=4` and `/rl/cmd_vel`
  `NONZERO=119`, with no `go2_sport_cmd_bridge` subscriber.
- `map -> base` TF was stable around `z=-0.700`, placing the robot on the
  prebuilt TRG floor reference rather than the raw live cloud height.
- Full stack follow-up stability probe: 30 s, `/Odometry max_step=0.0120 m`,
  `/localized_odometry max_step=0.0120 m`, both with `jumps_gt_5cm=0`.

Next:
- If RViz still looks cluttered, close old RViz windows and use the relaunched
  `real_saved_map_policy.rviz`.
- For real walking, keep `ENABLE_MOTOR_PUBLISH=false` until a human confirms
  the live map/localized pose/path are correct, then restart with explicit
  movement enablement.
- Next live step is a short Sport goal only after localization stays stable and
  the robot pose visually matches the saved preliminary-arena map.

Rollback:
- Revert the three listed `/home/jairlab/go2_ws` files to restore the previous
  RViz and localizer behavior.

## 2026-06-27 06:53 KST

Context:
- Migrated the successful QR/photo mission pipeline from `/home/jairlab/GO2`
  into `/home/jairlab/go2_ws`.
- Added the missing bridge between the ICROS course concept and runtime:
  measured semantic map, route zones, QR/photo action, and motor-off dry-run
  workflow.

Files changed in `/home/jairlab/go2_ws`:
- `src/go2_competition_nav/go2_competition_nav/icros2026_mission_normalizer.py`
- `src/go2_competition_nav/go2_competition_nav/icros2026_qr_vision_node.py`
- `src/go2_competition_nav/go2_competition_nav/icros2026_qr_mission_monitor.py`
- `src/go2_competition_nav/go2_competition_nav/usb_camera_image_publisher.py`
- `src/go2_competition_nav/go2_competition_nav/publish_synthetic_qr_image.py`
- `src/go2_competition_nav/go2_competition_nav/wait_for_topic_once.py`
- `src/go2_competition_nav/go2_competition_nav/validate_icros2026_semantic_map.py`
- `src/go2_competition_nav/models/qr_best.pt`
- `scripts/start_icros2026_qr_mission_remote.sh`
- `scripts/mock_icros2026_qr_photo_mission.sh`
- `scripts/test_icros2026_qr_mission_synthetic.sh`
- `maps/icros2026_measured_semantic_map.template.yaml`
- `maps/icros2026_reference_semantic_map.yaml`
- `docs/runbooks/ICROS2026_MISSION_ZONE_PIPELINE.md`

Verification:
- `colcon build --packages-select go2_competition_nav --symlink-install`
  passed.
- Python syntax checks passed for the migrated QR and semantic-map nodes.
- `ros2 run go2_competition_nav validate_icros2026_semantic_map
  maps/icros2026_reference_semantic_map.yaml` passed.
- `./scripts/test_icros2026_qr_mission_synthetic.sh` passed with:
  `state=DONE`, `result=qr_success`,
  `decoded_text=ICROS2026_SYNTHETIC_QR`, and `motion_commanded=false`.

Next:
- Fill a measured semantic map after actual course mapping.
- Run motor-off saved-map localization + TRG + `/rl/cmd_vel` dry-run.
- Add a mission coordinator that waits for zone arrival before arming QR/photo
  or wall-touch actions.
- Implement guarded wall-touch; do not use blind timed movement.

Rollback:
- Remove or revert the listed `/home/jairlab/go2_ws` files if the QR/semantic
  mission pipeline is replaced.

## 2026-06-27 05:55 KST

Context:
- User clarified that the QR/photo mission needs the full pipeline, not only a
  detector: organizer mission input, QR recognition, photo/evidence capture,
  and mission completion output.
- `/icros2026/mission_done` must remain compatible with the existing roughnav
  stack, which expects `std_msgs/Bool`.

Files changed:
- `tools/icros2026_mission_normalizer.py`
- `tools/icros2026_qr_mission_monitor.py`
- `tools/icros2026_qr_vision_node.py`
- `tools/publish_synthetic_qr_image.py`
- `tools/wait_for_topic_once.py`
- `scripts/start_usb_camera_qr_mission.sh`
- `scripts/mock_qr_photo_mission.sh`
- `scripts/test_qr_mission_synthetic.sh`
- `docs/qr_mission_pipeline.md`
- `README.md`
- `workspace_manifest.yaml`
- `docs/progress_log.md`

Result:
- Added a GO2-local mission normalizer for organizer mission messages.
- The full QR pipeline now starts:
  USB camera -> QR YOLO/OpenCV decoder -> mission normalizer -> QR mission
  monitor.
- QR/photo missions publish `/icros2026/mission_done` as `std_msgs/Bool true`.
- Detailed JSON evidence is published on `/icros2026/mission/result`.
- Raw/debug/crop/metadata evidence is copied into
  `artifacts/mission_evidence/<timestamp>_<mission_id>/`.
- Added a synthetic QR image publisher and an end-to-end test that does not
  require a physical camera.

Verification:
- Python compile passed for the mission normalizer, QR monitor, QR vision node,
  synthetic QR publisher, wait helper, USB camera publisher.
- Bash syntax check passed for QR mission scripts.
- Synthetic end-to-end test passed:
  - organizer raw mission was normalized into a zone 3 orange/right QR mission,
  - YOLO detected the generated QR with confidence about `0.925`,
  - OpenCV decoded `ICROS2026_SYNTHETIC_QR`,
  - `/icros2026/mission_done` published `data: true`,
  - `/icros2026/mission/result` published `result: qr_success`,
  - mission evidence was copied under
    `artifacts/mission_evidence/20260627_055430_synthetic_qr_20260627_055425/`.

Next:
- Attach the external webcam and run:
  `ROS_DOMAIN_ID=88 ./scripts/start_usb_camera_qr_mission.sh`.
- Send a test mission with:
  `ROS_DOMAIN_ID=88 ./scripts/mock_qr_photo_mission.sh`.
- Show a real QR code to the webcam and confirm the same mission done/result
  topics update.

Rollback:
- Remove the added mission normalizer, synthetic test tools/scripts, and the
  matching README/manifest/runbook/log entries. Revert QR monitor to String
  mission-done only if the rest of the navigation stack is also changed to
  consume String, which is not recommended.

## 2026-06-27 KST

Context:
- User wants to prepare QR/photo mission handling before turning on the real
  Go2 again.
- The next navigation stage is remembered separately as real Go2 motor-off
  FAST-LIO live cloud + saved-map localization + TRG path + `/rl/cmd_vel`
  verification, with no Sport movement.
- The QR mission path should use the external USB RGB webcam and the existing
  `models/qr/best.pt` YOLO QR detector.

Files changed:
- `tools/icros2026_qr_mission_monitor.py`
- `scripts/start_usb_camera_qr_mission.sh`
- `scripts/mock_qr_photo_mission.sh`
- `docs/qr_mission_pipeline.md`
- `README.md`
- `workspace_manifest.yaml`
- `docs/progress_log.md`

Result:
- Added a motion-free QR mission monitor.
- It subscribes to `/icros2026/mission/request`,
  `/icros2026/mission/normalized`, and `/icros2026/vision/qr/result`.
- It publishes `/icros2026/mission/status`,
  `/icros2026/mission_done`, and `/icros2026/mission/qr_evidence` as
  `std_msgs/String` JSON.
- It infers the orientation example for zone 3 only when side is not already
  provided: orange -> right wall QR/photo, red -> left wall QR/photo.
- Added a single launch script for USB camera + QR vision + QR mission monitor.
- Added a mock QR/photo mission publisher for Go2-off testing.

Next:
- With the external webcam attached, run:
  `ROS_DOMAIN_ID=88 ./scripts/start_usb_camera_qr_mission.sh`.
- In another terminal, run:
  `ROS_DOMAIN_ID=88 ./scripts/mock_qr_photo_mission.sh`.
- Show a QR code to the camera and confirm `/icros2026/mission_done` publishes
  a `qr_success` result.

Rollback:
- Remove the new QR mission monitor, the two scripts, the QR mission runbook,
  and the matching README/manifest/log entries.

## 2026-06-26 21:07 KST

Context:
- User connected an external USB RGB camera and clarified that the laptop
  Chicony camera must not be used for the QR mission.
- Live V4L inspection showed the external camera as `GENERAL WEBCAM`; its
  `/dev/videoN` number can change, so selection should use `/dev/v4l/by-id`.

Files changed:
- `tools/usb_camera_image_publisher.py`
- `scripts/start_usb_camera_qr_vision.sh`
- `README.md`
- `workspace_manifest.yaml`
- `docs/progress_log.md`

Result:
- Added an OpenCV-based ROS2 Image publisher for the external USB camera.
- The default stable device is
  `/dev/v4l/by-id/usb-LX-240924-XH_GENERAL_WEBCAM-video-index0`.
- The publisher outputs `/go2/usb_camera/image_raw` as `bgr8`.
- QR vision can now be launched from this external camera with
  `./scripts/start_usb_camera_qr_vision.sh`.

Verification:
- OpenCV captured a 1280x720 frame from the external camera.
- ROS2 test on an isolated domain received `/go2/usb_camera/image_raw` with
  width `1280`, height `720`, encoding `bgr8`.
- QR node subscribed to the external camera topic and published
  `/icros2026/vision/qr/status` with state `NO_QR`, confirming that frames are
  reaching the detector.

Rollback:
- Remove the USB camera publisher/script and the README/manifest/log entries.

## 2026-06-26 20:55 KST

Context:
- User decided to implement QR recognition directly inside the GO2 hub repo.
- The QR mission needs the robot to look at the correct wall, detect the QR
  code in the Go2 camera image, decode it, and save evidence.

Files changed:
- `models/qr/best.pt`
- `tools/icros2026_qr_vision_node.py`
- `scripts/start_qr_vision.sh`
- `README.md`
- `workspace_manifest.yaml`
- `docs/progress_log.md`

Result:
- Added a GO2-local ROS2 QR vision node.
- The node subscribes to `/go2/front_camera/image_raw` by default.
- It uses the YOLO QR detector from `scardonac/qr_code_detection`
  commit `84d38c5c65b6f9e4810114684e369cc1a417485d`.
- YOLO is used only for QR bounding-box detection; OpenCV
  `QRCodeDetector` decodes the actual QR text.
- The node publishes `/icros2026/vision/qr/status`,
  `/icros2026/vision/qr/result`, and `/icros2026/vision/qr/debug_image`.
- Evidence images and metadata are saved under
  `/home/jairlab/GO2/artifacts/qr_evidence`.

Next:
- Run `./scripts/start_qr_vision.sh` while a camera publisher is active.
- If using the Go2 onboard camera, run
  `LAUNCH_GO2_FRONT_CAMERA_BRIDGE=true ./scripts/start_qr_vision.sh`.
- Integrate successful QR decode results into the mission executor after the
  vision node is validated live.

Rollback:
- Remove the added QR model, tool, script, and the README/manifest/log entries.

## 2026-06-26 16:07 KST

Context:
- User reported a roof-like surface above the RViz map.
- Inspection showed the v11 TRG safe map max z is about `0.84 m`, while the
  visual planner source still contains high residual points up to about
  `1.14 m`.

Files changed:
- `/home/jairlab/go2_ws/src/go2_competition_nav/launch/map_policy_sim.launch.py`
- `/home/jairlab/go2_ws/src/go2_competition_nav/rviz/map_policy_sim.rviz`
- `/home/jairlab/go2_ws/scripts/start_map_policy_sim.sh`
- `/home/jairlab/go2_ws/scripts/run_clubroom_climbable_trg_sim.sh`
- `docs/progress_log.md`

Result:
- Added `mesh_z_min` and `mesh_z_max` launch arguments.
- Passed `MESH_Z_MIN` and `MESH_Z_MAX` through `start_map_policy_sim.sh`.
- Added `SAVED_PCD_MAP` control to `start_map_policy_sim.sh`.
- Limited the clubroom v11 RViz mesh to `z=-0.75..0.95 m`.
- Reduced mesh hole filling/smoothing from `3/2` to `1/1` for the clubroom v11
  wrapper.
- Disabled the raw `/saved_pcd_map` display by default in the clubroom v11
  wrapper so upper residual points do not look like a roof.
- Disabled the `Flat-filled Saved PCD` display in the RViz config.
- Rebuilt `go2_competition_nav`.
- Relaunched the v11 TRG sim and verified:
  `/saved_map_mesh z_range=(-0.75,0.95)`,
  `/trg/output/path` exists, and `go2_sdk2_bridge publish=False`.

Next:
- Use RViz to confirm the roof-like mesh artifact is removed.
- If the view still shows too much upper clutter, lower `MESH_Z_MAX` slightly
  or disable only the `Saved Map Mesh` RViz display.

Rollback:
- Set `MESH_Z_MIN=-inf`, `MESH_Z_MAX=inf`, `MESH_FILL_HOLES=3`,
  `MESH_SMOOTH_ITERS=2` when running
  `/home/jairlab/go2_ws/scripts/run_clubroom_climbable_trg_sim.sh`.
- Set `SAVED_PCD_MAP=true` to show the raw `/saved_pcd_map` again.

## 2026-06-26 15:55 KST

Context:
- User reported that RViz goal pose did not move and that the displayed map
  looked like clubroom and rough-terrain maps were mixed.

Files changed:
- `/home/jairlab/go2_ws/src/go2_competition_nav/launch/map_policy_sim.launch.py`
- `/home/jairlab/go2_ws/scripts/run_clubroom_climbable_trg_sim.sh`
- `docs/progress_log.md`

Result:
- Confirmed the previous run used
  `clubroom_existing_results_v12d_climbable_traversable`, which is an optional
  rough/climbable experiment map and can look mixed.
- Changed `run_clubroom_climbable_trg_sim.sh` defaults to the documented
  `clubroom_temporal_no_person_v11` map set.
- Disabled `require_localization_ok` inside `map_policy_sim.launch.py` only for
  simulation, because this sim stack has no real localization-status publisher.
- Rebuilt `go2_competition_nav`.
- Relaunched the v11 TRG sim and verified RViz goal motion:
  `/Odometry` advanced from the start pose and later stopped with
  `reason=endpoint_reached`.
- Verified this is still safe simulation/dry-run:
  `go2_sdk2_bridge state=DRY_STOP_HOLD; publish=False`.

Next:
- Use this v11 sim for RViz/TRG path inspection.
- Use the real Go2 Sport stack separately when intentionally testing physical
  movement.

Rollback:
- Restore the old default map paths in
  `/home/jairlab/go2_ws/scripts/run_clubroom_climbable_trg_sim.sh`.
- Remove the simulation-only `require_localization_ok: False` override from
  `/home/jairlab/go2_ws/src/go2_competition_nav/launch/map_policy_sim.launch.py`.

## 2026-06-26 15:44 KST

Context:
- Reopened the previous rough/clubroom room TRG visualization stack rather than
  the current real Go2 Sport stack.
- Target map:
  `clubroom_existing_results_v12d_climbable_traversable`.
- Observed that TRG planning succeeded, but `/trg/output/path` was only
  published as a one-shot message and RViz/CLI could miss it.

Files changed:
- `/home/jairlab/go2_ws/src/TRG-planner/pipelines/ros2/src/ros2_node.cpp`
- `docs/progress_log.md`

Result:
- Changed the TRG ROS2 node to republish the current smooth path while a path
  exists, instead of relying only on the one-shot `pathFound` event.
- Rebuilt `trg_planner_ros`.
- Relaunched `run_clubroom_climbable_trg_sim.sh` with `hardware=none`.
- Verified `/trg/output/path` at about 10 Hz after RViz goal planning.
- Verified path poses from start near `(2.54, -2.42)` to goal near
  `(4.23, -2.07)`.

Next:
- Use RViz `2D Goal Pose` on the rough room map to inspect TRG path, global TRG,
  local TRG, saved PCD, and saved mesh.
- Keep this as visualization/sim only unless explicitly switching back to the
  real Go2 Sport stack.

Rollback:
- Revert the behavior change in
  `/home/jairlab/go2_ws/src/TRG-planner/pipelines/ros2/src/ros2_node.cpp` and
  rebuild `trg_planner_ros`.

## 2026-06-26 15:23 KST

Context:
- User reported that RViz goal pose did not reliably make the real Go2 follow
  the TRG path.
- User also asked whether the onboard Go2 camera includes RGB-D/depth data for
  QR missions.
- User noted that the saved map and live FAST-LIO visualization still appeared
  mismatched.

Files changed:
- `/home/jairlab/go2_ws/scripts/run_rviz_clicked_point_goal_bridge.sh`
- `/home/jairlab/go2_ws/scripts/start_saved_map_trg_rl_stack.sh`
- `/home/jairlab/go2_ws/artifacts/rviz/real_saved_map_policy.rviz`
- `scripts/step7_sport_short_goal_smoke.sh`
- `docs/progress_log.md`

Result:
- Added `rviz_clicked_point_goal_bridge`: RViz `Publish Point` on
  `/clicked_point` is converted to `/goal_pose` using current
  `/localized_odometry`, then handled by the same TRG path guard and Sport
  auto gate.
- Added RViz `PublishPoint` tool and Go2 front camera image display.
- Step 7 manual stack now launches the Go2 front camera bridge by default.
- `dongari` RViz saved-map display now uses the same cleaned/leveled map as
  saved-map localization:
  `/home/jairlab/go2_ws/maps/dongari_room_20260626_clean_level.pcd`.
  TRG still uses the separate traversability-safe map.
- Verified actual onboard camera topic:
  `/go2/front_camera/image_raw`, `sensor_msgs/Image`, `1920x1080`, `bgr8`.
- No depth/disparity/infra/RGB-D topic was present in the live ROS graph, and
  the SDK bridge uses Unitree `VideoClient.GetImageSample()` JPEG/RGB image
  data only.
- Verified clicked-point motion on the real Go2:
  published a 0.18 m forward clicked point, Sport bridge reached
  `move_count=120`, and localization measured `dxy=0.044 m`, `dyaw=0.161 rad`.

Next:
- For RViz testing, use either `2D Goal Pose` or the new `Publish Point` tool.
  Start with short forward points under 0.8 m.
- For QR missions, use `/go2/front_camera/image_raw` for image capture and
  QR decoding. Do not assume RGB-D distance from the onboard camera; use map,
  odometry, MID360, or known wall/zone geometry for approach distance.

Rollback:
- Stop motion with `ACTION=stop ./scripts/step7_sport_short_goal_smoke.sh`.
- Revert the listed files if the clicked-point bridge is replaced by another
  goal-entry method.

## 2026-06-26 15:06 KST

Context:
- Real Go2 was reconnected and the saved-map TRG Sport stack was tested on the
  `dongari` map.
- The robot did not move enough with the initial RViz/TRG test even though
  joystick control worked.

Files changed:
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/go2_roughnav/go2_sport_cmd_bridge.py`
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/go2_roughnav/path_to_cmd_vel.py`
- `/home/jairlab/go2_ws/src/go2_competition_nav/config/rl_policy_interface.yaml`
- `/home/jairlab/go2_ws/scripts/start_saved_map_trg_rl_stack.sh`
- `/home/jairlab/go2_ws/scripts/run_sport_trg_short_goal.sh`
- `/home/jairlab/go2_ws/scripts/run_sport_rviz_goal_auto_gate.sh`
- `scripts/step7_sport_short_goal_smoke.sh`

Result:
- Confirmed the SportClient command path is alive. A guarded 2.0 s short-goal
  run sent `Move` 40 times and produced `odom_delta dxy=0.080 m, dyaw=0.171 rad`.
- Added stop heartbeat enforcement to `go2_sport_cmd_bridge`: if
  `/rl/sport_stop=false` is not continuously refreshed, the bridge treats it as
  stop and sends `StopMove`.
- Added `move_count`, `stop_count`, `last_move_age`, and `last_stop_age` to
  Sport bridge status for real movement debugging.
- Removed stale anonymous embedded auto-gate processes from the stop path. Old
  `python3 - <numeric args>` runners can no longer keep publishing
  `/rl/sport_stop=true` after restart.
- Changed local terrain speed limiting from raw min/max height to robust
  percentile statistics (`height_stat_low_percentile=10`,
  `height_stat_high_percentile=90`). This prevents one or two wall/furniture
  height cells from forcing `high_risk` speed on otherwise usable terrain.
- Raised the Step 7 Sport yaw limit from `0.20` to `0.35 rad/s` so the robot can
  align to TRG paths before moving forward.
- Added validate-only mode and richer test output to
  `run_sport_trg_short_goal.sh`: TRG path guard, last command, terrain state,
  path controller status, and odom delta.
- Current stack is armed in RViz manual mode:
  `CONFIRM_CLEAR=true ACTION=manual_start ./scripts/step7_sport_short_goal_smoke.sh`.

Next:
- In RViz, click only short reachable 2D goals first. The auto gate will verify
  the TRG path and then release Sport movement for at most 6 s.
- If the first clicked RViz goal turns too much, reduce goal distance and click
  closer to the robot's forward direction before testing longer goals.
- Next implementation target remains mission message normalizer and measured
  semantic-map-driven zone goals.

Rollback:
- Stop all motion with `ACTION=stop ./scripts/step7_sport_short_goal_smoke.sh`.
- Revert the listed runtime files if the Sport gate or terrain speed limiter is
  replaced.

## 2026-06-26 13:45 KST

Context:
- User reported that the TRG path was not clearly visible in RViz and asked for
  RViz `2D Goal Pose` to drive the Go2 along the TRG path.
- User also asked to re-check the `이전 mapping` note and apply the parts that
  matter for competition preparation.

Files changed:
- `/home/jairlab/go2_ws/artifacts/rviz/real_saved_map_policy.rviz`
- `/home/jairlab/go2_ws/scripts/run_sport_rviz_goal_auto_gate.sh`
- `/home/jairlab/go2_ws/scripts/start_saved_map_trg_rl_stack.sh`
- `scripts/step7_sport_short_goal_smoke.sh`
- `README.md`
- `docs/current_runbook.md`
- `docs/progress_log.md`

Result:
- Made `TRG Path` more visible in the real saved-map RViz config by increasing
  line width and changing it to a high-contrast yellow.
- Enabled `Snapped Goal` by default so the operator can see where a clicked
  2D goal was projected onto the traversable surface.
- Added duplicate-goal filtering to the RViz Sport auto gate so repeated
  identical `/goal_pose` messages do not keep extending a movement window.
- Added auto-gate timing parameters to the saved-map Sport stack:
  `SPORT_AUTO_GATE_RUN_TIMEOUT_S`, `SPORT_AUTO_GATE_MIN_RUN_S`,
  `SPORT_AUTO_GATE_IDLE_STOP_HZ`, and duplicate goal thresholds.
- Added `ACTION=manual_start` to the Step 7 wrapper. This mode starts the
  current `dongari` saved-map localization/TRG/Sport stack with the RViz 2D
  Goal auto gate enabled and requires `CONFIRM_CLEAR=true`.
- Documented the current `dongari` map split from the `이전 mapping` contract:
  localization map, planner source map, and TRG safe map stay as separate files.

Next:
- Restart the Step 7 stack with
  `CONFIRM_CLEAR=true ACTION=manual_start ./scripts/step7_sport_short_goal_smoke.sh`.
- Click one short reachable RViz `2D Goal Pose` on clear floor and watch
  `/trg/output/path`, `/rl/cmd_vel`, and `/go2_sport_cmd_bridge/status`.
- Do not enter obstacles until short clear-floor 2D Goal behavior and automatic
  stop are verified.

Follow-up:
- Restarted the Step 7 stack in safe waiting mode with `ACTION=start`.
- FAST-LIO odometry sanity gate passed:
  `max_displacement_xy=0.006 m`, `max_step_xy=0.003 m`,
  `max_abs_z=0.009 m`.
- Runtime confirmed:
  localization `OK`, `fitness=1.0`, `rmse=0.0421 m`;
  TRG `obsCloud=/cloud_registered_map`, `egoOdom=/localized_odometry`,
  `frame=map`; Sport bridge `stop=True`.
- Published one dry RViz-style goal while keeping `/rl/sport_stop=true`.
  TRG produced a visible path with `2` poses and the snapped goal marker
  reported `dist=0.281 m`.
- Cleared the dry goal by publishing the current pose as the goal. Final status:
  Sport bridge `stop=True`, `controller_stop=True`, `cmd=(0.00,0.00,0.00)`;
  `path_to_cmd_vel` reports `STOP; reason=endpoint_reached`.

Additional live test:
- User requested moving the real Go2.
- Started `manual_start` mode and sent a short `0.20 m` goal through the RViz
  `/goal_pose` path. The Go2 moved about `0.062 m`, but TRG/goal snapping
  expanded the short goal into a longer path and terrain gating reported
  `high_risk`, so motion stayed weak.
- Stopped the Sport movement nodes with `ACTION=stop`.
- Ran a direct SportClient smoke independent of TRG:
  `BalanceStand`, `SwitchJoystick(False)`, `ClassicWalk(True)`,
  repeated `Move(0.08, 0.0, 0.0)` for `1.2 s`, then `StopMove`,
  `ClassicWalk(False)`, `BalanceStand`, `SwitchJoystick(True)`.
  All SDK calls returned `0`.
- Conclusion: Sport high-level command path is available. The weak autonomous
  movement is now a TRG goal snap/path gating problem, not a basic SDK/Sport
  connectivity problem.

## 2026-06-26 13:22 KST

Context:
- User asked to ensure TRG planning uses both the saved/base map and live map,
  automatically correcting differences, and asked what remains before real Go2
  testing.

Files changed:
- `/home/jairlab/go2_ws/scripts/start_saved_map_trg_rl_stack.sh`
- `scripts/step7_sport_short_goal_smoke.sh`
- `README.md`
- `docs/current_runbook.md`
- `docs/progress_log.md`

Result:
- Confirmed the runtime architecture:
  `map_config=dongari_room_20260626_v3_traversable_safe` provides the saved TRG
  base graph, while `trg_obs_topic=/cloud_registered_map` feeds the continuously
  localized live cloud into TRG.
- Confirmed saved/live automatic pose correction is handled by
  `scan_to_map_localizer` with repeated ICP, relocalization on rejected jumps,
  relocalization on repeated metric failure, and auto z alignment.
- Changed saved-map stack default `PUBLISH_LOCALIZATION_MAP` to `true` so RViz
  always has `/localization_saved_pcd_map` available.
- Added Step 7 wrapper:
  `scripts/step7_sport_short_goal_smoke.sh`.
- The wrapper starts the Sport stack with:
  `CONTROL_BACKEND=sport`, `LAUNCH_SPORT_GOAL_AUTO_GATE=false`,
  `SPORT_MAX_VX=0.10`, `SPORT_MAX_VY=0.04`, `SPORT_MAX_WZ=0.20`.
- Actual movement requires `CONFIRM_CLEAR=true ACTION=run`, so scripted movement
  cannot run accidentally.

Safety:
- Use the Step 7 wrapper for all short-goal tests.
- Keep RViz auto gate disabled for scripted smoke tests.

Follow-up:
- Ran `ACTION=start ./scripts/step7_sport_short_goal_smoke.sh`.
- FAST-LIO odometry sanity gate passed:
  `max_displacement_xy=0.005 m`, `max_step_xy=0.003 m`,
  `max_abs_z=0.005 m`.
- Final readiness:
  localization `OK`, fitness `0.9994`, RMSE `0.0434 m`.
- TRG confirmed:
  `obsCloud=/cloud_registered_map`,
  `egoOdom=/localized_odometry`,
  `frame=map`.
- Sport bridge confirmed:
  `enable_move=True`, `stop=True`, `controller_stop=True`,
  `cmd=(0.00,0.00,0.00)`, `StopMove=0`.
- `path_to_cmd_vel` is the only `/rl/cmd_vel` publisher.
- No real movement was executed in this follow-up.

## 2026-06-26 13:05 KST

Context:
- Proceeded to Step 7 Sport short-goal smoke on the current `dongari` saved-map
  stack.
- Sport stack started with conservative limits:
  `SPORT_MAX_VX=0.10`, `SPORT_MAX_VY=0.04`, `SPORT_MAX_WZ=0.20`.
- FAST-LIO odometry sanity passed with about `0.007 m` max XY displacement.
- First 0.20 m and 0.35 m goals generated TRG paths but no command because the
  terrain gate was blocking motion.

Files changed:
- `/home/jairlab/go2_ws/src/go2_competition_nav/config/rl_policy_interface.yaml`
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/config/rl_interface.yaml`
- `/home/jairlab/go2_ws/scripts/start_saved_map_trg_rl_stack.sh`
- `/home/jairlab/go2_ws/scripts/run_sport_trg_short_goal.sh`
- `README.md`
- `docs/current_runbook.md`
- `docs/progress_log.md`

Result:
- Adjusted `path_to_cmd_vel` terrain gate for the current MID360/localized cloud
  rate:
  `height_scan_timeout_s=2.00`, `unknown_slow_ratio=0.70`,
  `unknown_stop_ratio=0.95`.
- Rebuilt `go2_roughnav` and `go2_competition_nav`.
- Re-ran 0.35 m Sport/TRG short goal. It produced actual bounded Sport
  commands:
  `path_poses=6`, `cmd_peak=0.529`, SportClient `Move=0`.
- Found a safety issue: RViz auto gate and scripted short-goal runner both owned
  `/rl/sport_stop`, so the auto gate could keep `sport_stop=false` after the
  script ended.
- Forced `/rl/sport_stop=true`; Sport status returned to
  `stop=True`, `controller_stop=True`, `cmd=(0,0,0)`, `StopMove=0`.
- Added `LAUNCH_SPORT_GOAL_AUTO_GATE=false` so scripted short-goal tests can run
  without the RViz auto gate overriding stop.
- Updated the short-goal runner to verify Sport stop after the run.

Safety:
- Do not run another scripted short-goal with the RViz auto gate enabled.
- Restart the Sport stack with `LAUNCH_SPORT_GOAL_AUTO_GATE=false` before the
  next smoke test.

Follow-up:
- User reported that the live map and existing map were not visible in RViz.
- Cause was the active Sport stack using
  `/home/jairlab/go2_ws/artifacts/rviz/real_saved_map_policy.rviz`, where
  `/cloud_registered_map` and `/localization_saved_pcd_map` were disabled while
  TRG graph/mesh displays were enabled.
- Updated that RViz config:
  - enabled `Localized Live Cloud` on `/cloud_registered_map`,
  - enabled `Localization Dense Map` on `/localization_saved_pcd_map`,
  - kept `/saved_pcd_map` visible,
  - disabled saved mesh, walkable/obstacle masks, snapped goal, TRG global/local
    graph, and TRG prebuilt map by default for map inspection.
- Killed remaining Sport bridge PIDs and restarted only RViz.
- Verified map topics:
  `/cloud_registered_map`, `/saved_pcd_map`, `/localization_saved_pcd_map`,
  all in frame `map`.
- Verified no `go2_sport_cmd_bridge`, `path_to_cmd_vel`, SDK bridge, policy
  node, or Sport auto gate process remained.

## 2026-06-26 12:45 KST

Context:
- User reported that the existing mapped result was not visible/aligned in RViz.
- Initial diagnosis about missing dense-map visualization was incomplete.
- The actual live failure was saved-map/local cloud misalignment:
  `/icros2026/localization/status` was `REJECTED`, and FAST-LIO odometry/cloud
  had jumped to very large coordinates, for example `/Odometry` around
  `(504, -1307, -273)`.

Files changed:
- `/home/jairlab/go2_ws/src/go2_competition_nav/go2_competition_nav/scan_to_map_localizer.py`
- `scripts/step6_real_sensor_only_dry_run.sh`
- `/home/jairlab/go2_ws/scripts/start_saved_map_trg_rl_stack.sh`
- `/home/jairlab/go2_ws/src/go2_competition_nav/rviz/map_policy_sim.rviz`
- `README.md`
- `docs/current_runbook.md`
- `docs/progress_log.md`

Result:
- Step 6 now publishes `/localization_saved_pcd_map` by default from
  `LOCALIZATION_MAP_PATH`.
- RViz now shows `Localized Live Cloud` (`/cloud_registered_map`) and
  `Localization Dense Map` (`/localization_saved_pcd_map`) by default,
  separately from the lightweight `/saved_pcd_map` planner/visualization layer.
- Stop handling also kills stale `/localization_saved_pcd_map` publishers.
- `scan_to_map_localizer` can now re-run coarse relocalization after repeated
  metric failures, and can auto-align live scan height to the saved map height
  when FAST-LIO z drift/jump is large.
- Rebuilt `go2_competition_nav` and restarted Step 6 with the current
  `동아리방` map.
- After restart, localization returned to:
  `state=OK`, `fitness=1.0`, `rmse=0.041`, pose about
  `x=-0.298, y=-0.150, z=0.001, yaw=-1.630`.
- `/cloud_registered_map`, `/saved_pcd_map`, `/localization_saved_pcd_map`, and
  `/icros2026/localization/status` were all present.
- `/rl/cmd_vel` still had `0` publishers.

Safety:
- This only changes sensor-only visualization/localization display.
- Sport, SDK, policy, and `path_to_cmd_vel` movement nodes remain disabled in
  Step 6.

## Entry Template

```text
## YYYY-MM-DD HH:MM KST

Context:
- What changed or what was tested.

Commands:
- Exact commands run.

Result:
- Pass/fail/partial and evidence.

Next:
- Next concrete action.

Rollback:
- How to return to the previous working state.
```

## 2026-06-26 12:30 KST

Context:
- Added a movement gate so map/live alignment quality is enforced by runtime
  sensor status, not by manual hardcoded offsets.

Commands:
- Edited `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/go2_roughnav/path_to_cmd_vel.py`.
- Edited `/home/jairlab/go2_ws/src/go2_competition_nav/config/rl_policy_interface.yaml`.
- Edited `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/config/rl_interface.yaml`.
- `python3 -m py_compile /home/jairlab/go2_roughnav_ws/src/go2_roughnav/go2_roughnav/path_to_cmd_vel.py`
- YAML parse checks for both config files.
- `colcon build --packages-select go2_roughnav --symlink-install`
- `colcon build --packages-select go2_competition_nav --symlink-install`
- Checked installed config and current topics:
  `/icros2026/localization/status`, `/rl/cmd_vel`.

Result:
- `path_to_cmd_vel` now subscribes to `/icros2026/localization/status`.
- In the Sport saved-map config,
  `require_localization_ok=true`,
  `localization_ok_states=OK,RELOCALIZED`,
  `localization_min_fitness=0.35`,
  `localization_max_rmse=0.55`.
- Missing/stale/rejected/low-fitness/high-RMSE localization status blocks
  nonzero `/rl/cmd_vel`.
- Current sensor-only stack still reports localization `OK` with fitness about
  `1.0` and RMSE about `0.041 m`.
- `/rl/cmd_vel` still had `0` publishers because Sport/path follower movement
  was not started.

Next:
- Keep RViz open and visually verify saved map versus `/cloud_registered_map`.
- Then proceed to Sport short-goal only if the physical area is clear and
  joystick/e-stop recovery is ready.

Rollback:
- Revert `path_to_cmd_vel.py` and the two YAML config changes if the movement
  gate is replaced.

## 2026-06-26 12:15 KST

Context:
- RViz showed live cloud and saved `동아리방` map misalignment.
- Fixed the root cause without hardcoded x/y/yaw offsets by improving automatic
  scan-to-map initialization.

Commands:
- Edited `/home/jairlab/go2_ws/src/go2_competition_nav/go2_competition_nav/scan_to_map_localizer.py`.
- Edited `/home/jairlab/go2_ws/scripts/start_saved_map_trg_rl_stack.sh`.
- Edited `/home/jairlab/GO2/scripts/step6_real_sensor_only_dry_run.sh`.
- `python3 -m py_compile /home/jairlab/go2_ws/src/go2_competition_nav/go2_competition_nav/scan_to_map_localizer.py`
- `bash -n /home/jairlab/go2_ws/scripts/start_saved_map_trg_rl_stack.sh /home/jairlab/GO2/scripts/step6_real_sensor_only_dry_run.sh`
- `colcon build --packages-select go2_competition_nav --symlink-install`
- Restarted sensor-only stack with:
  `LOCALIZATION_MAP_PATH=/home/jairlab/go2_ws/maps/dongari_room_20260626_clean_level.pcd LOCALIZATION_LEVEL_META=/home/jairlab/go2_ws/maps/dongari_room_20260626_clean_level_meta.json VIS_MAP_PATH=/home/jairlab/go2_ws/maps/dongari_room_20260626_planner_source.pcd MAP_CONFIG=dongari_room_20260626_v3_traversable_safe RVIZ=true ACTION=start ./scripts/step6_real_sensor_only_dry_run.sh`

Result:
- `scan_to_map_localizer` now:
  - searches initial yaw over `-180..180 deg`,
  - recomputes translation for each yaw candidate,
  - runs coarse ICP from those candidates,
  - supports bounded relocalization after repeated rejected jumps.
- Sensor-only restart printed:
  `coarse initial alignment candidate: fitness=1.000, rmse=0.093`.
- `/icros2026/localization/status` then reported:
  `state=OK`, `fitness=0.9997..1.0`, `rmse=0.0406..0.0419`,
  pose around `x=-0.298`, `y=-0.155`, `yaw=-1.632`.
- `/rl/cmd_vel` still had `0` publishers, so no robot motion command was sent.

Next:
- Confirm visually in RViz that `/cloud_registered_map` overlaps the saved map.
- If alignment is still visually wrong in a new environment, tune generic ICP
  thresholds or map preprocessing, not manual offsets.
- Only after alignment is visually and numerically stable, proceed to Sport
  short-goal smoke.

Rollback:
- Revert `scan_to_map_localizer.py` and the two launch wrapper changes if the
  automatic initialization is replaced.

## 2026-06-26 11:55 KST

Context:
- Implemented the runtime update for saved-map error compensation, organizer
  message driven random routes, and ICROS2026 obstacle height gates.
- The update is based on the current `동아리방` map but is structured so the
  final competition map can replace it through launch variables.

Commands:
- `python3 -m py_compile /home/jairlab/go2_roughnav_ws/src/go2_roughnav/go2_roughnav/path_to_cmd_vel.py /home/jairlab/go2_ws/src/go2_competition_nav/go2_competition_nav/scan_to_map_localizer.py`
- YAML parse check for:
  `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/config/rl_interface.yaml`,
  `/home/jairlab/go2_ws/src/go2_competition_nav/config/rl_policy_interface.yaml`,
  `/home/jairlab/GO2/maps/icros2026_reference_semantic_map.yaml`
- `bash -n /home/jairlab/go2_ws/scripts/start_saved_map_trg_rl_stack.sh /home/jairlab/GO2/scripts/step6_real_sensor_only_dry_run.sh /home/jairlab/GO2/scripts/step5_reference_rehearsal.sh`
- `python3 /home/jairlab/GO2/tools/validate_icros2026_semantic_map.py /home/jairlab/GO2/maps/icros2026_reference_semantic_map.yaml`
- `colcon build --packages-select go2_roughnav --symlink-install`
- `colcon build --packages-select go2_competition_nav --symlink-install`

Result:
- Added `high_risk` terrain state to `path_to_cmd_vel`.
- Added separate wall/drop thresholds so 0.45 m class competition obstacles can
  be treated as high-risk crawl while 0.6 m wall-class structures remain
  blocked.
- Updated runtime threshold config:
  `slow=0.05`, `cross=0.15`, `high_risk>=0.30`, `wall/block>=0.55`,
  `high_risk_speed_scale=0.22`.
- Added `dongari`, `dongari_room`, and `clubroom_current` preset names to
  `/home/jairlab/go2_ws/scripts/start_saved_map_trg_rl_stack.sh`.
- Changed saved-map localization launch defaults to repeated bounded ICP:
  `freeze_after_localized=false`,
  `icp_period_s=1.0`,
  `max_update_translation_m=0.35`,
  `max_update_yaw_rad=0.35`.
- Added optional launch of `icros2026_goal_adapter`,
  `icros2026_mission_normalizer`, `icros2026_front_camera_bridge`,
  `icros2026_mission_executor`, and rehearsal-only
  `icros2026_route_sequencer` from the Sport saved-map stack.
- Added `/home/jairlab/GO2/docs/icros2026_runtime_profile.md` and updated
  README/runbook/manifest.
- Static checks and both selected package builds passed.

Next:
- Create a measured semantic map for the final arena or the current
  `동아리방` practice layout.
- Start with sensor-only dry-run, then short Sport goals on flat ground before
  obstacle entry.
- Use route sequencer only for rehearsal; use organizer mission messages for
  the real random route.

Rollback:
- Revert the changed runtime files:
  `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/go2_roughnav/path_to_cmd_vel.py`,
  `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/config/rl_interface.yaml`,
  `/home/jairlab/go2_ws/src/go2_competition_nav/config/rl_policy_interface.yaml`,
  `/home/jairlab/go2_ws/scripts/start_saved_map_trg_rl_stack.sh`,
  `/home/jairlab/GO2/scripts/step6_real_sensor_only_dry_run.sh`.
- Remove the new runtime profile doc if this profile is replaced.

## 2026-06-26 11:20 KST

Context:
- Re-ran Step 6 real Go2 sensor-only dry-run using the newly saved
  `동아리방` map derivatives.
- This was live MID360/FAST-LIO plus saved-map localization and TRG/RViz only.
  No Sport, SDK command bridge, policy, `path_to_cmd_vel`, or low-level motor
  publisher was started.

Commands:
- `LOCALIZATION_MAP_PATH=/home/jairlab/go2_ws/maps/dongari_room_20260626_clean_level.pcd LOCALIZATION_LEVEL_META=/home/jairlab/go2_ws/maps/dongari_room_20260626_clean_level_meta.json VIS_MAP_PATH=/home/jairlab/go2_ws/maps/dongari_room_20260626_planner_source.pcd MAP_CONFIG=dongari_room_20260626_v3_traversable_safe RVIZ=true ACTION=start ./scripts/step6_real_sensor_only_dry_run.sh`
- `ros2 topic hz` checks for `/livox/lidar`, `/cloud_registered`, `/Odometry`,
  `/localized_odometry`, `/cloud_registered_map`, and `/rl/height_scan`.
- Published a live sensor-only test `/goal_pose` around `(0.937, -3.276)`.
- Captured `/trg/output/path` to `/tmp/dongari_room_step6_live_path.yaml`.
- `ros2 topic info /rl/cmd_vel -v`.

Result:
- Step 6 stack started with:
  - localization map:
    `/home/jairlab/go2_ws/maps/dongari_room_20260626_clean_level.pcd`,
  - visual map:
    `/home/jairlab/go2_ws/maps/dongari_room_20260626_planner_source.pcd`,
  - TRG config:
    `dongari_room_20260626_v3_traversable_safe`.
- Live sampled topics were fresh:
  `/livox/lidar`, `/cloud_registered`, `/Odometry`, `/localized_odometry`,
  `/cloud_registered_map`, and `/rl/height_scan`.
- TRG graph initialized and kept updating.
- Test goal generated `/trg/output/path` with `24` poses.
- `/rl/cmd_vel` had `0` publishers and only the health monitor subscription.
- FAST-LIO printed repeated IMU dt warnings. This run is sensor-only passing,
  not movement clearance.

Next:
- Keep this stack as the current visualization/localization view if inspection
  is needed.
- Before any Sport short-goal smoke, inspect drift/stability and confirm no
  stale publishers or joystick interference.
- For the real competition course, repeat the same current-map pipeline after
  mapping the course and manually creating the measured semantic map.

Rollback:
- Stop the current sensor-only stack with:
  `ACTION=stop /home/jairlab/GO2/scripts/step6_real_sensor_only_dry_run.sh`.

## 2026-06-26 11:10 KST

Context:
- User saved the fresh current-environment FAST-LIO map as `동아리방.pcd`.
- Built current-map derivatives for TRG rehearsal without enabling Sport or
  low-level command output.
- Kept the Korean raw map name, but used ASCII-safe names for ROS/TRG generated
  artifacts.

Commands:
- `/home/jairlab/go2_ws/scripts/verify_fastlio_map.sh /home/jairlab/go2_ws/maps/current_mapping/동아리방.pcd`
- `TRAVERSABILITY_PROFILE=icros2026 FORCE=true /home/jairlab/go2_ws/scripts/prepare_new_pcd_for_trg.sh /home/jairlab/go2_ws/maps/current_mapping/동아리방.pcd dongari_room_20260626`
- `python3 /home/jairlab/go2_ws/scripts/make_trg_planner_source.py /home/jairlab/go2_ws/maps/dongari_room_20260626_clean_level.pcd --output-pcd /home/jairlab/go2_ws/maps/dongari_room_20260626_planner_source.pcd --meta-json /home/jairlab/go2_ws/maps/dongari_room_20260626_planner_source_meta.json --grid 0.10 --z-min -0.80 --z-max 1.10 --floor-percentile 5 --max-above-local-floor 1.05 --max-above-global-floor 1.20 --min-points-per-cell 1 --voxel 0.025`
- `python3 /home/jairlab/go2_ws/scripts/make_trg_traversable_map.py /home/jairlab/go2_ws/maps/dongari_room_20260626_planner_source.pcd --map-name dongari_room_20260626_v3 --resolution 0.10 --min-points-per-cell 2 --max-cloud-points 200000 --surface-mode terrain --surface-height-estimator supported_high --max-surface-slope-deg 65.0 --max-surface-step 0.55 --max-surface-roughness 0.90 --obstacle-clearance-radius 0.15 --body-clearance-radius 0.05 --trg-robot-size 0.25 --trg-safety-factor 2.0 --force`
- Started no-motion RViz/TRG visualization with
  `MAP_CONFIG=dongari_room_20260626_v3_traversable_safe`,
  `MAP_PATH=/home/jairlab/go2_ws/maps/dongari_room_20260626_planner_source.pcd`,
  `WALKABLE_MAP_PATH=/home/jairlab/go2_ws/maps/dongari_room_20260626_v3_traversable_safe.pcd`,
  `START_X=0.187`, and `START_Y=-0.325`.
- Published a test `/goal_pose` around `(0.937, -3.276)`.

Result:
- Raw map verified:
  `/home/jairlab/go2_ws/maps/current_mapping/동아리방.pcd`
  with `1382290` points and `44233533` bytes.
- Existing same-name map was preserved as:
  `/home/jairlab/go2_ws/maps/current_mapping/동아리방_backup_20260626_110710.pcd`.
- Direct `dongari_room_20260626_traversable_safe` build produced only
  `walkable_cells=1`; do not use it as the selected map.
- `dongari_room_20260626_v2_traversable_safe` produced `193` walkable cells.
- Selected `dongari_room_20260626_v3_traversable_safe` produced `859` walkable
  cells.
- RViz/TRG visualization is running from
  `/tmp/dongari_room_step5_visualization_v3.log`.
- TRG graph initialized successfully; prebuilt graph showed `859` nodes and
  `6306` edges.
- `/rl/cmd_vel` had `0` publishers.
- Test goal generated a `/trg/output/path` with `12` poses.

Next:
- Use this map for offline semantic annotation practice only; the real
  competition course will need the same mapping and v3-style validation pass.
- Create a measured semantic map for zones, walls, QR/photo sides, and risk
  regions before route-card rehearsal on a real competition map.
- Do not run Sport movement from this map until sensor-only localization against
  the selected map is checked.

Rollback:
- Stop the current visualization stack with:
  `pkill -TERM -f 'map_policy_sim.launch.py|start_map_policy_sim.sh|pcd_map_closed_loop_sim|prebuilt_graph_publisher|trg_ros2_node|height_scan_bridge|pipeline_health|publish_saved_pcd_map|publish_saved_map_mesh|robot_state_publisher|rviz2'`.
- Raw map can be restored from the same-name backup if needed.

## 2026-06-26 10:58 KST

Context:
- User clarified that the next newly captured map, not the previous saved map,
  should be saved as `동아리방.pcd`.
- Restarted pure current-environment FAST-LIO mapping with the final output
  target fixed to `/home/jairlab/go2_ws/maps/current_mapping/동아리방.pcd`.

Commands:
- `MAP_BASENAME='동아리방' ACTION=start ./scripts/step6_current_mapping.sh`
- created `/tmp/icros2026_current_mapping_output_map` so plain
  `ACTION=save_stop ./scripts/step6_current_mapping.sh` keeps saving to
  `동아리방.pcd`
- `ros2 topic info /rl/cmd_vel -v`
- `ros2 topic hz /cloud_registered --window 10`

Result:
- New mapping run is active.
- RViz is live FAST-LIO RViz.
- Final output on stop:
  `/home/jairlab/go2_ws/maps/current_mapping/동아리방.pcd`
- Existing `동아리방.pcd` will be backed up automatically before the new remap is
  copied over.
- `/rl/cmd_vel` was unknown; no movement command path was active.

Next:
- Move the robot slowly through the target area.
- Finish this remap with:
  `ACTION=save_stop /home/jairlab/GO2/scripts/step6_current_mapping.sh`.

Rollback:
- Stop without saving another map:
  `SAVE_ON_STOP=false ACTION=stop /home/jairlab/GO2/scripts/step6_current_mapping.sh`.

## 2026-06-26 10:55 KST

Context:
- Stopped the current FAST-LIO mapping run after saving the accumulated map.
- User requested the map name to be `동아리방`.

Commands:
- `ACTION=save_stop ./scripts/step6_current_mapping.sh`
- hard-linked the timestamped snapshot to
  `/home/jairlab/go2_ws/maps/current_mapping/동아리방.pcd`
- updated
  `/home/jairlab/go2_ws/maps/current_mapping/latest_current_fastlio_map.pcd`
  to point at `동아리방.pcd`
- `/home/jairlab/go2_ws/scripts/verify_fastlio_map.sh /home/jairlab/go2_ws/maps/current_mapping/동아리방.pcd`

Result:
- Current mapping processes stopped.
- Named map:
  `/home/jairlab/go2_ws/maps/current_mapping/동아리방.pcd`
- Timestamped source:
  `/home/jairlab/go2_ws/maps/current_mapping/go2_current_fastlio_20260626_105447.pcd`
- The named map and timestamped source are hardlinks to the same data.
- Map size: `250081725` bytes.
- Points: `7815046`.
- No movement command path was active.

Next:
- Use `동아리방.pcd` as the input for cleaned/leveled localization map,
  measured semantic map, and TRG traversability map generation.

Rollback:
- Remove `/home/jairlab/go2_ws/maps/current_mapping/동아리방.pcd` if the name is
  replaced; the timestamped source remains.

## 2026-06-26 10:45 KST

Context:
- The RViz view from Step 6 was correctly showing the previous practice map,
  but that map is not the current room/arena layout.
- Switched to current-environment MID360 FAST-LIO mapping with live RViz.
- This matches the competition workflow: pre-map the course first, then derive
  localization/TRG/semantic maps from the measured PCD.

Files changed:
- `README.md`
- `docs/current_runbook.md`
- `docs/progress_log.md`
- `docs/robot_live_snapshot.md`
- `workspace_manifest.yaml`
- `scripts/step6_current_mapping.sh`

Commands:
- `ACTION=start ./scripts/step6_current_mapping.sh`
- `ros2 topic info /rl/cmd_vel -v`
- `ros2 topic hz /livox/lidar --window 20`
- `ACTION=save ./scripts/step6_current_mapping.sh`
- `ros2 topic hz /cloud_registered --window 10`

Result:
- Current mapping stack is running:
  - `start_go2_fastlio_mapping.sh`
  - `livox_ros_driver2_node`
  - `fastlio_mapping`
  - `rviz2 -d .../fastlio.rviz`
- RViz is now live FAST-LIO mapping, not previous saved-map localization RViz.
- `/livox/lidar` was about `10 Hz`.
- `/cloud_registered` was about `10 Hz`.
- `/map_save` service was available.
- Movement safety:
  - `/rl/cmd_vel`: unknown.
  - `/go2_sport_cmd_bridge/status`: unknown.
  - `/lowcmd`: unknown.
  - `path_to_cmd_vel`, `go2_sport_cmd_bridge`, `go2_sdk2_bridge`, and
    `onnx_policy_node` were not running.
- Saved initial current-space snapshot:
  - path:
    `/home/jairlab/go2_ws/maps/current_mapping/go2_current_fastlio_20260626_104528.pcd`
  - size: `24377179` bytes
  - points: `761779`
  - latest symlink:
    `/home/jairlab/go2_ws/maps/current_mapping/latest_current_fastlio_map.pcd`

Next:
- Move the robot slowly through the full target area while mapping remains
  active.
- Finish with:
  `ACTION=save_stop /home/jairlab/GO2/scripts/step6_current_mapping.sh`.
- Use the final PCD to build the cleaned/leveled localization map, measured
  semantic map, and TRG traversability map.

Rollback:
- Stop without saving another map:
  `SAVE_ON_STOP=false ACTION=stop /home/jairlab/GO2/scripts/step6_current_mapping.sh`.
- The saved snapshot is an added PCD under
  `/home/jairlab/go2_ws/maps/current_mapping/`; existing previous mapping files
  were not modified.

## 2026-06-26 10:37 KST

Context:
- Implemented and ran Step 6 real Go2 sensor-only dry-run.
- Used the actual LAN-connected Go2/MID360, but kept all movement outputs off.
- Included RViz visualization and reused the previous mapping practice map for
  saved-map localization/TRG.

Files changed:
- `README.md`
- `docs/current_runbook.md`
- `docs/progress_log.md`
- `docs/robot_live_snapshot.md`
- `workspace_manifest.yaml`
- `scripts/step6_real_sensor_only_dry_run.sh`

Commands:
- `bash -n scripts/step6_real_sensor_only_dry_run.sh`
- `ACTION=start ./scripts/step6_real_sensor_only_dry_run.sh`
- 8 second ROS2 probe over `/livox/lidar`, `/cloud_registered`,
  `/cloud_registered_map`, `/Odometry`, `/localized_odometry`,
  `/rl/height_scan`, `/roughnav/terrain_flags`, `/trg/output/path`,
  `/icros2026/localization/status`, and `/rl/cmd_vel`
- temporary `/goal_pose` probe at localized pose plus `0.6 m` in map x
- `ros2 topic info /rl/cmd_vel -v`

Result:
- Step 6 passed for the previous-mapping practice stack.
- RViz is running with:
  `/home/jairlab/go2_ws/src/go2_competition_nav/rviz/map_policy_sim.rviz`.
- Previous mapping inputs used:
  - localization map:
    `/home/jairlab/go2_ws/maps/go2_dual_lidar_clean_level.pcd`
  - localization meta:
    `/home/jairlab/go2_ws/maps/go2_dual_lidar_clean_level_meta.json`
  - visual map:
    `/home/jairlab/go2_ws/maps/go2_dual_lidar_clean_level_detail_surface.pcd`
  - TRG config:
    `go2_dual_lidar_icros2026_traversable_safe`
- 8 second probe:
  - `/livox/lidar`: `10.18 Hz`
  - `/cloud_registered`: `5.63 Hz`
  - `/cloud_registered_map`: `0.77 Hz`
  - `/Odometry`: `5.63 Hz`
  - `/localized_odometry`: `5.59 Hz`
  - `/rl/height_scan`: `0.80 Hz`
  - `/roughnav/terrain_flags`: `5.71 Hz`
  - raw odom drift: `0.0024 m`
  - localized odom drift: `0.0037 m`
- Localization status was `OK` with `fitness=1.0`, `rmse=0.0`, `x=1.982`,
  `y=0.230`, and `yaw=0.4434`.
- Temporary TRG goal probe published a map-frame goal at `x=2.582`,
  `y=0.230`; `/trg/output/path` produced `5` messages and latest path length
  was `2` poses.
- Movement safety:
  - `/rl/cmd_vel` publisher count was `0`.
  - the probe observed `0` `/rl/cmd_vel` messages.
  - `go2_sport_cmd_bridge/status` was unknown.
  - `/lowcmd` was unknown.
  - `path_to_cmd_vel`, `go2_sport_cmd_bridge`, `go2_sdk2_bridge`, and
    `onnx_policy_node` were not running.
- Caution:
  - `traversability_node` diagnostic still reports `blocked` in the static room
    view due to high unknown/blocked ratios and must be tuned before it becomes
    a hard movement gate.
  - FAST-LIO still logs IMU dt warnings, but stationary odometry drift remained
    small in this dry-run.

Next:
- Step 7 is Sport short-goal smoke, but only after the current sensor-only
  stack is stopped and command publisher checks are repeated.
- Before obstacle work, tune traversability diagnostic thresholds/ROI and
  re-run Step 5/6 on the final measured competition map.

Rollback:
- Stop Step 6 with:
  `ACTION=stop /home/jairlab/GO2/scripts/step6_real_sensor_only_dry_run.sh`.
- This entry added one GO2 wrapper and documentation updates; no map or runtime
  control node was modified for movement.

## 2026-06-26 KST

Context:
- Implemented and ran Step 5 offline route rehearsal.
- Added a reference-only semantic map for public ICROS2026 geometry.
- Added a no-RL Step 5 wrapper that starts reference RViz/TRG/goal routing while
  keeping SportClient, SDK publish, and ONNX policy off.
- Rebuilt the practice ICROS2026 TRG map from the previous mapping workflow.

Files changed:
- `README.md`
- `docs/current_runbook.md`
- `docs/progress_log.md`
- `workspace_manifest.yaml`
- `maps/icros2026_reference_semantic_map.yaml`
- `scripts/step5_reference_rehearsal.sh`

Commands:
- `python3 tools/validate_icros2026_semantic_map.py maps/icros2026_reference_semantic_map.yaml`
- `bash -n scripts/step5_reference_rehearsal.sh`
- `ROUTE_CARD=A ACTION=start scripts/step5_reference_rehearsal.sh`
- strict Route A/B/C contract probe over `/icros2026/route/select`,
  `/goal_pose`, `/trg/input/snapped_goal_pose`, and `/trg/output/path`
- `cd /home/jairlab/go2_ws && ./scripts/rebuild_icros2026_trg_maps.sh practice`

Result:
- No Sport or low-level robot movement command was sent.
- Step 5 reference rehearsal is currently running in `ROS_DOMAIN_ID=88` with
  RViz.
- `onnx_policy_node`, `go2_sdk2_bridge`, and `go2_sport_cmd_bridge` are not
  running.
- `/rl/cmd_vel` has one publisher, `path_to_cmd_vel`, and is consumed by the
  virtual `pcd_map_closed_loop_sim` only.
- `/joint_group_effort_controller/joint_trajectory` has zero publishers.
- Route A/B/C contract passed:
  - A: zones `2,4,3,1` all produced semantic goals, snapped goals, and
    non-empty TRG paths.
  - B: zones `3,2,4,1` all produced semantic goals, snapped goals, and
    non-empty TRG paths.
  - C: zones `3,4,2,1` all produced semantic goals, snapped goals, and
    non-empty TRG paths.
- Reference virtual odometry moved about `1.013 m` during a 6 second probe.
- Latest terrain state in the reference run was `flat`, reason `front_clear`.
- Practice map rebuild from previous mapping succeeded:
  - input: `/home/jairlab/go2_ws/maps/go2_dual_lidar_clean_level_detail_surface.pcd`
  - output: `/home/jairlab/go2_ws/maps/go2_dual_lidar_icros2026_traversable_safe.pcd`
  - walkable cells: `3113`

Next:
- Build the final measured competition semantic map from the actual aligned
  course map.
- Re-run this Step 5 route contract against the measured semantic/TRG map.
- Then proceed to Step 6 real Go2 sensor-only dry-run, still with Sport
  movement disabled.

Rollback:
- Stop Step 5 with:
  `ACTION=stop /home/jairlab/GO2/scripts/step5_reference_rehearsal.sh`.
- Remove the reference-only semantic map and wrapper if the reference rehearsal
  flow is replaced by a measured-map-only launch.
- The previous mapping raw PCD was not modified; only derived ICROS2026 TRG map
  outputs were regenerated.

## 2026-06-26 KST

Context:
- Continued Step 4 and enabled live visualization without any Sport movement.
- Switched the validated competition sensor path to external MID360 +
  FAST-LIO2.
- Confirmed the previous mapping workflow in `/home/jairlab/GO2/이전 mapping`
  must be reused for Step 5 map/TRG rehearsal.

Files changed:
- `README.md`
- `docs/robot_live_snapshot.md`
- `docs/current_runbook.md`
- `docs/progress_log.md`

Commands:
- `./scripts/setup_livox_cyclonedds.sh`
- `FASTLIO_CONFIG=/home/jairlab/go2_ws/src/FAST_LIO_ROS2/FAST_LIO/config/mid360.yaml AUTO_SAVE_ON_EXIT=false RVIZ=false STARTUP_HEALTH_CHECK=false ./scripts/start_go2_fastlio_mapping.sh`
- `rviz2 -d /home/jairlab/go2_ws/src/FAST_LIO_ROS2/FAST_LIO/rviz_cfg/fastlio.rviz`
- `ros2 run go2_roughnav height_scan_bridge --ros-args -p cloud_topic:=/cloud_registered -p odom_topic:=/Odometry -p out_topic:=/rl/height_scan -p point_stride:=3`
- `ros2 run go2_roughnav traversability_node --ros-args -p pointcloud_topic:=/cloud_registered -p terrain_flags_topic:=/roughnav/terrain_flags -p map_topic:=/traversability_map`
- `ros2 topic hz /livox/lidar`
- `ros2 topic hz /cloud_registered`
- `ros2 topic hz /Odometry`
- `ros2 topic info /cloud_registered -v`
- Read-only `/rl/height_scan`, `/roughnav/terrain_flags`, and `/Odometry`
  samples.

Result:
- No Sport or low-level movement command was sent.
- `/livox/lidar` published at about `9.9-10.0 Hz`.
- `/cloud_registered` published at about `6.5 Hz`.
- `/Odometry` published at about `6.6 Hz`.
- RViz is subscribed to `/cloud_registered`.
- `/rl/height_scan` published with `273` cells, `48` valid cells, and valid
  height range about `-0.379` to `0.191 m`.
- `/roughnav/terrain_flags` published diagnostic JSON. Current state was
  conservative `blocked` with high unknown ratio, so it still needs tuning
  before becoming a hard movement gate.
- `/rl/cmd_vel` was unknown, and `path_to_cmd_vel` plus
  `go2_sport_cmd_bridge` were not running.
- Built-in UTLiDAR FAST-LIO path is rejected for the mainline because the tested
  odometry diverged badly.

Next:
- Proceed to Step 5: offline route rehearsal from previous mapping principles,
  measured semantic map, cleaned/TRG map, and RViz graph/path validation.
- Tune traversability diagnostic thresholds and region of interest.
- Keep Sport movement blocked until Step 6 sensor-only dry-run passes.

Rollback:
- Stop live visualization processes with `pkill -f` on
  `start_go2_fastlio_mapping`, `livox_ros_driver2_node`, `fastlio_mapping`,
  `height_scan_bridge`, `traversability_node`, and `rviz2`.
- The FAST-LIO config used for visualization has `pcd_save_en: false`, so no raw
  map overwrite rollback is needed.

## 2026-06-26 KST

Context:
- Ran Step 4 live sensor gate without Sport movement.
- Built `go2_roughnav` after Step 2/3 changes.
- Rechecked Go2 network, SDK LowState, ROS2 sensor topics, and front camera.
- Fixed `icros2026_front_camera_bridge` shutdown behavior after the read-only
  camera check exposed a Ctrl-C shutdown traceback.

Files changed:
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/go2_roughnav/icros2026_front_camera_bridge.py`
- `README.md`
- `docs/robot_live_snapshot.md`
- `docs/progress_log.md`

Commands:
- `colcon build --packages-select go2_roughnav --symlink-install`
- `ping -c 2 -W 1 192.168.123.20`
- `ping -c 2 -W 1 192.168.123.161`
- ROS2 topic list/type/info checks for `/utlidar/*`, `/uslam/*`,
  `/rl/cmd_vel`, `/rl/controller_stop`, and `/rl/stop`.
- Reliable/BEST_EFFORT read-only subscriber counters for standard LiDAR, IMU,
  pose, odom, range, and USLAM topics.
- `python3 /home/jairlab/go2_ws/scripts/read_go2_lowstate_snapshot.py --net enp46s0 --timeout 4 --sample-seconds 0.5`
- Short `icros2026_front_camera_bridge` run with
  `network_interface:=enp46s0`.

Result:
- No local autonomy or movement publisher was left running.
- No Sport or low-level movement command was sent.
- `enp46s0` was up at `192.168.123.99/24`.
- MID360 `192.168.123.20` ping passed.
- Go2 `192.168.123.161` ping passed.
- `go2_roughnav` build passed and installed the new Step 2/3 executables.
- SDK LowState passed: 262 samples in the short read-only snapshot, estimated
  body tilt `2.83 deg`.
- Go2 front camera bridge passed: status `state=OK shape=1920x1080`, image
  width `1920`, height `1080`.
- ROS2 standard topic samples:
  - `/utlidar/robot_pose`: sampled.
  - `/utlidar/range_info`: sampled once.
  - `/utlidar/cloud`, `/utlidar/cloud_deskewed`, `/utlidar/height_map`,
    `/utlidar/imu`, `/utlidar/robot_odom`, `/uslam/frontend/odom`,
    `/uslam/localization/odom`, `/uslam/frontend/cloud_world_ds`, and
    `/uslam/localization/cloud_world`: no samples in the short read-only
    counters.
- `unitree_go` ROS2 message package is still not visible in the currently
  sourced environment.

Next:
- Do not start Sport movement yet.
- Fix/enable live LiDAR cloud and IMU stream or source the correct Unitree ROS2
  environment.
- Re-run Step 4 until `/utlidar/cloud`, `/utlidar/imu`, `/cloud_registered`,
  `/Odometry`, `/rl/height_scan`, and `/roughnav/terrain_state` are fresh.

Rollback:
- Revert the front-camera bridge patch if a different ROS Image transport is
  adopted. The sensor checks were read-only and need no rollback.

## 2026-06-26 KST

Context:
- Implemented Step 3: terrain risk layer cleanup.
- `path_to_cmd_vel` now turns the front-center height scan into a simple
  terrain state and uses that state for speed limiting or blocked-terrain stop.
- `traversability_node` remains diagnostic-first and now publishes structured
  JSON flags.

Files changed:
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/go2_roughnav/path_to_cmd_vel.py`
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/go2_roughnav/traversability_node.py`
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/config/rl_interface.yaml`
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/config/roughnav.yaml`
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/launch/06_real_go2_pipeline.launch.py`
- `README.md`
- `docs/current_runbook.md`
- `workspace_manifest.yaml`

Commands:
- AST parse check for `path_to_cmd_vel.py`, `traversability_node.py`, and
  `06_real_go2_pipeline.launch.py`.
- YAML parse check for `rl_interface.yaml`, `roughnav.yaml`, and
  `workspace_manifest.yaml`.
- Terrain assessment smoke tests for flat, approach, cross, blocked step,
  unknown slow, unknown stop, stale scan, and missing scan cases.

Result:
- `/roughnav/terrain_state` now reports JSON with `state`, `speed_scale`,
  `reason`, `valid_cells`, `unknown_ratio`, `max_height_m`, and `roughness_m`.
- Competition config requires a fresh height scan for motion.
- Missing, stale, mostly unknown, or large-step front terrain becomes
  `blocked` and causes `/rl/controller_stop`.
- `/roughnav/terrain_flags` from `traversability_node` is structured JSON.
- `06_real_go2_pipeline.launch.py` now has optional
  `launch_traversability:=true`.
- No Sport or low-level robot movement command was sent.

Next:
- Build/source `/home/jairlab/go2_roughnav_ws`.
- Run Step 4 live sensor gate with no Sport movement and echo
  `/rl/height_scan`, `/roughnav/terrain_state`, and `/roughnav/terrain_flags`.

Rollback:
- Revert the listed runtime files and GO2 hub docs if live sensor data shows
  the thresholds are too conservative for the course surface.

## 2026-06-26 KST

Context:
- Implemented Step 2: mission message normalizer.
- The normalizer converts organizer String/JSON/key-value/std_msgs inputs into
  a stable normalized mission JSON without sending robot motion commands.

Files changed:
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/go2_roughnav/icros2026_mission_normalizer.py`
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/go2_roughnav/icros2026_mission_executor.py`
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/setup.py`
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/config/rl_interface.yaml`
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/launch/06_real_go2_pipeline.launch.py`
- `README.md`
- `docs/current_runbook.md`
- `workspace_manifest.yaml`

Commands:
- AST parse check for the new normalizer, mission executor, setup, and real
  launch file.
- YAML parse check for `rl_interface.yaml` and `workspace_manifest.yaml`.
- Parser smoke tests for JSON, key-value String, and executor auto mode.

Result:
- `zone=3;color=red` normalizes to QR/photo on the left wall and executor mode
  `photo`.
- `zone=2;color=orange` normalizes to left-wall touch but is blocked from the
  current executor because guarded wall-touch execution is not implemented yet.
- `mission=button` and `executor_mode=dry_run` are correctly selected by the
  executor in auto mode.
- Real launch now has `launch_mission_normalizer`.

Next:
- Implement Step 3: terrain risk layer cleanup around height scan,
  traversability diagnostics, and speed-state reporting.

Rollback:
- Revert the listed runtime files and GO2 hub docs if organizer message handling
  changes when the official message package is received.

## 2026-06-26 KST

Context:
- Updated `README.md` to lock the final competition mainline around SLAM,
  local height/elevation scan, traversability/risk, speed control, TRG, and
  Go2 Sport mode.
- Kept full foothold planning, low-level RL, and torque control out of the
  competition mainline.

Files changed:
- `README.md`

Commands:
- Checked all README local references with `test -e`.
- Re-ran semantic-map template validation.
- Confirmed launch arguments for `arena_semantics_path`,
  `launch_front_camera_bridge`, and `launch_mission_executor`.

Result:
- README now contains the final architecture, hardcoding boundary, mission
  interpretation, obstacle strategy, current Go2 snapshot, implemented
  artifacts, eight-step roadmap, commands, and source notes.
- Semantic-map template still fails validation until measured values are filled
  in, which is the expected safe behavior.

Next:
- Implement Step 2: mission message normalizer.

Rollback:
- Revert `README.md` to the previous hub summary if the final mainline changes.

## 2026-06-26 KST

Context:
- Continued step 1 of the non-hardcoded implementation.
- Added a measured semantic-map contract so zone-only goals cannot silently
  become guessed hardcoded coordinates.

Files changed:
- `docs/semantic_map_contract.md`
- `templates/icros2026_semantic_map.template.yaml`
- `tools/validate_icros2026_semantic_map.py`
- `docs/current_runbook.md`
- `docs/non_hardcoded_obstacle_strategy.md`
- `README.md`
- `workspace_manifest.yaml`
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/go2_roughnav/icros2026_goal_adapter.py`
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/config/rl_interface.yaml`
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/launch/06_real_go2_pipeline.launch.py`

Commands:
- `python3 tools/validate_icros2026_semantic_map.py templates/icros2026_semantic_map.template.yaml`
- AST parse check for the validator, goal adapter, front-camera bridge, mission
  executor, and real launch file.
- YAML parse check for `workspace_manifest.yaml` and the semantic-map template.
- In-memory valid semantic-map sample through the validator.

Result:
- The template fails validation until measured values are filled in. This is
  intentional and prevents accidental runtime use of placeholders.
- A valid four-zone sample passes with no errors.
- Goal adapter now requires all four semantic zone goals by default when a
  semantic map is supplied.
- Real launch accepts `arena_semantics_path` and optional
  `launch_front_camera_bridge` / `launch_mission_executor` switches.

Next:
- Fill a real measured semantic map from the aligned course map.
- Build/source `/home/jairlab/go2_roughnav_ws`.
- Run read-only front-camera bridge with `network_interface:=enp46s0`.
- Move to step 2: mission message normalization for color/side/action.

Rollback:
- Revert the listed files if this semantic-map contract is replaced.

## 2026-06-26 KST

Context:
- Ran read-only live diagnostics before powering down the connected Go2.

Files changed:
- `docs/robot_live_snapshot.md`
- `README.md`

Commands:
- `ip -br addr`
- ping checks for `192.168.123.161` and `192.168.123.20`
- Unitree SDK read-only subscriptions for `rt/lowstate`,
  `rt/sportmodestate`, and `rt/lf/sportmodestate`
- Unitree SDK `VideoClient.GetImageSample()`
- ROS2 topic list and short echo checks for Unitree LiDAR topics
- local process check for stale command publishers

Result:
- `enp46s0=192.168.123.99/24`.
- MID360 candidate `192.168.123.20` ping OK.
- Go2 candidate `192.168.123.161` did not answer ICMP, but SDK DDS telemetry
  was received.
- SDK LowState, SportModeState, and front camera are reachable.
- ROS2 graph shows Unitree LiDAR topics, but only `/utlidar/robot_pose` was
  sampled in the short echo check.
- Local ROS2 environment still lacks `unitree_go` message definitions.
- No active local command publisher was found after filtering.

Next:
- Fix/source `unitree_go` messages or deliberately keep Go2 state on SDK path.
- Recheck `/utlidar/cloud`, `/utlidar/imu`, and `/utlidar/range_info` with the
  correct driver/source environment before relying on live LiDAR cloud.
- Repeat IMU level check before any Sport movement.

Rollback:
- This entry and snapshot file are documentation-only.

## 2026-06-26 KST

Context:
- Implemented the first non-hardcoded runtime layer in
  `/home/jairlab/go2_roughnav_ws`.
- Kept the robot motion path disabled during this edit; no movement command was
  sent to Go2.

Files changed:
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/go2_roughnav/icros2026_goal_adapter.py`
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/go2_roughnav/icros2026_front_camera_bridge.py`
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/go2_roughnav/icros2026_mission_executor.py`
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/setup.py`
- `/home/jairlab/go2_roughnav_ws/src/go2_roughnav/config/rl_interface.yaml`
- `README.md`
- `workspace_manifest.yaml`

Commands:
- Python AST parse check for `icros2026_goal_adapter.py`,
  `icros2026_front_camera_bridge.py`, and `icros2026_mission_executor.py`.
- Label parsing smoke for `1->2`, `①->②`, `destination=zone3`, and `goal4`.

Result:
- Goal adapter now forwards direct organizer pose/point/XY messages and refuses
  zone-only goals unless a measured semantic map is configured.
- Default fixed live zone coordinates were removed from the active config.
- Added a read-only Go2 SDK front-camera bridge publishing
  `/go2/front_camera/image_raw`.
- Mission executor default photo topic now points to the Go2 onboard camera.
- Static Python syntax checks passed.

Next:
- Create a measured semantic-map file with zone goals, wall geometry, QR/photo
  sides, and obstacle risk regions.
- Build/source `/home/jairlab/go2_roughnav_ws`.
- Run the front-camera bridge read-only with `network_interface:=enp46s0`.

Rollback:
- Revert the listed runtime files in `/home/jairlab/go2_roughnav_ws` and the
  two GO2 hub files if this implementation is replaced.

## 2026-06-26 KST

Context:
- Re-scoped the autonomy plan around the rule that fixed forward distances,
  fixed rotations, fixed timed nudges, and fixed route scripts count as
  hardcoding.
- Added obstacle feasibility policy for Sport mode, especially central 0.45 m
  stair/slope cross and foot-drop/gap-like terrain.
- Decided the first runtime implementation target should be mission/goal
  normalization and Go2 onboard camera bridging, not movement scripts.

Files changed:
- `docs/non_hardcoded_obstacle_strategy.md`
- `docs/autonomy_directions.md`
- `docs/current_runbook.md`

Result:
- Documented that Sport mode is conditionally useful for rough tile, low
  uneven terrain, and 0.2 m entry blocks, but not guaranteed for the 0.45 m
  center structure or foot-drop terrain.
- Defined the non-hardcoded contract: organizer messages + measured semantic
  map + TRG + live feedback.

Next:
- Patch `/home/jairlab/go2_roughnav_ws` runtime code when write permission is
  available:
  1. remove live default zone coordinates from `icros2026_goal_adapter`,
  2. require measured semantic-map goals for zone-only messages,
  3. add Go2 SDK front-camera image bridge,
  4. update mission executor default image topic to the Go2 camera bridge.

Rollback:
- Revert the three GO2 documentation edits if this strategy is replaced.

## 2026-06-25 KST

Context:
- Created the `/home/jairlab/GO2` competition hub plan.
- Selected Sport-based autonomous driving as the competition mainline.
- Kept low-level RL as a separate experiment track.
- Decided not to move existing workspaces into this folder.

Files planned/created:
- `README.md`
- `docs/rules_summary.md`
- `docs/autonomy_directions.md`
- `docs/current_runbook.md`
- `docs/progress_log.md`
- `workspace_manifest.yaml`

Main route:
- MID360 -> FAST-LIO2 -> saved-map localization -> TRG -> path_to_cmd_vel ->
  Go2 SportClient.

Next:
- Run `PRESET=practice MODE=presport ./scripts/icros2026_readiness_audit.sh`
  from `/home/jairlab/go2_ws`.
- Rehearse route A/B/C with the ICROS2026 reference map in RViz.
- Perform real sensor/localization dry-run before enabling Sport movement.

Rollback:
- This change only adds hub documents under `/home/jairlab/GO2`; no runtime code
  or maps were changed.
