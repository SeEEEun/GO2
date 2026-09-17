#!/usr/bin/env bash
set -euo pipefail

GO2_HUB="${GO2_HUB:-/home/jairlab/GO2}"
GO2_WS="${GO2_WS:-/home/jairlab/go2_ws}"
ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-88}"
RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"
MID360_IP="${MID360_IP:-192.168.123.20}"
ACTION="${ACTION:-start}"
RVIZ="${RVIZ:-true}"
LOG_DIR="${LOG_DIR:-/tmp}"
SESSION_OUTPUT_FILE="${SESSION_OUTPUT_FILE:-/tmp/icros2026_current_mapping_output_map}"
USER_SET_OUTPUT_MAP="${OUTPUT_MAP+x}"
USER_SET_MAP_BASENAME="${MAP_BASENAME+x}"

FASTLIO_SAVE_CONFIG="${FASTLIO_SAVE_CONFIG:-${GO2_WS}/install/fast_lio/share/fast_lio/config/mid360_save_pcd.yaml}"
GENERIC_MAP="${GENERIC_MAP:-${GO2_WS}/maps/go2_mid360_fastlio_map.pcd}"
OUTPUT_DIR="${OUTPUT_DIR:-${GO2_WS}/maps/current_mapping}"
MAP_BASENAME="${MAP_BASENAME:-go2_current_fastlio_$(date +%Y%m%d_%H%M%S)}"
OUTPUT_MAP="${OUTPUT_MAP:-${OUTPUT_DIR}/${MAP_BASENAME}.pcd}"

if [[ "${ACTION}" != "start" && -f "${SESSION_OUTPUT_FILE}" && -z "${USER_SET_OUTPUT_MAP}" && -z "${USER_SET_MAP_BASENAME}" ]]; then
  OUTPUT_MAP="$(cat "${SESSION_OUTPUT_FILE}")"
fi

source_ros() {
  set +u
  source /opt/ros/humble/setup.bash
  source "${GO2_WS}/install/setup.bash"
  set -u
  export ROS_DOMAIN_ID
  export RMW_IMPLEMENTATION
  export CYCLONEDDS_URI="${CYCLONEDDS_URI:-file:///tmp/cyclonedds_livox.xml}"
  export LIVOX_CONFIG_PATH="${LIVOX_CONFIG_PATH:-/tmp/MID360_config_livox.json}"
}

stop_navigation_only() {
  ACTION=stop "${GO2_HUB}/scripts/step6_real_sensor_only_dry_run.sh" >/dev/null 2>&1 || true
  pkill -TERM -f 'scan_to_map_localizer|localized_odom_to_tf|trg_policy_dryrun.launch.py|trg_ros2_node|goal_snapper|pipeline_health' 2>/dev/null || true
  pkill -TERM -f 'path_to_cmd_vel|go2_sport_cmd_bridge|go2_sdk2_bridge|onnx_policy_node|go2_lowstate_bridge|icros2026_safety_supervisor' 2>/dev/null || true
  sleep 1
  pkill -KILL -f 'scan_to_map_localizer|localized_odom_to_tf|trg_policy_dryrun.launch.py|trg_ros2_node|goal_snapper|pipeline_health' 2>/dev/null || true
  pkill -KILL -f 'path_to_cmd_vel|go2_sport_cmd_bridge|go2_sdk2_bridge|onnx_policy_node|go2_lowstate_bridge|icros2026_safety_supervisor' 2>/dev/null || true
}

stop_mapping_processes() {
  pkill -TERM -f 'start_go2_fastlio_mapping|livox_ros_driver2_node|fastlio_mapping|rviz2' 2>/dev/null || true
  sleep 1
  pkill -KILL -f 'start_go2_fastlio_mapping|livox_ros_driver2_node|fastlio_mapping|rviz2' 2>/dev/null || true
}

backup_existing_generic_map() {
  if [[ -s "${GENERIC_MAP}" ]]; then
    "${GO2_WS}/scripts/backup_fastlio_map.sh" "${GENERIC_MAP}" >/dev/null || true
  fi
}

backup_existing_output_map() {
  if [[ -e "${OUTPUT_MAP}" && ! "${OUTPUT_MAP}" -ef "${GENERIC_MAP}" ]]; then
    local backup="${OUTPUT_MAP%.pcd}_backup_$(date +%Y%m%d_%H%M%S).pcd"
    mv "${OUTPUT_MAP}" "${backup}"
    echo "Backed up existing output map: ${backup}"
  fi
}

