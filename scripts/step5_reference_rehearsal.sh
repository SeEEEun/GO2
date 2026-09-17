#!/usr/bin/env bash
set -euo pipefail

GO2_HUB="${GO2_HUB:-/home/jairlab/GO2}"
GO2_WS="${GO2_WS:-/home/jairlab/go2_ws}"
ROUGHNAV_WS="${ROUGHNAV_WS:-/home/jairlab/go2_roughnav_ws}"
POLICY_NAME="${POLICY_NAME:-isaaclab_best_45000}"
ROUTE_CARD="${ROUTE_CARD:-A}"
ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-88}"
ACTION="${ACTION:-start}"
STOP_LIVE="${STOP_LIVE:-true}"

SEMANTIC_MAP="${SEMANTIC_MAP:-${GO2_HUB}/maps/icros2026_reference_semantic_map.yaml}"
MAP_PATH="${MAP_PATH:-${GO2_WS}/maps/icros2026_reference_dense_visual.pcd}"
WALKABLE_MAP_PATH="${WALKABLE_MAP_PATH:-${GO2_WS}/maps/icros2026_reference_terrain_surface.pcd}"
MAP_CONFIG="${MAP_CONFIG:-icros2026_reference_traversable_safe}"
LOG_DIR="${LOG_DIR:-/tmp}"

stop_step5() {
  ACTION=stop "${GO2_WS}/scripts/start_icros2026_reference_sim.sh" >/dev/null 2>&1 || true
  pkill -TERM -f 'icros2026_goal_adapter|icros2026_route_sequencer|path_to_cmd_vel.*trg/output/path' 2>/dev/null || true
  sleep 1
  pkill -KILL -f 'icros2026_goal_adapter|icros2026_route_sequencer|path_to_cmd_vel.*trg/output/path' 2>/dev/null || true
}

stop_live_mid360() {
  pkill -TERM -f 'start_go2_fastlio_mapping|livox_ros_driver2_node|fastlio_mapping|height_scan_bridge|traversability_node' 2>/dev/null || true
  sleep 1
  pkill -KILL -f 'start_go2_fastlio_mapping|livox_ros_driver2_node|fastlio_mapping|height_scan_bridge|traversability_node' 2>/dev/null || true
}

if [[ "${ACTION}" == "stop" ]]; then
  stop_step5
  echo "Stopped Step 5 reference rehearsal processes."
  exit 0
fi

if [[ ! -f "${SEMANTIC_MAP}" ]]; then
  echo "Missing semantic map: ${SEMANTIC_MAP}" >&2
  exit 2
fi

if [[ ! -f "${GO2_WS}/maps/icros2026_reference_terrain_surface.pcd" ]]; then
  cd "${GO2_WS}"
  ./scripts/generate_icros2026_reference_map.py --force
fi

if [[ "${STOP_LIVE}" == "true" ]]; then
  stop_live_mid360
fi
stop_step5

set +u
source /opt/ros/humble/setup.bash
source "${GO2_WS}/install/setup.bash"
source "${ROUGHNAV_WS}/install/setup.bash"
set -u
export ROS_DOMAIN_ID

python3 "${GO2_HUB}/tools/validate_icros2026_semantic_map.py" "${SEMANTIC_MAP}"

mkdir -p "${LOG_DIR}"

setsid bash -lc "
  set -eo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source '${GO2_WS}/install/setup.bash'
  source '${ROUGHNAV_WS}/install/setup.bash'
  set -u
  export ROS_DOMAIN_ID='${ROS_DOMAIN_ID}'
  export MAP_PATH='${MAP_PATH}'
  export WALKABLE_MAP_PATH='${WALKABLE_MAP_PATH}'
  export WALKABLE_MAP_IS_PRESCREENED=true
  export MAP_CONFIG='${MAP_CONFIG}'
  export RVIZ=true
  export GAZEBO=false
  export TRG_DIRECT_FALLBACK=0
  export WALKABLE_GRID_RESOLUTION=0.10
  cd '${GO2_WS}'
  exec ./scripts/start_map_policy_sim.sh '${POLICY_NAME}' \
    run_policy:=false \
    run_sdk2_dryrun:=false \
    run_cmd:=false \
    run_health:=true \
    launch_rviz:=true
