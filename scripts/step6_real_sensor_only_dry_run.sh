#!/usr/bin/env bash
set -euo pipefail

GO2_HUB="${GO2_HUB:-/home/jairlab/GO2}"
GO2_WS="${GO2_WS:-/home/jairlab/go2_ws}"
ROUGHNAV_WS="${ROUGHNAV_WS:-/home/jairlab/go2_roughnav_ws}"
ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-88}"
RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"
LIVOX_IFACE="${LIVOX_IFACE:-enp46s0}"
MID360_IP="${MID360_IP:-192.168.123.20}"
GO2_IP="${GO2_IP:-192.168.123.161}"
ACTION="${ACTION:-start}"
RVIZ="${RVIZ:-true}"
LOG_DIR="${LOG_DIR:-/tmp}"
PUBLISH_LOCALIZATION_MAP="${PUBLISH_LOCALIZATION_MAP:-true}"
LAUNCH_ROBOT_MODEL="${LAUNCH_ROBOT_MODEL:-true}"
ROBOT_JOINT_STATE_TOPIC="${ROBOT_JOINT_STATE_TOPIC:-/visual_joint_states}"

FASTLIO_CONFIG="${FASTLIO_CONFIG:-${GO2_WS}/src/FAST_LIO_ROS2/FAST_LIO/config/mid360.yaml}"
LOCALIZATION_MAP_PATH="${LOCALIZATION_MAP_PATH:-${GO2_WS}/maps/go2_dual_lidar_clean_level.pcd}"
LOCALIZATION_LEVEL_META="${LOCALIZATION_LEVEL_META:-${GO2_WS}/maps/go2_dual_lidar_clean_level_meta.json}"
VIS_MAP_PATH="${VIS_MAP_PATH:-${GO2_WS}/maps/go2_dual_lidar_clean_level_detail_surface.pcd}"
MAP_CONFIG="${MAP_CONFIG:-go2_dual_lidar_icros2026_traversable_safe}"
POLICY_NAME="${POLICY_NAME:-go2_real_contract_model_42400}"
RVIZ_CONFIG="${RVIZ_CONFIG:-${GO2_WS}/src/go2_competition_nav/rviz/map_policy_sim.rviz}"
LOCALIZATION_FREEZE_AFTER_LOCALIZED="${LOCALIZATION_FREEZE_AFTER_LOCALIZED:-false}"
LOCALIZATION_ICP_PERIOD_S="${LOCALIZATION_ICP_PERIOD_S:-1.0}"
LOCALIZATION_MAX_UPDATE_TRANSLATION_M="${LOCALIZATION_MAX_UPDATE_TRANSLATION_M:-0.35}"
LOCALIZATION_MAX_UPDATE_YAW_RAD="${LOCALIZATION_MAX_UPDATE_YAW_RAD:-0.35}"
LOCALIZATION_COARSE_YAW_SEARCH_DEG="${LOCALIZATION_COARSE_YAW_SEARCH_DEG:-180.0}"
LOCALIZATION_COARSE_YAW_STEP_DEG="${LOCALIZATION_COARSE_YAW_STEP_DEG:-10.0}"
LOCALIZATION_REINIT_ON_REJECTED_JUMP="${LOCALIZATION_REINIT_ON_REJECTED_JUMP:-true}"
LOCALIZATION_REJECTED_JUMP_REINIT_COUNT="${LOCALIZATION_REJECTED_JUMP_REINIT_COUNT:-3}"
LOCALIZATION_MAX_REINIT_TRANSLATION_M="${LOCALIZATION_MAX_REINIT_TRANSLATION_M:-3.0}"
LOCALIZATION_MAX_REINIT_YAW_RAD="${LOCALIZATION_MAX_REINIT_YAW_RAD:-3.14159}"
LOCALIZATION_REINIT_ON_METRIC_FAILURE="${LOCALIZATION_REINIT_ON_METRIC_FAILURE:-true}"
LOCALIZATION_REJECTED_METRIC_REINIT_COUNT="${LOCALIZATION_REJECTED_METRIC_REINIT_COUNT:-2}"
LOCALIZATION_AUTO_Z_ALIGN="${LOCALIZATION_AUTO_Z_ALIGN:-true}"
LOCALIZATION_Z_REFERENCE_PERCENTILE="${LOCALIZATION_Z_REFERENCE_PERCENTILE:-50.0}"
LOCALIZATION_TARGET_Z_MIN="${LOCALIZATION_TARGET_Z_MIN:--1.15}"
LOCALIZATION_TARGET_Z_MAX="${LOCALIZATION_TARGET_Z_MAX:-1.65}"
LOCALIZATION_SOURCE_Z_MIN="${LOCALIZATION_SOURCE_Z_MIN:--1000000000.0}"
LOCALIZATION_SOURCE_Z_MAX="${LOCALIZATION_SOURCE_Z_MAX:-1000000000.0}"
LOCALIZATION_LIVE_LEVEL_MODE="${LOCALIZATION_LIVE_LEVEL_MODE:-auto_floor}"
LOCALIZATION_LIVE_LEVEL_FREEZE_AFTER_LOCALIZED="${LOCALIZATION_LIVE_LEVEL_FREEZE_AFTER_LOCALIZED:-true}"
LOCALIZATION_LIVE_FLOOR_LOW_PERCENTILE="${LOCALIZATION_LIVE_FLOOR_LOW_PERCENTILE:-1.0}"
LOCALIZATION_LIVE_FLOOR_HIGH_PERCENTILE="${LOCALIZATION_LIVE_FLOOR_HIGH_PERCENTILE:-35.0}"
LOCALIZATION_GLOBAL_XY_SEARCH="${LOCALIZATION_GLOBAL_XY_SEARCH:-true}"
LOCALIZATION_GLOBAL_XY_SEARCH_RESOLUTION_M="${LOCALIZATION_GLOBAL_XY_SEARCH_RESOLUTION_M:-0.60}"
LOCALIZATION_GLOBAL_XY_SEARCH_SCORE_RESOLUTION_M="${LOCALIZATION_GLOBAL_XY_SEARCH_SCORE_RESOLUTION_M:-0.20}"
LOCALIZATION_GLOBAL_XY_SEARCH_MAX_CENTERS="${LOCALIZATION_GLOBAL_XY_SEARCH_MAX_CENTERS:-180}"
LOCALIZATION_GLOBAL_XY_SEARCH_SOURCE_POINTS="${LOCALIZATION_GLOBAL_XY_SEARCH_SOURCE_POINTS:-1400}"
LOCALIZATION_GLOBAL_XY_SEARCH_TOP_K="${LOCALIZATION_GLOBAL_XY_SEARCH_TOP_K:-18}"
FASTLIO_ODOM_CHECK="${FASTLIO_ODOM_CHECK:-true}"
FASTLIO_ODOM_CHECK_SEC="${FASTLIO_ODOM_CHECK_SEC:-4.0}"
FASTLIO_ODOM_MAX_ABS_XY_M="${FASTLIO_ODOM_MAX_ABS_XY_M:-30.0}"
FASTLIO_ODOM_MAX_ABS_Z_M="${FASTLIO_ODOM_MAX_ABS_Z_M:-5.0}"

