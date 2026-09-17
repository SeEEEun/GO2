#!/usr/bin/env bash
set -euo pipefail

GO2_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GO2_WS="${GO2_WS:-/home/jairlab/go2_ws}"
ROUGHNAV_WS="${ROUGHNAV_WS:-/home/jairlab/go2_roughnav_ws}"

: "${ROS_DOMAIN_ID:=188}"
: "${RMW_IMPLEMENTATION:=rmw_cyclonedds_cpp}"
: "${IMAGE_TOPIC:=/go2/usb_camera/image_raw}"
: "${MODEL_PATH:=${GO2_DIR}/models/qr/best.pt}"
: "${QR_TEXT:=ICROS2026_SYNTHETIC_QR}"
: "${TIMEOUT_S:=30}"

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
TMP_DIR="$(mktemp -d /tmp/go2_qr_synthetic.XXXXXX)"

cleanup() {
  for pid in "${PIDS[@]:-}"; do
    kill "${pid}" 2>/dev/null || true
  done
  for pid in "${PIDS[@]:-}"; do
    wait "${pid}" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

python3 "${GO2_DIR}/tools/icros2026_qr_vision_node.py" \
  --model "${MODEL_PATH}" \
  --image-topic "${IMAGE_TOPIC}" \
  --process-hz 5.0 \
  --save-all-detections &
PIDS+=("$!")

python3 "${GO2_DIR}/tools/icros2026_mission_normalizer.py" \
  --default-timeout-s "${TIMEOUT_S}" &
PIDS+=("$!")

python3 "${GO2_DIR}/tools/icros2026_qr_mission_monitor.py" \
  --mission-topics /icros2026/mission/request \
  --default-timeout-s "${TIMEOUT_S}" \
  --mission-evidence-dir "${GO2_DIR}/artifacts/mission_evidence" &
PIDS+=("$!")

sleep 3

python3 "${GO2_DIR}/tools/wait_for_topic_once.py" \
  --topic /icros2026/mission_done \
  --type std_msgs/msg/Bool \
  --timeout-s "${TIMEOUT_S}" >"${TMP_DIR}/mission_done.txt" &
DONE_ECHO_PID="$!"
PIDS+=("${DONE_ECHO_PID}")
python3 "${GO2_DIR}/tools/wait_for_topic_once.py" \
  --topic /icros2026/mission/result \
  --type std_msgs/msg/String \
  --timeout-s "${TIMEOUT_S}" >"${TMP_DIR}/mission_result.txt" &
RESULT_ECHO_PID="$!"
PIDS+=("${RESULT_ECHO_PID}")

MISSION_ID="synthetic_qr_$(date +%Y%m%d_%H%M%S)" \
MISSION_TOPIC=/icros2026/organizer/mission \
ZONE=3 COLOR=orange SIDE=right WALL_ID=right_wall TIMEOUT_S="${TIMEOUT_S}" \
"${GO2_DIR}/scripts/mock_qr_photo_mission.sh" >"${TMP_DIR}/mock_mission.log"

python3 "${GO2_DIR}/tools/publish_synthetic_qr_image.py" \
  --topic "${IMAGE_TOPIC}" \
  --text "${QR_TEXT}" \
  --count 20 \
  --rate-hz 8.0 >"${TMP_DIR}/synthetic_qr.log" 2>&1

wait "${DONE_ECHO_PID}"
wait "${RESULT_ECHO_PID}"
echo "[synthetic-test] mission_done:"
cat "${TMP_DIR}/mission_done.txt"
echo "[synthetic-test] mission_result:"
cat "${TMP_DIR}/mission_result.txt"
