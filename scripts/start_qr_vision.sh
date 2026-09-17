#!/usr/bin/env bash
set -euo pipefail

GO2_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GO2_WS="${GO2_WS:-/home/jairlab/go2_ws}"
ROUGHNAV_WS="${ROUGHNAV_WS:-/home/jairlab/go2_roughnav_ws}"

: "${ROS_DOMAIN_ID:=0}"
: "${RMW_IMPLEMENTATION:=rmw_cyclonedds_cpp}"
: "${NETWORK_INTERFACE:=enp46s0}"
: "${IMAGE_TOPIC:=/go2/front_camera/image_raw}"
: "${MODEL_PATH:=${GO2_DIR}/models/qr/best.pt}"
: "${EVIDENCE_DIR:=${GO2_DIR}/artifacts/qr_evidence}"
: "${PROCESS_HZ:=2.0}"
: "${CONF:=0.25}"
: "${IMGSZ:=640}"
: "${CROP_MARGIN_RATIO:=0.20}"
: "${LAUNCH_GO2_FRONT_CAMERA_BRIDGE:=false}"
: "${SAVE_ALL_DETECTIONS:=false}"
: "${PUBLISH_DEBUG_IMAGE:=true}"

source_if_exists() {
  local setup="$1"
  if [[ -f "${setup}" ]]; then
    # shellcheck disable=SC1090
    source "${setup}"
  fi
}

set +u
source_if_exists /opt/ros/humble/setup.bash
source_if_exists "${GO2_WS}/install/setup.bash"
source_if_exists "${ROUGHNAV_WS}/install/setup.bash"
set -u

export ROS_DOMAIN_ID
export RMW_IMPLEMENTATION

mkdir -p "${EVIDENCE_DIR}"

cleanup() {
  if [[ -n "${CAMERA_PID:-}" ]]; then
    kill "${CAMERA_PID}" 2>/dev/null || true
    wait "${CAMERA_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [[ "${LAUNCH_GO2_FRONT_CAMERA_BRIDGE}" == "true" ]]; then
  echo "Starting Go2 front camera bridge on ${IMAGE_TOPIC}..."
  ros2 run go2_roughnav icros2026_front_camera_bridge --ros-args \
    -p network_interface:="${NETWORK_INTERFACE}" \
    -p image_topic:="${IMAGE_TOPIC}" &
  CAMERA_PID="$!"
  sleep 2
fi

extra_args=()
if [[ "${SAVE_ALL_DETECTIONS}" == "true" ]]; then
  extra_args+=(--save-all-detections)
fi
if [[ "${PUBLISH_DEBUG_IMAGE}" != "true" ]]; then
  extra_args+=(--no-debug-image)
fi

exec python3 "${GO2_DIR}/tools/icros2026_qr_vision_node.py" \
  --model "${MODEL_PATH}" \
  --image-topic "${IMAGE_TOPIC}" \
  --evidence-dir "${EVIDENCE_DIR}" \
  --process-hz "${PROCESS_HZ}" \
  --conf "${CONF}" \
  --imgsz "${IMGSZ}" \
  --crop-margin-ratio "${CROP_MARGIN_RATIO}" \
  "${extra_args[@]}"