stop_step6() {
  ACTION=stop "${GO2_HUB}/scripts/step5_reference_rehearsal.sh" >/dev/null 2>&1 || true
  pkill -TERM -f 'go2_sport_cmd_bridge|go2_sdk2_bridge|onnx_policy_node|go2_lowstate_bridge|icros2026_safety_supervisor|path_to_cmd_vel' 2>/dev/null || true
  pkill -TERM -f 'trg_policy_dryrun.launch.py|trg_ros2_node|goal_snapper|pipeline_health|robot_state_publisher|static_transform_publisher|prebuilt_graph_publisher' 2>/dev/null || true
  pkill -TERM -f 'scan_to_map_localizer|localized_odom_to_tf|publish_saved_pcd_map|saved_pcd_map_publisher|publish_saved_map_mesh|saved_map_mesh_publisher' 2>/dev/null || true
  pkill -TERM -f '/saved_pcd_map|/localization_saved_pcd_map|/saved_map_mesh' 2>/dev/null || true
  pkill -TERM -f 'start_go2_fastlio_mapping|livox_ros_driver2_node|fastlio_mapping|height_scan_bridge|traversability_node|rviz2|go2_visual_joint_states|start_go2_visual_joint_states' 2>/dev/null || true
  sleep 1
  pkill -KILL -f 'go2_sport_cmd_bridge|go2_sdk2_bridge|onnx_policy_node|go2_lowstate_bridge|icros2026_safety_supervisor|path_to_cmd_vel' 2>/dev/null || true
  pkill -KILL -f 'trg_policy_dryrun.launch.py|trg_ros2_node|goal_snapper|pipeline_health|robot_state_publisher|static_transform_publisher|prebuilt_graph_publisher' 2>/dev/null || true
  pkill -KILL -f 'scan_to_map_localizer|localized_odom_to_tf|publish_saved_pcd_map|saved_pcd_map_publisher|publish_saved_map_mesh|saved_map_mesh_publisher' 2>/dev/null || true
  pkill -KILL -f '/saved_pcd_map|/localization_saved_pcd_map|/saved_map_mesh' 2>/dev/null || true
  pkill -KILL -f 'start_go2_fastlio_mapping|livox_ros_driver2_node|fastlio_mapping|height_scan_bridge|traversability_node|rviz2|go2_visual_joint_states|start_go2_visual_joint_states' 2>/dev/null || true
}

