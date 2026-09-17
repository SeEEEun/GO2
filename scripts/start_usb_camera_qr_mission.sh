#!/usr/bin/env bash
set -euo pipefail

GO2_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GO2_WS="${GO2_WS:-/home/jairlab/go2_ws}"
ROUGHNAV_WS="${ROUGHNAV_WS:-/home/jairlab/go2_roughnav_ws}"

: "${ROS_DOMAIN_ID:=88}"
: "${RMW_IMPLEMENTATION:=rmw_cyclonedds_cpp}"
: "${USB_CAMERA_DEVICE:=auto}"
: "${USB_CAMERA_TOPIC:=/go2/usb_camera/image_raw}"
: "${USB_CAMERA_STATUS_TOPIC:=/go2/usb_camera/status}"
: "${USB_CAMERA_FRAME_ID:=go2_usb_camera_optical_frame}"
: "${USB_CAMERA_WIDTH:=1280}"
: "${USB_CAMERA_HEIGHT:=720}"
: "${USB_CAMERA_FPS:=15.0}"
: "${USB_CAMERA_FOURCC:=MJPG}"

: "${MODEL_PATH:=${GO2_DIR}/models/qr/best.pt}"
: "${QR_RESULT_TOPIC:=/icros2026/vision/qr/result}"
: "${QR_STATUS_TOPIC:=/icros2026/vision/qr/status}"
: "${QR_DEBUG_IMAGE_TOPIC:=/icros2026/vision/qr/debug_image}"
: "${QR_EVIDENCE_DIR:=${GO2_DIR}/artifacts/qr_evidence}"
: "${QR_CONF:=0.25}"
: "${QR_IMGSZ:=640}"
: "${QR_PROCESS_HZ:=3.0}"
: "${QR_SAVE_ALL_DETECTIONS:=true}"

: "${LAUNCH_MISSION_NORMALIZER:=true}"
: "${ORGANIZER_MISSION_TOPIC:=/icros2026/organizer/mission}"
: "${ORGANIZER_ZONE_TOPIC:=/icros2026/organizer/zone}"
: "${ORGANIZER_COLOR_TOPIC:=/icros2026/organizer/color}"
: "${ORGANIZER_MISSION_TYPE_TOPIC:=/icros2026/organizer/mission_type}"
: "${ORGANIZER_SIDE_TOPIC:=/icros2026/organizer/side}"
: "${ORGANIZER_DEADLINE_TOPIC:=/icros2026/organizer/deadline_s}"
: "${ORGANIZER_PASS_ALLOWED_TOPIC:=/icros2026/organizer/pass_allowed}"
: "${NORMALIZED_MISSION_TOPIC:=/icros2026/mission/normalized}"
: "${MISSION_REQUEST_TOPIC:=/icros2026/mission/request}"
: "${MISSION_NORMALIZER_STATUS_TOPIC:=/icros2026/mission_normalizer/status}"

: "${MISSION_TOPICS:=/icros2026/mission/request}"
: "${MISSION_STATUS_TOPIC:=/icros2026/mission/status}"
: "${MISSION_DONE_TOPIC:=/icros2026/mission_done}"
: "${MISSION_RESULT_TOPIC:=/icros2026/mission/result}"
: "${MISSION_QR_EVIDENCE_TOPIC:=/icros2026/mission/qr_evidence}"
: "${MISSION_EVIDENCE_DIR:=${GO2_DIR}/artifacts/mission_evidence}"
: "${MISSION_TIMEOUT_S:=30.0}"
: "${MISSION_REQUIRE_DECODE:=true}"
: "${MISSION_ALLOW_DETECTED_ONLY:=false}"

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

PIDS=()