save_current_map() {
  source_ros
  mkdir -p "${OUTPUT_DIR}"
  backup_existing_generic_map
  backup_existing_output_map
  if timeout 3 ros2 service list 2>/dev/null | grep -qx "/map_save"; then
    timeout "${MAP_SAVE_TIMEOUT:-20}" ros2 service call /map_save std_srvs/srv/Trigger "{}" || true
  else
    echo "WARN: /map_save service is not available. Trying existing generic map file." >&2
  fi
  "${GO2_WS}/scripts/verify_fastlio_map.sh" "${GENERIC_MAP}"
  cp -p "${GENERIC_MAP}" "${OUTPUT_MAP}"
  ln -sfn "${OUTPUT_MAP}" "${OUTPUT_DIR}/latest_current_fastlio_map.pcd"
  "${GO2_WS}/scripts/verify_fastlio_map.sh" "${OUTPUT_MAP}"
}

if [[ "${ACTION}" == "status" ]]; then
  ps -eo pid=,comm=,args= | rg '(start_go2_fastlio_mapping|livox_ros_driver2_node|fastlio_mapping|rviz2|path_to_cmd_vel|go2_sport_cmd_bridge|go2_sdk2_bridge|onnx_policy_node)' || true
  exit 0
fi

if [[ "${ACTION}" == "save" ]]; then
  save_current_map
  echo "Saved current mapping snapshot: ${OUTPUT_MAP}"
  exit 0
fi

if [[ "${ACTION}" == "stop" || "${ACTION}" == "save_stop" ]]; then
  saved_map=false
  if [[ "${ACTION}" == "save_stop" || "${SAVE_ON_STOP:-true}" == "true" ]]; then
    save_current_map
    saved_map=true
  fi
  stop_mapping_processes
  echo "Stopped current mapping."
  if [[ "${saved_map}" == "true" ]]; then
    echo "Saved map: ${OUTPUT_MAP}"
  else
    echo "No map saved. Output target remains: ${OUTPUT_MAP}"
  fi
  exit 0
fi

if [[ ! -f "${FASTLIO_SAVE_CONFIG}" ]]; then
  echo "ERROR: missing FAST-LIO save config: ${FASTLIO_SAVE_CONFIG}" >&2
  exit 2
fi

mkdir -p "${LOG_DIR}" "${OUTPUT_DIR}"

stop_navigation_only
stop_mapping_processes

echo "Configuring Livox/CycloneDDS..."
"${GO2_WS}/scripts/setup_livox_cyclonedds.sh" >/tmp/icros2026_current_mapping_livox_dds_setup.log

source_ros

if ! ping -c 1 -W 1 "${MID360_IP}" >/dev/null 2>&1; then
  echo "ERROR: MID360 ${MID360_IP} is not reachable." >&2
  exit 3
fi

echo "Starting current-environment FAST-LIO mapping."
printf '%s\n' "${OUTPUT_MAP}" >"${SESSION_OUTPUT_FILE}"
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
  export FASTLIO_CONFIG='${FASTLIO_SAVE_CONFIG}'
  export AUTO_SAVE_ON_EXIT=false
  export RVIZ='${RVIZ}'
  export STARTUP_HEALTH_CHECK=true
  export STARTUP_HEALTH_TIMEOUT=30
  exec '${GO2_WS}/scripts/start_go2_fastlio_mapping.sh'
" >"${LOG_DIR}/icros2026_current_mapping_fastlio.log" 2>&1 &
mapping_pid=$!

cat <<EOF
Started current-environment mapping.
  ROS_DOMAIN_ID=${ROS_DOMAIN_ID}
  MID360=${MID360_IP}
  rviz=${RVIZ}
  mapping_pid=${mapping_pid}
  generic_map=${GENERIC_MAP}
  final_output_on_stop=${OUTPUT_MAP}
  log=${LOG_DIR}/icros2026_current_mapping_fastlio.log

Move the robot slowly through the area manually or with a separate guarded
operator workflow. This script does not start Sport, SDK, policy, or cmd_vel.

Save and stop:
  ACTION=save_stop ${GO2_HUB}/scripts/step6_current_mapping.sh
EOF
