#!/usr/bin/env bash
set -euo pipefail

GO2_HUB="${GO2_HUB:-/home/jairlab/GO2}"
GO2_WS="${GO2_WS:-/home/jairlab/go2_ws}"
ROUGHNAV_WS="${ROUGHNAV_WS:-/home/jairlab/go2_roughnav_ws}"
ACTION="${ACTION:-check}"
ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-88}"
RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"
PRESET="${PRESET:-dongari}"
GOAL_DISTANCE_M="${GOAL_DISTANCE_M:-0.35}"
RUN_TIMEOUT_S="${RUN_TIMEOUT_S:-2.5}"
GOAL_REPEAT_S="${GOAL_REPEAT_S:-0.8}"
SPORT_MAX_VX="${SPORT_MAX_VX:-0.10}"
SPORT_MAX_VY="${SPORT_MAX_VY:-0.04}"
SPORT_MAX_WZ="${SPORT_MAX_WZ:-0.35}"
SPORT_AUTO_GATE_RUN_TIMEOUT_S="${SPORT_AUTO_GATE_RUN_TIMEOUT_S:-6.0}"
SPORT_AUTO_GATE_MIN_RUN_S="${SPORT_AUTO_GATE_MIN_RUN_S:-0.8}"
LAUNCH_FRONT_CAMERA_BRIDGE="${LAUNCH_FRONT_CAMERA_BRIDGE:-true}"
CONFIRM_CLEAR="${CONFIRM_CLEAR:-false}"

source_ros() {
  set +u
  source /opt/ros/humble/setup.bash
  source "${GO2_WS}/install/setup.bash"
  source "${ROUGHNAV_WS}/install/setup.bash"
  set -u
  export ROS_DOMAIN_ID
  export RMW_IMPLEMENTATION
}

stop_publishers() {
  source_ros
  python3 - <<'PY'
import time

import rclpy
from rclpy.node import Node
from std_msgs.msg import Bool

rclpy.init()
node = Node("step7_force_stop")
sport_stop = node.create_publisher(Bool, "/rl/sport_stop", 10)
controller_stop = node.create_publisher(Bool, "/rl/controller_stop", 10)
msg = Bool(data=True)
end = time.monotonic() + 3.0
while time.monotonic() < end:
    sport_stop.publish(msg)
    controller_stop.publish(msg)
    rclpy.spin_once(node, timeout_sec=0.02)
node.destroy_node()
rclpy.shutdown()
PY
}

kill_motion_nodes() {
  local patterns=(
    '[g]o2_sport_cmd_bridge'
    '[p]ath_to_cmd_vel'
    '[s]port_rviz_goal_auto_gate'
    '[g]o2_sdk2_bridge'
    '[o]nnx_policy_node'
    '[i]cros2026_safety_supervisor'
  )
  local pattern pids pid
  for pattern in "${patterns[@]}"; do
    mapfile -t pids < <(pgrep -f "${pattern}" || true)
    for pid in "${pids[@]}"; do
      [[ -n "${pid}" ]] || continue
      [[ "${pid}" == "$$" ]] && continue
      kill -TERM "${pid}" 2>/dev/null || true
    done
  done
  sleep 1
  for pattern in "${patterns[@]}"; do
    mapfile -t pids < <(pgrep -f "${pattern}" || true)
    for pid in "${pids[@]}"; do
      [[ -n "${pid}" ]] || continue
      [[ "${pid}" == "$$" ]] && continue
      kill -KILL "${pid}" 2>/dev/null || true
    done
  done

  # Embedded Python runners launched from run_sport_* scripts can appear only as
  # "python3 - <numeric args>", so pgrep by script name misses them.
  mapfile -t pids < <(
    ps -eo pid=,args= \
      | awk '($2 ~ /(^|\/)python3$/ || $2 == "python3") && $3 == "-" && $4 ~ /^[0-9]+([.][0-9]+)?$/ {print $1}'
  )
  for pid in "${pids[@]}"; do
    [[ -n "${pid}" ]] || continue
    [[ "${pid}" == "$$" ]] && continue
    kill -TERM "${pid}" 2>/dev/null || true
  done
  sleep 1
  for pid in "${pids[@]}"; do
    [[ -n "${pid}" ]] || continue
    [[ "${pid}" == "$$" ]] && continue
    kill -KILL "${pid}" 2>/dev/null || true
  done
}