source_ros() {
  set +u
  source /opt/ros/humble/setup.bash
  source "${GO2_WS}/install/setup.bash"
  source "${ROUGHNAV_WS}/install/setup.bash"
  set -u
}

require_file() {
  local path="$1"
  if [[ ! -e "${path}" ]]; then
    echo "ERROR: missing required path: ${path}" >&2
    exit 2
  fi
}

check_fastlio_odom_sane() {
  python3 - "${FASTLIO_ODOM_CHECK_SEC}" "${FASTLIO_ODOM_MAX_ABS_XY_M}" "${FASTLIO_ODOM_MAX_ABS_Z_M}" <<'PY'
import math
import sys
import time

import rclpy
from nav_msgs.msg import Odometry
from rclpy.node import Node

duration = float(sys.argv[1])
max_abs_xy = float(sys.argv[2])
max_abs_z = float(sys.argv[3])


class OdomGate(Node):
    def __init__(self):
        super().__init__("fastlio_odom_sanity_gate")
        self.samples = []
        self.create_subscription(Odometry, "/Odometry", self.cb, 20)

    def cb(self, msg):
        p = msg.pose.pose.position
        self.samples.append((float(p.x), float(p.y), float(p.z)))


rclpy.init()
node = OdomGate()
end = time.monotonic() + duration
while rclpy.ok() and time.monotonic() < end:
    rclpy.spin_once(node, timeout_sec=0.1)

samples = node.samples
node.destroy_node()
rclpy.shutdown()

if len(samples) < 3:
    print(f"ERROR: FAST-LIO /Odometry has only {len(samples)} samples; not starting localization/TRG.", file=sys.stderr)
    sys.exit(4)

bad = []
for x, y, z in samples:
    if not all(math.isfinite(v) for v in (x, y, z)):
        bad.append((x, y, z))
    if math.hypot(x, y) > max_abs_xy or abs(z) > max_abs_z:
        bad.append((x, y, z))

last = samples[-1]
print(
    "FASTLIO_ODOM_GATE "
    f"samples={len(samples)} last=({last[0]:.3f},{last[1]:.3f},{last[2]:.3f}) "
    f"max_abs_xy={max_abs_xy:.1f} max_abs_z={max_abs_z:.1f}"
)
if bad:
    x, y, z = bad[-1]
    print(
        "ERROR: FAST-LIO /Odometry is out of bounds "
        f"sample=({x:.3f},{y:.3f},{z:.3f}); restart FAST-LIO/LiDAR before localization/TRG.",
        file=sys.stderr,
    )
    sys.exit(5)
PY
}

if [[ "${ACTION}" == "stop" ]]; then
  stop_step6
  echo "Stopped Step 6 real sensor-only dry-run processes."
  exit 0
fi

