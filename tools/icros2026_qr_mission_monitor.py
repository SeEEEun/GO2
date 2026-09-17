#!/usr/bin/env python3
"""Bridge QR vision results into ICROS2026 mission completion messages.

This node is intentionally motion-free. It watches mission request topics and
QR vision outputs, then publishes mission status/done JSON when the requested
QR/photo evidence is observed. It never publishes velocity, Sport, SDK, or
low-level Go2 commands.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import rclpy
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from std_msgs.msg import Bool, String


QR_TYPES = {
    "qr",
    "qr_photo",
    "photo",
    "take_photo",
    "camera",
    "camera_photo",
    "qr_capture",
    "qr_detect",
}


@dataclass
class ActiveMission:
    mission_id: str
    mission_type: str
    zone: int | None
    color: str
    side: str
    wall_id: str
    require_decode: bool
    allow_detected_only: bool
    timeout_s: float
    started_monotonic: float
    raw: dict[str, Any]


def _load_payload(text: str) -> dict[str, Any] | None:
    text = text.strip()
    if not text:
        return None
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        data = _parse_key_value(text)
    if isinstance(data, dict):
        return data
    return None


def _parse_key_value(text: str) -> dict[str, str]:
    data: dict[str, str] = {}
    normalized = text.replace(",", ";")
    for item in normalized.split(";"):
        item = item.strip()
        if not item or "=" not in item:
            continue
        key, value = item.split("=", 1)
        key = key.strip()
        value = value.strip()
        if key:
            data[key] = value
    return data


def _first(data: dict[str, Any], *keys: str, default: Any = "") -> Any:
    for key in keys:
        if key in data and data[key] not in (None, ""):
            return data[key]
    return default


def _str_lower(value: Any) -> str:
    return str(value).strip().lower()


def _as_int(value: Any) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _as_float(value: Any, default: float) -> float:
    try:
        result = float(value)
    except (TypeError, ValueError):
        return default
    if result <= 0:
        return default
    return result


def _as_bool(value: Any, default: bool) -> bool:
    if isinstance(value, bool):
        return value
    if value is None or value == "":
        return default
    lowered = str(value).strip().lower()
    if lowered in {"1", "true", "yes", "y", "on"}:
        return True
    if lowered in {"0", "false", "no", "n", "off"}:
        return False
    return default


def _normalize_mission_type(value: Any) -> str:
    text = _str_lower(value).replace("-", "_").replace(" ", "_")
    if text in QR_TYPES:
        return "qr_photo"
    return text


def _safe_filename(value: str) -> str:
    safe = re.sub(r"[^A-Za-z0-9_.-]+", "_", value.strip())
    return safe.strip("._") or "mission"


def _mission_side(zone: int | None, color: str, explicit_side: str) -> str:
    if explicit_side in {"left", "right"}:
        return explicit_side
    # Orientation example: zone 3 orange -> right QR, red -> left QR.
    if zone == 3 and color == "orange":
        return "right"
    if zone == 3 and color == "red":
        return "left"
    return explicit_side


class IcrosQrMissionMonitor(Node):
    def __init__(
        self,
        mission_topics: list[str],
        qr_result_topic: str,
        status_topic: str,
        done_topic: str,
        result_topic: str,
        evidence_topic: str,
        mission_evidence_dir: Path,
        default_timeout_s: float,
        require_decode: bool,
        allow_detected_only: bool,
        max_result_age_s: float,
    ) -> None:
        super().__init__("icros2026_qr_mission_monitor")
        self.default_timeout_s = default_timeout_s
        self.default_require_decode = require_decode
        self.default_allow_detected_only = allow_detected_only
        self.max_result_age_s = max_result_age_s
        self.mission_evidence_dir = mission_evidence_dir

        self.status_pub = self.create_publisher(String, status_topic, 10)
        self.done_pub = self.create_publisher(Bool, done_topic, 10)
        self.result_pub = self.create_publisher(String, result_topic, 10)
        self.evidence_pub = self.create_publisher(String, evidence_topic, 10)
        self.create_subscription(String, qr_result_topic, self._qr_cb, 10)
        for topic in mission_topics:
            self.create_subscription(String, topic, self._mission_cb, 10)
        self.create_timer(0.5, self._timer_cb)

        self.active: ActiveMission | None = None
        self.last_qr_result: dict[str, Any] | None = None
        self.last_qr_arrival = 0.0
        self.last_status: dict[str, Any] = {
            "state": "WAIT_MISSION",
            "motion_commanded": False,
            "mission_topics": mission_topics,
            "qr_result_topic": qr_result_topic,
        }

        self.get_logger().info(
            "ICROS2026 QR mission monitor ready: "
            f"missions={mission_topics}, qr={qr_result_topic}, "
            f"done={done_topic}, result={result_topic}, require_decode={require_decode}, "
            f"allow_detected_only={allow_detected_only}"
        )

    def _mission_cb(self, msg: String) -> None:
        payload = _load_payload(msg.data)
        if payload is None:
            self._publish_status({"state": "MISSION_PARSE_ERROR", "raw": msg.data, "motion_commanded": False})
            return

        mission = self._normalize_mission(payload)
        if mission is None:
            mission_type = _normalize_mission_type(
                _first(payload, "mission_type", "type", "action_type", "action", default="")
            )
            self._publish_status(
                {
                    "state": "IGNORED_NON_QR_MISSION",
                    "mission_type": mission_type,
                    "raw": payload,
                    "motion_commanded": False,
                }
            )
            return

        self.active = mission
        self.get_logger().info(
            "QR mission armed: "
            f"id={mission.mission_id}, zone={mission.zone}, color={mission.color}, "
            f"side={mission.side}, timeout={mission.timeout_s:.1f}s"
        )
        self._publish_status(self._active_status("MISSION_QR_ACTIVE"))
        self._try_complete_from_latest_qr()

    def _normalize_mission(self, payload: dict[str, Any]) -> ActiveMission | None:
        zone = _as_int(_first(payload, "zone", "target_zone", "zone_id", default=None))
        color = _str_lower(_first(payload, "color", "light", "stack_light", default=""))
        mission_type = _normalize_mission_type(
            _first(payload, "mission_type", "type", "action_type", "action", default="")
        )
        if not mission_type and zone == 3 and color in {"orange", "red"}:
            mission_type = "qr_photo"
        if mission_type != "qr_photo":
            return None

        side = _mission_side(zone, color, _str_lower(_first(payload, "side", "wall_side", default="")))
        mission_id = str(
            _first(payload, "mission_id", "id", default=f"qr_zone{zone or 'unknown'}_{int(time.time())}")
        )
        require_decode = _as_bool(_first(payload, "require_decode", default=None), self.default_require_decode)
        allow_detected_only = _as_bool(
            _first(payload, "allow_detected_only", "detected_only_ok", default=None),
            self.default_allow_detected_only,
        )
        timeout_s = _as_float(_first(payload, "timeout_s", "timeout", "duration_s", default=None), self.default_timeout_s)
        wall_id = str(_first(payload, "wall_id", "target_wall", default="")).strip()

        return ActiveMission(
            mission_id=mission_id,
            mission_type=mission_type,
            zone=zone,
            color=color,
            side=side,
            wall_id=wall_id,
            require_decode=require_decode,
            allow_detected_only=allow_detected_only,
            timeout_s=timeout_s,
            started_monotonic=time.monotonic(),
            raw=payload,
        )

    def _qr_cb(self, msg: String) -> None:
        payload = _load_payload(msg.data)
        if payload is None:
            return
        self.last_qr_result = payload
        self.last_qr_arrival = time.monotonic()
        self._try_complete_from_latest_qr()

    def _timer_cb(self) -> None:
        if self.active is None:
            state = "WAIT_MISSION"
            if self.last_qr_result:
                state = f"WAIT_MISSION_QR_{_str_lower(self.last_qr_result.get('state', 'unknown')).upper()}"
            self._publish_status({"state": state, "motion_commanded": False})
            return

        elapsed = time.monotonic() - self.active.started_monotonic
        if elapsed > self.active.timeout_s:
            status = self._active_status("MISSION_QR_TIMEOUT")
            status["elapsed_s"] = round(elapsed, 3)
            status["last_qr_state"] = self._last_qr_state()
            self._publish_status(status)
            self.get_logger().warn(
                f"QR mission timeout: id={self.active.mission_id}, elapsed={elapsed:.1f}s"
            )
            self.active = None
            return

        self._publish_status(self._active_status("MISSION_QR_ACTIVE"))

    def _try_complete_from_latest_qr(self) -> None:
        if self.active is None or self.last_qr_result is None:
            return
        if self.last_qr_arrival < self.active.started_monotonic:
            return
        if time.monotonic() - self.last_qr_arrival > self.max_result_age_s:
            return
        success, reason = self._qr_satisfies_mission(self.last_qr_result, self.active)
        if not success:
            status = self._active_status("MISSION_QR_WAITING")
            status["wait_reason"] = reason
            status["last_qr_state"] = self._last_qr_state()
            self._publish_status(status)
            return

        mission = self.active
        qr = self._qr_summary(self.last_qr_result)
        done = {
            "state": "DONE",
            "result": "qr_success",
            "mission_id": mission.mission_id,
            "mission_type": mission.mission_type,
            "zone": mission.zone,
            "color": mission.color,
            "side": mission.side,
            "wall_id": mission.wall_id,
            "qr": qr,
            "motion_commanded": False,
            "stamp_monotonic": round(time.monotonic(), 6),
        }
        mission_evidence = self._save_mission_evidence(mission, qr, done)
        done["mission_evidence"] = mission_evidence
        payload = json.dumps(done, ensure_ascii=False)
        status = dict(done)
        status["state"] = "MISSION_QR_SUCCESS"
        self.evidence_pub.publish(String(data=payload))
        self.result_pub.publish(String(data=payload))
        self.done_pub.publish(Bool(data=True))
        self._publish_status(status)
        self.get_logger().info(
            "QR mission complete: "
            f"id={mission.mission_id}, text={qr.get('decoded_text', '')!r}, "
            f"saved={qr.get('saved', {})}"
        )
        self.active = None

    def _save_mission_evidence(
        self,
        mission: ActiveMission,
        qr: dict[str, Any],
        done: dict[str, Any],
    ) -> dict[str, Any]:
        safe_id = _safe_filename(mission.mission_id)
        ts = time.strftime("%Y%m%d_%H%M%S")
        directory = self.mission_evidence_dir / f"{ts}_{safe_id}"
        directory.mkdir(parents=True, exist_ok=True)

        copied: dict[str, str] = {}
        saved = qr.get("saved", {})
        if isinstance(saved, dict):
            copy_names = {
                "raw_image": "photo_raw.jpg",
                "debug_image": "photo_debug.jpg",
                "crop_image": "qr_crop.jpg",
                "metadata": "qr_metadata.json",
            }
            for key, filename in copy_names.items():
                src_text = saved.get(key)
                if not src_text:
                    continue
                src = Path(str(src_text)).expanduser()
                if not src.exists() or not src.is_file():
                    copied[f"{key}_missing"] = str(src)
                    continue
                dst = directory / filename
                shutil.copy2(src, dst)
                copied[key] = str(dst)

        result_path = directory / "mission_result.json"
        result_payload = dict(done)
        result_payload["mission_evidence"] = {
            "directory": str(directory),
            **copied,
            "mission_result": str(result_path),
        }
        result_path.write_text(json.dumps(result_payload, ensure_ascii=False, indent=2), encoding="utf-8")
        return {
            "directory": str(directory),
            **copied,
            "mission_result": str(result_path),
        }

    def _qr_satisfies_mission(self, qr: dict[str, Any], mission: ActiveMission) -> tuple[bool, str]:
        state = _str_lower(qr.get("state", ""))
        decoded_text = str(qr.get("decoded_text", "") or "")
        detections = qr.get("detections", [])
        has_detection = isinstance(detections, list) and len(detections) > 0

        if decoded_text:
            return True, "decoded"
        if mission.require_decode and not decoded_text:
            return False, "decode_required"
        if (mission.allow_detected_only or not mission.require_decode) and has_detection:
            return True, "detected_only_allowed"
        return False, "no_qr_detection"

    def _active_status(self, state: str) -> dict[str, Any]:
        assert self.active is not None
        elapsed = time.monotonic() - self.active.started_monotonic
        return {
            "state": state,
            "mission_id": self.active.mission_id,
            "mission_type": self.active.mission_type,
            "zone": self.active.zone,
            "color": self.active.color,
            "side": self.active.side,
            "wall_id": self.active.wall_id,
            "require_decode": self.active.require_decode,
            "allow_detected_only": self.active.allow_detected_only,
            "elapsed_s": round(elapsed, 3),
            "timeout_s": round(self.active.timeout_s, 3),
            "motion_commanded": False,
        }

    def _last_qr_state(self) -> dict[str, Any]:
        if not self.last_qr_result:
            return {"state": "NO_QR_RESULT_YET"}
        return self._qr_summary(self.last_qr_result)

    def _qr_summary(self, qr: dict[str, Any]) -> dict[str, Any]:
        detections = qr.get("detections", [])
        detection_count = len(detections) if isinstance(detections, list) else 0
        return {
            "state": qr.get("state", ""),
            "decoded_text": qr.get("decoded_text", ""),
            "decoded_source": qr.get("decoded_source", ""),
            "decoded_bbox_xyxy": qr.get("decoded_bbox_xyxy", []),
            "detection_count": detection_count,
            "frame_id": qr.get("frame_id", ""),
            "frame_count": qr.get("frame_count", 0),
            "saved": qr.get("saved", {}),
        }

    def _publish_status(self, payload: dict[str, Any]) -> None:
        self.last_status = payload
        self.status_pub.publish(String(data=json.dumps(payload, ensure_ascii=False)))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Monitor ICROS2026 QR/photo mission completion.")
    parser.add_argument(
        "--mission-topics",
        default="/icros2026/mission/request,/icros2026/mission/normalized",
        help="Comma-separated std_msgs/String JSON mission topics to subscribe to.",
    )
    parser.add_argument("--qr-result-topic", default="/icros2026/vision/qr/result")
    parser.add_argument("--status-topic", default="/icros2026/mission/status")
    parser.add_argument("--done-topic", default="/icros2026/mission_done")
    parser.add_argument("--result-topic", default="/icros2026/mission/result")
    parser.add_argument("--evidence-topic", default="/icros2026/mission/qr_evidence")
    parser.add_argument("--mission-evidence-dir", default="/home/jairlab/GO2/artifacts/mission_evidence")
    parser.add_argument("--default-timeout-s", type=float, default=30.0)
    parser.add_argument("--require-decode", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--allow-detected-only", action="store_true")
    parser.add_argument("--max-result-age-s", type=float, default=2.0)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    mission_topics = [topic.strip() for topic in args.mission_topics.split(",") if topic.strip()]
    if not mission_topics:
        raise ValueError("at least one mission topic is required")

    rclpy.init()
    node = IcrosQrMissionMonitor(
        mission_topics=mission_topics,
        qr_result_topic=args.qr_result_topic,
        status_topic=args.status_topic,
        done_topic=args.done_topic,
        result_topic=args.result_topic,
        evidence_topic=args.evidence_topic,
        mission_evidence_dir=Path(args.mission_evidence_dir).expanduser(),
        default_timeout_s=args.default_timeout_s,
        require_decode=args.require_decode,
        allow_detected_only=args.allow_detected_only,
        max_result_age_s=args.max_result_age_s,
    )
    try:
        rclpy.spin(node)
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    finally:
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    main()