check_stack() {
  source_ros
  echo "Localization status:"
  timeout 3 ros2 topic echo /icros2026/localization/status --once || true
  echo
  echo "TRG inputs:"
  ros2 param get /trg_ros2_node ros2.topic.input.obsCloud 2>/dev/null || true
  ros2 param get /trg_ros2_node ros2.topic.input.egoOdom 2>/dev/null || true
  ros2 param get /trg_ros2_node ros2.frameId 2>/dev/null || true
  echo
  echo "Sport bridge status:"
  timeout 3 ros2 topic echo /go2_sport_cmd_bridge/status --once || true
  echo
  echo "/rl/cmd_vel graph:"
  ros2 topic info /rl/cmd_vel -v 2>/dev/null || true
  echo
  echo "Process check:"
  ps -eo pid,ppid,args | awk '/[g]o2_sport_cmd_bridge|[p]ath_to_cmd_vel|[s]port_rviz_goal_auto_gate|[t]rg_ros2_node|[s]can_to_map_localizer|[h]eight_scan_bridge|[r]viz2/ {print}'
}

start_stack() {
  local launch_auto_gate="${1:-false}"
  cd "${GO2_WS}"
  CONTROL_BACKEND=sport \
  LAUNCH_SPORT_GOAL_AUTO_GATE="${launch_auto_gate}" \
  PUBLISH_LOCALIZATION_MAP=true \
  SPORT_MAX_VX="${SPORT_MAX_VX}" \
  SPORT_MAX_VY="${SPORT_MAX_VY}" \
  SPORT_MAX_WZ="${SPORT_MAX_WZ}" \
  SPORT_AUTO_GATE_RUN_TIMEOUT_S="${SPORT_AUTO_GATE_RUN_TIMEOUT_S}" \
  SPORT_AUTO_GATE_MIN_RUN_S="${SPORT_AUTO_GATE_MIN_RUN_S}" \
  LAUNCH_FRONT_CAMERA_BRIDGE="${LAUNCH_FRONT_CAMERA_BRIDGE}" \
  ./scripts/start_saved_map_trg_rl_stack.sh "${PRESET}"
}

start_manual_stack() {
  if [[ "${CONFIRM_CLEAR}" != "true" ]]; then
    echo "ERROR: RViz 2D Goal manual mode can move the real Go2 and requires CONFIRM_CLEAR=true." >&2
    echo "Clear the floor, keep joystick/e-stop ready, then rerun with CONFIRM_CLEAR=true ACTION=manual_start." >&2
    exit 2
  fi
  start_stack true
  stop_publishers
  check_stack
  echo
  echo "Manual RViz 2D Goal mode is armed."
  echo "Click a short reachable goal in RViz; auto gate returns /rl/sport_stop=true after completion or timeout."
}

run_goal() {
  if [[ "${CONFIRM_CLEAR}" != "true" ]]; then
    echo "ERROR: real Go2 movement requires CONFIRM_CLEAR=true." >&2
    echo "Clear the floor, keep joystick/e-stop ready, then rerun with CONFIRM_CLEAR=true." >&2
    exit 2
  fi
  stop_publishers
  if pgrep -f '[s]port_rviz_goal_auto_gate' >/dev/null; then
    echo "ERROR: sport_rviz_goal_auto_gate is running. Stop it before scripted smoke." >&2
    exit 3
  fi
  cd "${GO2_WS}"
  GOAL_DISTANCE_M="${GOAL_DISTANCE_M}" \
  RUN_TIMEOUT_S="${RUN_TIMEOUT_S}" \
  GOAL_REPEAT_S="${GOAL_REPEAT_S}" \
  STOP_AT_END=true \
  ./scripts/run_sport_trg_short_goal.sh
  stop_publishers
  check_stack
}

validate_goal() {
  stop_publishers
  if pgrep -f '[s]port_rviz_goal_auto_gate' >/dev/null; then
    echo "ERROR: sport_rviz_goal_auto_gate is running. Stop it before scripted validation." >&2
    exit 3
  fi
  cd "${GO2_WS}"
  GOAL_DISTANCE_M="${GOAL_DISTANCE_M}" \
  RUN_TIMEOUT_S="${RUN_TIMEOUT_S}" \
  GOAL_REPEAT_S="${GOAL_REPEAT_S}" \
  STOP_AT_END=true \
  VALIDATE_ONLY=true \
  ./scripts/run_sport_trg_short_goal.sh
  stop_publishers
  check_stack
}

case "${ACTION}" in
  stop)
    stop_publishers || true
    kill_motion_nodes
    echo "Stopped Step 7 Sport movement nodes and forced /rl/sport_stop=true."
    ;;
  start)
    start_stack false
    stop_publishers
    check_stack
    ;;
  manual_start)
    start_manual_stack
    ;;
  check)
    check_stack
    ;;
  run)
    run_goal
    ;;
  validate)
    validate_goal
    ;;
  *)
    echo "ERROR: unknown ACTION='${ACTION}'. Use stop, start, manual_start, check, validate, or run." >&2
    exit 2
    ;;
esac