require_file "${FASTLIO_CONFIG}"
require_file "${LOCALIZATION_MAP_PATH}"
require_file "${LOCALIZATION_LEVEL_META}"
require_file "${VIS_MAP_PATH}"
require_file "${GO2_WS}/src/TRG-planner/config/${MAP_CONFIG}.yaml"
require_file "${RVIZ_CONFIG}"

mkdir -p "${LOG_DIR}"
stop_step6

echo "Configuring Livox/CycloneDDS..."
"${GO2_WS}/scripts/setup_livox_cyclonedds.sh" >/tmp/icros2026_step6_livox_dds_setup.log

export ROS_DOMAIN_ID
export RMW_IMPLEMENTATION
export CYCLONEDDS_URI="${CYCLONEDDS_URI:-file:///tmp/cyclonedds_livox.xml}"
export LIVOX_CONFIG_PATH="${LIVOX_CONFIG_PATH:-/tmp/MID360_config_livox.json}"

if ! ping -c 1 -W 1 "${MID360_IP}" >/dev/null 2>&1; then
  echo "ERROR: MID360 ${MID360_IP} is not reachable. Check ${LIVOX_IFACE} wiring/IP before dry-run." >&2
  exit 3
fi
if ! ping -c 1 -W 1 "${GO2_IP}" >/dev/null 2>&1; then
  echo "WARN: Go2 ${GO2_IP} did not respond to ping. Continuing sensor-only, but Sport tests must wait." >&2
fi

echo "Starting live MID360 FAST-LIO without map auto-save..."
setsid bash -lc "
  set -eo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source '${GO2_WS}/install/setup.bash'
  set -u
  export ROS_DOMAIN_ID='${ROS_DOMAIN_ID}'
  export RMW_IMPLEMENTATION='${RMW_IMPLEMENTATION}'
  export CYCLONEDDS_URI='${CYCLONEDDS_URI}'
  export LIVOX_CONFIG_PATH='${LIVOX_CONFIG_PATH}'
  export LD_LIBRARY_PATH='${GO2_WS}/external/livox_sdk2_install/lib:'\"\${LD_LIBRARY_PATH:-}\"
  export FASTLIO_CONFIG='${FASTLIO_CONFIG}'
  export AUTO_SAVE_ON_EXIT=false
  export RVIZ=false
  export STARTUP_HEALTH_CHECK=false
  exec '${GO2_WS}/scripts/start_go2_fastlio_mapping.sh'
" >"${LOG_DIR}/icros2026_step6_fastlio.log" 2>&1 &
fastlio_pid=$!

sleep 10
if [[ "${FASTLIO_ODOM_CHECK}" == "true" ]]; then
  echo "Checking FAST-LIO raw odometry before localization/TRG..."
  source_ros
  check_fastlio_odom_sane
fi