" >"${LOG_DIR}/icros2026_step5_map_policy_sim.log" 2>&1 &
map_pid=$!

sleep 8

setsid bash -lc "
  set -eo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source '${GO2_WS}/install/setup.bash'
  source '${ROUGHNAV_WS}/install/setup.bash'
  set -u
  export ROS_DOMAIN_ID='${ROS_DOMAIN_ID}'
  exec ros2 run go2_roughnav path_to_cmd_vel --ros-args \
    --params-file '${ROUGHNAV_WS}/src/go2_roughnav/config/rl_interface.yaml' \
    -p path_topic:=/trg/output/path \
    -p goal_topic:=/trg/input/snapped_goal_pose \
    -p max_lin_x:=0.25 \
    -p max_lin_y:=0.12 \
    -p max_ang_z:=0.45 \
    -p height_step_slow_m:=0.12 \
    -p height_step_cross_m:=0.30 \
    -p height_step_block_m:=0.65 \
    -p height_roughness_slow_m:=0.30 \
    -p height_roughness_cross_m:=0.55 \
    -p height_roughness_block_m:=0.75 \
    -p unknown_stop_ratio:=0.95
" >"${LOG_DIR}/icros2026_step5_path_to_cmd_vel.log" 2>&1 &
cmd_pid=$!

setsid bash -lc "
  set -eo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source '${GO2_WS}/install/setup.bash'
  source '${ROUGHNAV_WS}/install/setup.bash'
  set -u
  export ROS_DOMAIN_ID='${ROS_DOMAIN_ID}'
  exec ros2 run go2_roughnav icros2026_goal_adapter --ros-args \
    --params-file '${ROUGHNAV_WS}/src/go2_roughnav/config/rl_interface.yaml' \
    -p fixed_frame:=map \
    -p arena_semantics_path:='${SEMANTIC_MAP}' \
    -p output_goal_topic:=/goal_pose
" >"${LOG_DIR}/icros2026_step5_goal_adapter.log" 2>&1 &
adapter_pid=$!

setsid bash -lc "
  set -eo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source '${GO2_WS}/install/setup.bash'
  source '${ROUGHNAV_WS}/install/setup.bash'
  set -u
  export ROS_DOMAIN_ID='${ROS_DOMAIN_ID}'
  exec ros2 run go2_roughnav icros2026_route_sequencer --ros-args \
    --params-file '${ROUGHNAV_WS}/src/go2_roughnav/config/rl_interface.yaml' \
    -p route_card:='${ROUTE_CARD}' \
    -p auto_start:=true
" >"${LOG_DIR}/icros2026_step5_route_sequencer.log" 2>&1 &
route_pid=$!

cat <<EOF
Started Step 5 reference rehearsal.
  ROS_DOMAIN_ID=${ROS_DOMAIN_ID}
  route=${ROUTE_CARD}
  semantic_map=${SEMANTIC_MAP}
  map_policy_sim_pid=${map_pid}
  path_to_cmd_vel_pid=${cmd_pid}
  goal_adapter_pid=${adapter_pid}
  route_sequencer_pid=${route_pid}
  logs:
    ${LOG_DIR}/icros2026_step5_map_policy_sim.log
    ${LOG_DIR}/icros2026_step5_path_to_cmd_vel.log
    ${LOG_DIR}/icros2026_step5_goal_adapter.log
    ${LOG_DIR}/icros2026_step5_route_sequencer.log

Stop with:
  ACTION=stop ${GO2_HUB}/scripts/step5_reference_rehearsal.sh
EOF
