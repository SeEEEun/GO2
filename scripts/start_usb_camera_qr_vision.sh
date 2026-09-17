#!/usr/bin/env bash
set -euo pipefail

GO2_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GO2_WS="${GO2_WS:-/home/jairlab/go2_ws}"
ROUGHNAV_WS="${ROUGHNAV_WS:-/home/jairlab/go2_roughnav_ws}"

: "${ROS_DOMAIN_ID:=0}"
: "${RMW_IMPLEMENTATION:=rmw_cyclonedds_cpp}"
: "${USB_CAMERA_DEVICE:=auto}"
: "${USB_CAMERA_TOPIC:=/go2/usb_camera/image_raw}"
: "${USB_CAMERA_STATUS_TOPIC:=/go2/usb_camera/status}"
: "${USB_CAMERA_FRAME_ID:=go2_usb_camera_optical_frame}"
: "${USB_CAMERA_WIDTH:=1280}"
: "${USB_CAMERA_HEIGHT:=720}"
: "${USB_CAMERA_FPS:=15.0}"
: "${USB_CAMERA_FOURCC:=MJPG}"

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

cleanup() {
  if [[ -n "${CAMERA_PID:-}" ]]; then
    kill "${CAMERA_PID}" 2>/dev/null || true
    wait "${CAMERA_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

python3 "${GO2_DIR}/tools/usb_camera_image_publisher.py" \
  --device "${USB_CAMERA_DEVICE}" \
  --image-topic "${USB_CAMERA_TOPIC}" \
  --status-topic "${USB_CAMERA_STATUS_TOPIC}" \
  --frame-id "${USB_CAMERA_FRAME_ID}" \
  --width "${USB_CAMERA_WIDTH}" \
  --height "${USB_CAMERA_HEIGHT}" \
  --fps "${USB_CAMERA_FPS}" \
  --fourcc "${USB_CAMERA_FOURCC}" &
CAMERA_PID="$!"

sleep 2

IMAGE_TOPIC="${USB_CAMERA_TOPIC}" "${GO2_DIR}/scripts/start_qr_vision.sh"