echo "Starting saved-map localization from previous mapping..."
setsid bash -lc "
  set -eo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source '${ROUGHNAV_WS}/install/setup.bash' 2>/dev/null || true
  source '${GO2_WS}/install/setup.bash'
  set -u
  export ROS_DOMAIN_ID='${ROS_DOMAIN_ID}'
  export RMW_IMPLEMENTATION='${RMW_IMPLEMENTATION}'
  export CYCLONEDDS_URI='${CYCLONEDDS_URI}'
  exec ros2 run go2_competition_nav scan_to_map_localizer --ros-args \
    -p map_path:='${LOCALIZATION_MAP_PATH}' \
    -p level_meta_path:='${LOCALIZATION_LEVEL_META}' \
    -p input_cloud_topic:=/cloud_registered \
    -p input_odom_topic:=/Odometry \
    -p output_cloud_topic:=/cloud_registered_map \
    -p output_odom_topic:=/localized_odometry \
    -p map_frame:=map \
    -p odom_frame:=camera_init \
    -p child_frame:=body \
    -p initial_x:=0.0 \
    -p initial_y:=0.0 \
    -p initial_z:=0.0 \
    -p initial_yaw:=0.0 \
    -p locked_z:=0.0 \
    -p planar_only:=true \
    -p voxel_size:=0.10 \
    -p icp_period_s:='${LOCALIZATION_ICP_PERIOD_S}' \
    -p max_corr_distance:=0.55 \
    -p min_fitness:=0.35 \
    -p max_rmse:=0.55 \
    -p max_points:=9000 \
    -p coarse_yaw_search_deg:='${LOCALIZATION_COARSE_YAW_SEARCH_DEG}' \
    -p coarse_yaw_step_deg:='${LOCALIZATION_COARSE_YAW_STEP_DEG}' \
    -p freeze_after_localized:='${LOCALIZATION_FREEZE_AFTER_LOCALIZED}' \
    -p max_update_translation_m:='${LOCALIZATION_MAX_UPDATE_TRANSLATION_M}' \
    -p max_update_yaw_rad:='${LOCALIZATION_MAX_UPDATE_YAW_RAD}' \
    -p reinitialize_on_rejected_jump:='${LOCALIZATION_REINIT_ON_REJECTED_JUMP}' \
    -p rejected_jump_reinit_count:='${LOCALIZATION_REJECTED_JUMP_REINIT_COUNT}' \
    -p max_reinitialization_translation_m:='${LOCALIZATION_MAX_REINIT_TRANSLATION_M}' \
    -p max_reinitialization_yaw_rad:='${LOCALIZATION_MAX_REINIT_YAW_RAD}' \
    -p reinitialize_on_metric_failure:='${LOCALIZATION_REINIT_ON_METRIC_FAILURE}' \
    -p rejected_metric_reinit_count:='${LOCALIZATION_REJECTED_METRIC_REINIT_COUNT}' \
    -p auto_z_align:='${LOCALIZATION_AUTO_Z_ALIGN}' \
    -p z_reference_percentile:='${LOCALIZATION_Z_REFERENCE_PERCENTILE}' \
    -p target_z_min:='${LOCALIZATION_TARGET_Z_MIN}' \
    -p target_z_max:='${LOCALIZATION_TARGET_Z_MAX}' \
    -p source_z_min:='${LOCALIZATION_SOURCE_Z_MIN}' \
    -p source_z_max:='${LOCALIZATION_SOURCE_Z_MAX}' \
    -p live_level_mode:='${LOCALIZATION_LIVE_LEVEL_MODE}' \
    -p live_level_freeze_after_localized:='${LOCALIZATION_LIVE_LEVEL_FREEZE_AFTER_LOCALIZED}' \
    -p live_floor_low_percentile:='${LOCALIZATION_LIVE_FLOOR_LOW_PERCENTILE}' \
    -p live_floor_high_percentile:='${LOCALIZATION_LIVE_FLOOR_HIGH_PERCENTILE}' \
    -p global_xy_search_on_start:='${LOCALIZATION_GLOBAL_XY_SEARCH}' \
    -p global_xy_search_resolution_m:='${LOCALIZATION_GLOBAL_XY_SEARCH_RESOLUTION_M}' \
    -p global_xy_search_score_resolution_m:='${LOCALIZATION_GLOBAL_XY_SEARCH_SCORE_RESOLUTION_M}' \
    -p global_xy_search_max_centers:='${LOCALIZATION_GLOBAL_XY_SEARCH_MAX_CENTERS}' \
    -p global_xy_search_source_points:='${LOCALIZATION_GLOBAL_XY_SEARCH_SOURCE_POINTS}' \
    -p global_xy_search_top_k:='${LOCALIZATION_GLOBAL_XY_SEARCH_TOP_K}'
" >"${LOG_DIR}/icros2026_step6_scan_to_map_localizer.log" 2>&1 &
localizer_pid=$!

echo "Starting saved map publisher for RViz..."
setsid bash -lc "
  set -eo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source '${GO2_WS}/install/setup.bash'
  set -u
  export ROS_DOMAIN_ID='${ROS_DOMAIN_ID}'
  export MAP_PATH='${VIS_MAP_PATH}'
  export TOPIC=/saved_pcd_map
  export RATE_HZ=1.0
  export VOXEL_SIZE=0.0
  exec '${GO2_WS}/scripts/publish_saved_pcd_map.sh'
" >"${LOG_DIR}/icros2026_step6_saved_pcd_map.log" 2>&1 &
map_pub_pid=$!