cleanup() {
  for pid in "${PIDS[@]:-}"; do
    kill "${pid}" 2>/dev/null || true
  done
  for pid in "${PIDS[@]:-}"; do
    wait "${pid}" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

if [[ ! -f "${MODEL_PATH}" ]]; then
  echo "QR model not found: ${MODEL_PATH}" >&2
  exit 1
fi

echo "[qr-mission] ROS_DOMAIN_ID=${ROS_DOMAIN_ID}"
echo "[qr-mission] camera=${USB_CAMERA_DEVICE} -> ${USB_CAMERA_TOPIC}"
echo "[qr-mission] model=${MODEL_PATH}"
echo "[qr-mission] organizer_raw=${ORGANIZER_MISSION_TOPIC}"
echo "[qr-mission] normalized=${NORMALIZED_MISSION_TOPIC}"
echo "[qr-mission] request=${MISSION_REQUEST_TOPIC}"
echo "[qr-mission] mission_topics=${MISSION_TOPICS}"
echo "[qr-mission] no Go2 motion or Sport command will be started"

python3 "${GO2_DIR}/tools/usb_camera_image_publisher.py" \
  --device "${USB_CAMERA_DEVICE}" \
  --image-topic "${USB_CAMERA_TOPIC}" \
  --status-topic "${USB_CAMERA_STATUS_TOPIC}" \
  --frame-id "${USB_CAMERA_FRAME_ID}" \
  --width "${USB_CAMERA_WIDTH}" \
  --height "${USB_CAMERA_HEIGHT}" \
  --fps "${USB_CAMERA_FPS}" \
  --fourcc "${USB_CAMERA_FOURCC}" &
PIDS+=("$!")

sleep 2

QR_ARGS=(
  --model "${MODEL_PATH}"
  --image-topic "${USB_CAMERA_TOPIC}"
  --result-topic "${QR_RESULT_TOPIC}"
  --status-topic "${QR_STATUS_TOPIC}"
  --debug-image-topic "${QR_DEBUG_IMAGE_TOPIC}"
  --evidence-dir "${QR_EVIDENCE_DIR}"
  --conf "${QR_CONF}"
  --imgsz "${QR_IMGSZ}"
  --process-hz "${QR_PROCESS_HZ}"
)
if [[ "${QR_SAVE_ALL_DETECTIONS}" == "true" ]]; then
  QR_ARGS+=(--save-all-detections)
fi

python3 "${GO2_DIR}/tools/icros2026_qr_vision_node.py" "${QR_ARGS[@]}" &
PIDS+=("$!")

if [[ "${LAUNCH_MISSION_NORMALIZER}" == "true" ]]; then
  python3 "${GO2_DIR}/tools/icros2026_mission_normalizer.py" \
    --raw-mission-topic "${ORGANIZER_MISSION_TOPIC}" \
    --zone-topic "${ORGANIZER_ZONE_TOPIC}" \
    --color-topic "${ORGANIZER_COLOR_TOPIC}" \
    --mission-type-topic "${ORGANIZER_MISSION_TYPE_TOPIC}" \
    --side-topic "${ORGANIZER_SIDE_TOPIC}" \
    --deadline-topic "${ORGANIZER_DEADLINE_TOPIC}" \
    --pass-allowed-topic "${ORGANIZER_PASS_ALLOWED_TOPIC}" \
    --normalized-topic "${NORMALIZED_MISSION_TOPIC}" \
    --request-topic "${MISSION_REQUEST_TOPIC}" \
    --status-topic "${MISSION_NORMALIZER_STATUS_TOPIC}" \
    --default-timeout-s "${MISSION_TIMEOUT_S}" &
  PIDS+=("$!")
fi

MISSION_ARGS=(
  --mission-topics "${MISSION_TOPICS}"
  --qr-result-topic "${QR_RESULT_TOPIC}"
  --status-topic "${MISSION_STATUS_TOPIC}"
  --done-topic "${MISSION_DONE_TOPIC}"
  --result-topic "${MISSION_RESULT_TOPIC}"
  --evidence-topic "${MISSION_QR_EVIDENCE_TOPIC}"
  --mission-evidence-dir "${MISSION_EVIDENCE_DIR}"
  --default-timeout-s "${MISSION_TIMEOUT_S}"
)
if [[ "${MISSION_REQUIRE_DECODE}" != "true" ]]; then
  MISSION_ARGS+=(--no-require-decode)
fi
if [[ "${MISSION_ALLOW_DETECTED_ONLY}" == "true" ]]; then
  MISSION_ARGS+=(--allow-detected-only)
fi

python3 "${GO2_DIR}/tools/icros2026_qr_mission_monitor.py" "${MISSION_ARGS[@]}" &
PIDS+=("$!")

echo "[qr-mission] running. Useful checks:"
echo "  ros2 topic echo ${USB_CAMERA_STATUS_TOPIC}"
echo "  ros2 topic echo ${QR_STATUS_TOPIC}"
echo "  ros2 topic echo ${MISSION_NORMALIZER_STATUS_TOPIC}"
echo "  ros2 topic echo ${MISSION_STATUS_TOPIC}"
echo "  ros2 topic echo ${MISSION_DONE_TOPIC}"
echo "  ros2 topic echo ${MISSION_RESULT_TOPIC}"
echo "  rqt_image_view ${QR_DEBUG_IMAGE_TOPIC}"

wait -n "${PIDS[@]}"
