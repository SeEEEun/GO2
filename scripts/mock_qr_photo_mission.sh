#!/usr/bin/env bash
set -euo pipefail

GO2_WS="${GO2_WS:-/home/jairlab/go2_ws}"
ROUGHNAV_WS="${ROUGHNAV_WS:-/home/jairlab/go2_roughnav_ws}"

: "${ROS_DOMAIN_ID:=88}"
: "${RMW_IMPLEMENTATION:=rmw_cyclonedds_cpp}"
: "${MISSION_TOPIC:=/icros2026/organizer/mission}"
: "${MISSION_ID:=mock_qr_zone3_orange}"
: "${MISSION_TYPE:=qr_photo}"
: "${ZONE:=3}"
: "${COLOR:=orange}"
: "${SIDE:=right}"
: "${WALL_ID:=right_wall}"
: "${TIMEOUT_S:=30.0}"
: "${REQUIRE_DECODE:=true}"

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

python3 - "$MISSION_TOPIC" "$MISSION_ID" "$MISSION_TYPE" "$ZONE" "$COLOR" "$SIDE" "$WALL_ID" "$TIMEOUT_S" "$REQUIRE_DECODE" <<'PY'
import json
import sys
import time

import rclpy
from std_msgs.msg import String


def as_bool(text: str) -> bool:
    return text.strip().lower() in {"1", "true", "yes", "y", "on"}


topic, mission_id, mission_type, zone, color, side, wall_id, timeout_s, require_decode = sys.argv[1:]
payload = {
    "mission_id": mission_id,
    "mission_type": mission_type,
    "zone": int(zone),
    "color": color,
    "side": side,
    "wall_id": wall_id,
    "timeout_s": float(timeout_s),
    "require_decode": as_bool(require_decode),
    "source": "mock_qr_photo_mission.sh",
    "stamp_unix": time.time(),
}

rclpy.init()
node = rclpy.create_node("mock_qr_photo_mission")
pub = node.create_publisher(String, topic, 10)
msg = String()
msg.data = json.dumps(payload, ensure_ascii=False)
deadline = time.monotonic() + 1.0
while time.monotonic() < deadline:
    rclpy.spin_once(node, timeout_sec=0.05)
pub.publish(msg)
rclpy.spin_once(node, timeout_sec=0.2)
print(f"published {topic}: {msg.data}")
node.destroy_node()
rclpy.shutdown()
PY