localization_map_pub_pid=0
if [[ "${PUBLISH_LOCALIZATION_MAP}" == "true" ]]; then
  echo "Starting dense localization map publisher for RViz..."
  setsid bash -lc "
    set -eo pipefail
    set +u
    source /opt/ros/humble/setup.bash
    source '${GO2_WS}/install/setup.bash'
    set -u
    export ROS_DOMAIN_ID='${ROS_DOMAIN_ID}'
    export MAP_PATH='${LOCALIZATION_MAP_PATH}'
    export TOPIC=/localization_saved_pcd_map
    export RATE_HZ=0.2
    export VOXEL_SIZE=0.05
    exec '${GO2_WS}/scripts/publish_saved_pcd_map.sh'
  " >"${LOG_DIR}/icros2026_step6_localization_saved_pcd_map.log" 2>&1 &
  localization_map_pub_pid=$!
fi

echo "Starting localized odometry TF..."
setsid bash -lc "
  set -eo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source '${GO2_WS}/install/setup.bash'
  set -u
  export ROS_DOMAIN_ID='${ROS_DOMAIN_ID}'
  export RMW_IMPLEMENTATION='${RMW_IMPLEMENTATION}'
  export CYCLONEDDS_URI='${CYCLONEDDS_URI}'
  exec ros2 run go2_competition_nav localized_odom_to_tf --ros-args \
    -p odom_topic:=/localized_odometry \
    -p parent_frame:=map \
    -p child_frame:=base \
    -p fixed_z:=-0.05
" >"${LOG_DIR}/icros2026_step6_localized_odom_to_tf.log" 2>&1 &
tf_pid=$!

if [[ "${LAUNCH_ROBOT_MODEL}" == "true" && "${ROBOT_JOINT_STATE_TOPIC}" == "/visual_joint_states" ]]; then
  echo "Starting Go2 visual joint states for RViz..."
  setsid bash -lc "
    set -eo pipefail
    set +u
    source /opt/ros/humble/setup.bash
    source '${GO2_WS}/install/setup.bash'
    set -u
    export ROS_DOMAIN_ID='${ROS_DOMAIN_ID}'
    export TOPIC=/visual_joint_states
    exec '${GO2_WS}/scripts/start_go2_visual_joint_states.sh'
  " >"${LOG_DIR}/icros2026_step6_go2_visual_joint_states.log" 2>&1 &
  visual_joints_pid=$!
fi

echo "Starting TRG/height-scan/RViz with all command outputs disabled..."
setsid bash -lc "
  set -eo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source '${ROUGHNAV_WS}/install/setup.bash'
  source '${GO2_WS}/install/setup.bash'
  set -u
  export ROS_DOMAIN_ID='${ROS_DOMAIN_ID}'
  export RMW_IMPLEMENTATION='${RMW_IMPLEMENTATION}'
  export CYCLONEDDS_URI='${CYCLONEDDS_URI}'
  exec ros2 launch go2_competition_nav trg_policy_dryrun.launch.py \
    policy_name:='${POLICY_NAME}' \
    policy_onnx:='${GO2_WS}/models/policies/${POLICY_NAME}/policy.onnx' \
    map_config:='${MAP_CONFIG}' \
    network_interface:='${LIVOX_IFACE}' \
    direct_fallback:=0 \
    launch_rviz:='${RVIZ}' \
    rviz_config:='${RVIZ_CONFIG}' \
    trg_obs_topic:=/cloud_registered_map \
    height_scan_cloud_topic:=/cloud_registered_map \
    nav_odom_topic:=/localized_odometry \
    run_odom_offset:=false \
    localized_frame:=map \
    launch_robot_model:='${LAUNCH_ROBOT_MODEL}' \
    robot_joint_state_topic:='${ROBOT_JOINT_STATE_TOPIC}' \
    publish_body_to_base_tf:=false \
    run_cmd:=false \
    run_lowstate:=false \
    run_policy:=false \
    run_safety:=false \
    run_sdk2_dryrun:=false \
    run_health:=true
" >"${LOG_DIR}/icros2026_step6_trg_sensor_only.log" 2>&1 &
trg_pid=$!

