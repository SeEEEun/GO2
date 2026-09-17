#!/usr/bin/env python3
"""Normalize ICROS2026 organizer mission messages for the GO2 QR pipeline.

This node is motion-free. It accepts organizer mission messages in common
String JSON/key-value forms plus a small set of typed std_msgs topics, applies
the known ICROS2026 orange/red mission mapping, and publishes normalized JSON
for downstream mission handlers.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import time
from dataclasses import asdict, dataclass, field
from typing import Any

import rclpy
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from std_msgs.msg import Bool, Float32, Int32, String


SCHEMA = "icros2026.go2.normalized_mission.v1"

DEFAULT_RULE_ACTIONS = {
    (2, "orange"): {"mission_type": "wall_touch", "side": "left", "wall_id": "left_wall"},
    (2, "red"): {"mission_type": "wall_touch", "side": "right", "wall_id": "right_wall"},
    (3, "orange"): {"mission_type": "qr_photo", "side": "right", "wall_id": "right_wall"},
    (3, "red"): {"mission_type": "qr_photo", "side": "left", "wall_id": "left_wall"},
}

KEY_ALIASES = {
    "target": "zone",
    "target_zone": "zone",
    "goal": "zone",
    "goal_zone": "zone",
    "destination": "zone",
    "dest": "zone",
    "section": "zone",
    "segment": "zone",
    "stack_light": "color",
    "light": "color",
    "lamp": "color",
    "mission": "mission_type",
    "task": "mission_type",
    "action": "mission_type",
    "type": "mission_type",
    "wall": "wall_id",
    "target_wall": "wall_id",
    "deadline": "timeout_s",
    "deadline_s": "timeout_s",
    "deadline_sec": "timeout_s",
    "time_limit": "timeout_s",
    "timeout": "timeout_s",
    "timeout_sec": "timeout_s",
    "pass": "pass_allowed",
}

COLOR_ALIASES = {
    "amber": "orange",
    "orange": "orange",
    "yellow": "orange",
    "red": "red",
}

SIDE_ALIASES = {
    "l": "left",
    "left": "left",
    "left_wall": "left",
    "r": "right",
    "right": "right",
    "right_wall": "right",
}

MISSION_ALIASES = {
    "qr": "qr_photo",
    "qrcode": "qr_photo",
    "qr_code": "qr_photo",
    "qr_photo": "qr_photo",
    "qrphoto": "qr_photo",
    "photo": "qr_photo",
    "camera": "qr_photo",
    "image": "qr_photo",
    "capture": "qr_photo",
    "take_photo": "qr_photo",
    "wall_touch": "wall_touch",
    "walltouch": "wall_touch",
    "touch": "wall_touch",
    "contact": "wall_touch",
    "button": "wall_touch",
    "press": "wall_touch",
    "dry_run": "dry_run",
    "dryrun": "dry_run",
}


@dataclass
class NormalizedMission:
    schema: str = SCHEMA
    mission_id: str = ""
    source: str = ""
    raw: str = ""
    stamp_monotonic: float = 0.0
    zone: int | None = None
    color: str | None = None
    mission_type: str | None = None
    side: str | None = None
    wall_id: str | None = None
    timeout_s: float | None = None
    pass_allowed: bool | None = None
    require_decode: bool = True
    executor_mode: str | None = None
    motion_commanded: bool = False
    warnings: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)


def _canonical_key(key: str) -> str:
    text = str(key).strip().lower().replace("-", "_")
    return KEY_ALIASES.get(text, text)


def _strip_value(value: Any) -> str:
    return str(value).strip().strip("\"'")


def _parse_bool(value: Any) -> bool | None:
    if isinstance(value, bool):
        return value
    text = _strip_value(value).lower()
    if text in {"1", "true", "yes", "y", "on", "allowed", "allow"}:
        return True
    if text in {"0", "false", "no", "n", "off", "deny", "denied"}:
        return False
    return None


def _parse_int(value: Any) -> int | None:
    try:
        return int(_strip_value(value).replace("zone", "").replace("#", "").strip())
    except (TypeError, ValueError):
        return None


def _parse_zone(value: Any, raw: str = "") -> int | None:
    zone = _parse_int(value)
    if zone is not None:
        return zone
    match = re.search(r"(?:zone|target|destination|dest|section|segment|goal)\s*[:=#-]?\s*(?:zone)?\s*([1-4])", raw.lower())
    if match:
        return int(match.group(1))
    match = re.search(r"\b([1-4])\b", raw)
    return int(match.group(1)) if match else None


def _parse_color(value: Any, raw: str = "") -> str | None:
    text = _strip_value(value).lower()
    if text in COLOR_ALIASES:
        return COLOR_ALIASES[text]
    raw_lower = raw.lower()
    if re.search(r"\b(orange|amber|yellow)\b", raw_lower):
        return "orange"
    if re.search(r"\bred\b", raw_lower):
        return "red"
    return None


def _parse_side(value: Any, raw: str = "") -> str | None:
    text = _strip_value(value).lower()
    if text in SIDE_ALIASES:
        return SIDE_ALIASES[text]
    raw_lower = raw.lower()
    if re.search(r"\bleft(?:_wall|\s+wall)?\b", raw_lower):
        return "left"
    if re.search(r"\bright(?:_wall|\s+wall)?\b", raw_lower):
        return "right"
    return None


def _parse_mission_type(value: Any, raw: str = "") -> str | None:
    text = _strip_value(value).lower().replace("-", "_").replace(" ", "_")
    if text in MISSION_ALIASES:
        return MISSION_ALIASES[text]
    raw_lower = raw.lower()
    if re.search(r"\b(qr|qrcode|qr[_ -]?photo|photo|camera|image|capture)\b", raw_lower):
        return "qr_photo"
    if re.search(r"\b(wall[_ -]?touch|touch|contact|button|press)\b", raw_lower):
        return "wall_touch"
    if re.search(r"\bdry[_ -]?run\b", raw_lower):
        return "dry_run"
    return None


def _parse_float(value: Any) -> float | None:
    try:
        number = float(_strip_value(value).rstrip("s"))
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) and number > 0 else None


def _parse_key_values(raw: str) -> dict[str, Any]:
    fields: dict[str, Any] = {}
    for key, value in re.findall(r"([A-Za-z_][A-Za-z0-9_.-]*)\s*[:=]\s*(\"[^\"]+\"|'[^']+'|[^,;\s]+)", raw):
        fields[_canonical_key(key)] = _strip_value(value)
    return fields


def parse_raw_fields(raw: str) -> dict[str, Any]:
    text = raw.strip()
    if not text:
        return {}
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        data = None
    if isinstance(data, dict):
        return {_canonical_key(str(key)): value for key, value in data.items()}
    return _parse_key_values(text)


def _executor_mode(mission_type: str | None) -> str | None:
    if mission_type == "qr_photo":
        return "qr_photo"
    if mission_type == "wall_touch":
        return "blocked_wall_touch"
    if mission_type == "dry_run":
        return "dry_run"
    return None


def normalize_mission(
    fields: dict[str, Any],
    *,
    raw: str,
    source: str,
    sequence: int,
    default_timeout_s: float,
    require_decode_default: bool,
    use_default_rule_mapping: bool,
) -> NormalizedMission:
    mission = NormalizedMission(source=source, raw=raw, stamp_monotonic=time.monotonic())
    canonical = {_canonical_key(key): value for key, value in fields.items()}

    mission.zone = _parse_zone(canonical.get("zone", ""), raw)
    mission.color = _parse_color(canonical.get("color", ""), raw)
    mission.mission_type = _parse_mission_type(canonical.get("mission_type", ""), raw)
    mission.side = _parse_side(canonical.get("side", ""), raw)

    wall_id = canonical.get("wall_id")
    if wall_id not in (None, ""):
        mission.wall_id = _strip_value(wall_id)

    timeout = canonical.get("timeout_s")
    mission.timeout_s = _parse_float(timeout) if timeout not in (None, "") else default_timeout_s
    if mission.timeout_s is None:
        mission.timeout_s = default_timeout_s
        mission.warnings.append("invalid_timeout_s")

    require_decode = _parse_bool(canonical.get("require_decode", ""))
    mission.require_decode = require_decode_default if require_decode is None else require_decode

    pass_allowed = canonical.get("pass_allowed")
    if pass_allowed not in (None, ""):
        mission.pass_allowed = _parse_bool(pass_allowed)
        if mission.pass_allowed is None:
            mission.warnings.append("invalid_pass_allowed")

    if use_default_rule_mapping and mission.zone is not None and mission.color is not None:
        rule = DEFAULT_RULE_ACTIONS.get((mission.zone, mission.color))
        if rule is not None:
            if mission.mission_type is None:
                mission.mission_type = str(rule["mission_type"])
            if mission.side is None:
                mission.side = str(rule["side"])
            if mission.wall_id is None:
                mission.wall_id = str(rule["wall_id"])

    if mission.wall_id is None and mission.side in {"left", "right"}:
        mission.wall_id = f"{mission.side}_wall"

    if mission.zone is not None and mission.zone not in {1, 2, 3, 4}:
        mission.errors.append("zone_out_of_range")
    if mission.color is not None and mission.color not in {"orange", "red"}:
        mission.errors.append("color_out_of_range")
    if mission.side is not None and mission.side not in {"left", "right"}:
        mission.errors.append("side_out_of_range")
    if mission.zone is None:
        mission.warnings.append("missing_zone")
    if mission.color is None:
        mission.warnings.append("missing_color")
    if mission.mission_type is None:
        mission.warnings.append("missing_mission_type")

    mission.executor_mode = _executor_mode(mission.mission_type)
    base_id = canonical.get("mission_id") or canonical.get("id")
    mission.mission_id = str(base_id) if base_id not in (None, "") else (
        f"mission_{sequence:04d}_zone{mission.zone or 'unknown'}_{mission.color or 'unknown'}"
    )
    return mission


class IcrosMissionNormalizer(Node):
    def __init__(
        self,
        raw_mission_topic: str,
        zone_topic: str,
        color_topic: str,
        mission_type_topic: str,
        side_topic: str,
        deadline_topic: str,
        pass_allowed_topic: str,
        normalized_topic: str,
        request_topic: str,
        goal_zone_topic: str,
        status_topic: str,
        default_timeout_s: float,
        require_decode_default: bool,
        use_default_rule_mapping: bool,
        typed_field_timeout_s: float,
        publish_goal_zone: bool,
    ) -> None:
        super().__init__("icros2026_mission_normalizer")
        self.default_timeout_s = default_timeout_s
        self.require_decode_default = require_decode_default
        self.use_default_rule_mapping = use_default_rule_mapping
        self.typed_field_timeout_s = typed_field_timeout_s
        self.publish_goal_zone = publish_goal_zone
        self.sequence = 0
        self.typed_fields: dict[str, tuple[Any, float]] = {}

        self.normalized_pub = self.create_publisher(String, normalized_topic, 10)
        self.request_pub = self.create_publisher(String, request_topic, 10)
        self.goal_zone_pub = self.create_publisher(Int32, goal_zone_topic, 10)
        self.status_pub = self.create_publisher(String, status_topic, 10)

        self.create_subscription(String, raw_mission_topic, self._raw_cb, 10)
        self.create_subscription(Int32, zone_topic, self._zone_cb, 10)
        self.create_subscription(String, color_topic, self._color_cb, 10)
        self.create_subscription(String, mission_type_topic, self._mission_type_cb, 10)
        self.create_subscription(String, side_topic, self._side_cb, 10)
        self.create_subscription(Float32, deadline_topic, self._deadline_cb, 10)
        self.create_subscription(Bool, pass_allowed_topic, self._pass_allowed_cb, 10)

        self._publish_status({"state": "READY", "raw_mission_topic": raw_mission_topic, "request_topic": request_topic})
        self.get_logger().info(
            "ICROS2026 mission normalizer ready: "
            f"raw={raw_mission_topic}, normalized={normalized_topic}, request={request_topic}"
        )

    def _raw_cb(self, msg: String) -> None:
        self.sequence += 1
        mission = normalize_mission(
            parse_raw_fields(msg.data),
            raw=msg.data,
            source="organizer_raw",
            sequence=self.sequence,
            default_timeout_s=self.default_timeout_s,
            require_decode_default=self.require_decode_default,
            use_default_rule_mapping=self.use_default_rule_mapping,
        )
        self._publish_mission(mission)

    def _zone_cb(self, msg: Int32) -> None:
        self._update_typed("zone", int(msg.data))

    def _color_cb(self, msg: String) -> None:
        self._update_typed("color", msg.data)

    def _mission_type_cb(self, msg: String) -> None:
        self._update_typed("mission_type", msg.data)

    def _side_cb(self, msg: String) -> None:
        self._update_typed("side", msg.data)

    def _deadline_cb(self, msg: Float32) -> None:
        self._update_typed("timeout_s", float(msg.data))

    def _pass_allowed_cb(self, msg: Bool) -> None:
        self._update_typed("pass_allowed", bool(msg.data))

    def _update_typed(self, key: str, value: Any) -> None:
        self.typed_fields[key] = (value, time.monotonic())
        fields = self._current_typed_fields()
        raw = ";".join(f"{name}={fields[name]}" for name in sorted(fields))
        self.sequence += 1
        mission = normalize_mission(
            fields,
            raw=raw,
            source="organizer_typed",
            sequence=self.sequence,
            default_timeout_s=self.default_timeout_s,
            require_decode_default=self.require_decode_default,
            use_default_rule_mapping=self.use_default_rule_mapping,
        )
        self._publish_mission(mission)

    def _current_typed_fields(self) -> dict[str, Any]:
        now = time.monotonic()
        fields: dict[str, Any] = {}
        for key, (value, stamp) in self.typed_fields.items():
            if self.typed_field_timeout_s > 0.0 and now - stamp > self.typed_field_timeout_s:
                continue
            fields[key] = value
        return fields

    def _publish_mission(self, mission: NormalizedMission) -> None:
        payload = json.dumps(asdict(mission), ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        self.normalized_pub.publish(String(data=payload))

        request_published = False
        if not mission.errors and mission.executor_mode == "qr_photo":
            self.request_pub.publish(String(data=payload))
            request_published = True

        if self.publish_goal_zone and mission.zone is not None and not mission.errors:
            self.goal_zone_pub.publish(Int32(data=int(mission.zone)))

        status = {
            "state": "NORMALIZED",
            "mission_id": mission.mission_id,
            "zone": mission.zone,
            "color": mission.color,
            "mission_type": mission.mission_type,
            "side": mission.side,
            "wall_id": mission.wall_id,
            "executor_mode": mission.executor_mode,
            "request_published": request_published,
            "motion_commanded": False,
            "errors": mission.errors,
            "warnings": mission.warnings,
        }
        if mission.executor_mode == "blocked_wall_touch":
            status["blocked_reason"] = "wall_touch_requires_guarded_motion_stack"
        self._publish_status(status)

    def _publish_status(self, payload: dict[str, Any]) -> None:
        self.status_pub.publish(String(data=json.dumps(payload, ensure_ascii=False, sort_keys=True)))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Normalize ICROS2026 organizer missions for GO2.")
    parser.add_argument("--raw-mission-topic", default="/icros2026/organizer/mission")
    parser.add_argument("--zone-topic", default="/icros2026/organizer/zone")
    parser.add_argument("--color-topic", default="/icros2026/organizer/color")
    parser.add_argument("--mission-type-topic", default="/icros2026/organizer/mission_type")
    parser.add_argument("--side-topic", default="/icros2026/organizer/side")
    parser.add_argument("--deadline-topic", default="/icros2026/organizer/deadline_s")
    parser.add_argument("--pass-allowed-topic", default="/icros2026/organizer/pass_allowed")
    parser.add_argument("--normalized-topic", default="/icros2026/mission/normalized")
    parser.add_argument("--request-topic", default="/icros2026/mission/request")
    parser.add_argument("--goal-zone-topic", default="/icros2026/goal_zone")
    parser.add_argument("--status-topic", default="/icros2026/mission_normalizer/status")
    parser.add_argument("--default-timeout-s", type=float, default=30.0)
    parser.add_argument("--require-decode", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--use-default-rule-mapping", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--typed-field-timeout-s", type=float, default=0.0)
    parser.add_argument("--publish-goal-zone", action=argparse.BooleanOptionalAction, default=False)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    rclpy.init()
    node = IcrosMissionNormalizer(
        raw_mission_topic=args.raw_mission_topic,
        zone_topic=args.zone_topic,
        color_topic=args.color_topic,
        mission_type_topic=args.mission_type_topic,
        side_topic=args.side_topic,
        deadline_topic=args.deadline_topic,
        pass_allowed_topic=args.pass_allowed_topic,
        normalized_topic=args.normalized_topic,
        request_topic=args.request_topic,
        goal_zone_topic=args.goal_zone_topic,
        status_topic=args.status_topic,
        default_timeout_s=args.default_timeout_s,
        require_decode_default=args.require_decode,
        use_default_rule_mapping=args.use_default_rule_mapping,
        typed_field_timeout_s=args.typed_field_timeout_s,
        publish_goal_zone=args.publish_goal_zone,
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