echo "Starting traversability diagnostics from live FAST-LIO cloud..."
setsid bash -lc "
  set -eo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source '${GO2_WS}/install/setup.bash'
  source '${ROUGHNAV_WS}/install/setup.bash'
  set -u
  export ROS_DOMAIN_ID='${ROS_DOMAIN_ID}'
  export RMW_IMPLEMENTATION='${RMW_IMPLEMENTATION}'
  export CYCLONEDDS_URI='${CYCLONEDDS_URI}'
  exec ros2 run go2_roughnav traversability_node --ros-args \
    -p pointcloud_topic:=/cloud_registered \
    -p terrain_flags_topic:=/roughnav/terrain_flags \
    -p map_topic:=/traversability_map
" >"${LOG_DIR}/icros2026_step6_traversability.log" 2>&1 &
trav_pid=$!

cat <<EOF
Started Step 6 real Go2 sensor-only dry-run.
  ROS_DOMAIN_ID=${ROS_DOMAIN_ID}
  MID360=${MID360_IP}
  Go2=${GO2_IP}
  localization_map=${LOCALIZATION_MAP_PATH}
  localization_meta=${LOCALIZATION_LEVEL_META}
  visual_map=${VIS_MAP_PATH}
  localization_dense_map_topic=/localization_saved_pcd_map
  publish_localization_dense_map=${PUBLISH_LOCALIZATION_MAP}
  trg_config=${MAP_CONFIG}
  localization_live_icp_freeze_after_localized=${LOCALIZATION_FREEZE_AFTER_LOCALIZED}
  localization_icp_period_s=${LOCALIZATION_ICP_PERIOD_S}
  localization_max_update_xy=${LOCALIZATION_MAX_UPDATE_TRANSLATION_M}
  localization_max_update_yaw=${LOCALIZATION_MAX_UPDATE_YAW_RAD}
  localization_coarse_yaw_search_deg=${LOCALIZATION_COARSE_YAW_SEARCH_DEG}
  localization_coarse_yaw_step_deg=${LOCALIZATION_COARSE_YAW_STEP_DEG}
  localization_reinit_on_metric_failure=${LOCALIZATION_REINIT_ON_METRIC_FAILURE}
  localization_rejected_metric_reinit_count=${LOCALIZATION_REJECTED_METRIC_REINIT_COUNT}
  localization_auto_z_align=${LOCALIZATION_AUTO_Z_ALIGN}
  localization_z_reference_percentile=${LOCALIZATION_Z_REFERENCE_PERCENTILE}
  localization_target_z=(${LOCALIZATION_TARGET_Z_MIN},${LOCALIZATION_TARGET_Z_MAX})
  localization_global_xy_search=${LOCALIZATION_GLOBAL_XY_SEARCH}
  launch_robot_model=${LAUNCH_ROBOT_MODEL}
  robot_joint_state_topic=${ROBOT_JOINT_STATE_TOPIC}
  localization_global_xy_search_resolution_m=${LOCALIZATION_GLOBAL_XY_SEARCH_RESOLUTION_M}
  localization_global_xy_search_max_centers=${LOCALIZATION_GLOBAL_XY_SEARCH_MAX_CENTERS}
  localization_global_xy_search_top_k=${LOCALIZATION_GLOBAL_XY_SEARCH_TOP_K}
  rviz=${RVIZ}
  fastlio_pid=${fastlio_pid}
  localizer_pid=${localizer_pid}
  saved_map_pid=${map_pub_pid}
  localization_saved_map_pid=${localization_map_pub_pid}
  tf_pid=${tf_pid}
  trg_launch_pid=${trg_pid}
  traversability_pid=${trav_pid}
  logs:
    ${LOG_DIR}/icros2026_step6_fastlio.log
    ${LOG_DIR}/icros2026_step6_scan_to_map_localizer.log
    ${LOG_DIR}/icros2026_step6_saved_pcd_map.log
    ${LOG_DIR}/icros2026_step6_localization_saved_pcd_map.log
    ${LOG_DIR}/icros2026_step6_localized_odom_to_tf.log
    ${LOG_DIR}/icros2026_step6_trg_sensor_only.log
    ${LOG_DIR}/icros2026_step6_traversability.log

No Sport/SDK/policy/path_to_cmd_vel node is intentionally started.

Stop with:
  ACTION=stop ${GO2_HUB}/scripts/step6_real_sensor_only_dry_run.sh
EOF
