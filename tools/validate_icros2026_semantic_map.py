#!/usr/bin/env python3
"""Validate an ICROS2026 measured semantic map.

The validator is intentionally strict because this file is the boundary between
allowed measured course semantics and forbidden replayed/fixed movement scripts.
It does not generate coordinates and it does not infer missing zones.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any


PLACEHOLDER_STRINGS = {"", "todo", "tbd", "none", "null", "change_me", "fill_me", "example"}
REQUIRED_ZONES = {1, 2, 3, 4}
ALLOWED_MISSION_TYPES = {"wall_touch", "qr_photo", "photo", "button", "dry_run", "pass"}
ALLOWED_COLORS = {"orange", "red"}
ALLOWED_SIDES = {"left", "right"}


class Validation:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def error(self, text: str) -> None:
        self.errors.append(text)

    def warn(self, text: str) -> None:
        self.warnings.append(text)


def _load_mapping(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    if path.suffix.lower() == ".json":
        data = json.loads(text)
    else:
        try:
            import yaml  # type: ignore
        except Exception as exc:
            raise RuntimeError("PyYAML is required for YAML semantic maps") from exc
        data = yaml.safe_load(text)
    if not isinstance(data, dict):
        raise ValueError("semantic map root must be a mapping")
    return data


def _is_placeholder(value: Any) -> bool:
    if value is None:
        return True
    if isinstance(value, str):
        text = value.strip().lower()
        return text in PLACEHOLDER_STRINGS or "todo" in text or "change_me" in text
    return False


def _finite_number(value: Any) -> bool:
    if isinstance(value, bool) or _is_placeholder(value):
        return False
    try:
        return math.isfinite(float(value))
    except (TypeError, ValueError):
        return False


def _as_zone_id(key: Any, value: Any) -> int | None:
    if isinstance(value, dict):
        for field in ("id", "zone", "zone_id"):
            if field in value:
                text = str(value[field]).strip().lower().replace("zone", "")
                return int(text) if text in {"1", "2", "3", "4"} else None
    text = str(key).strip().lower().replace("zone", "")
    return int(text) if text in {"1", "2", "3", "4"} else None


def _iter_zones(data: dict[str, Any], result: Validation) -> dict[int, dict[str, Any]]:
    zones = data.get("zones")
    if zones is None:
        result.error("zones: missing required field")
        return {}
    if not isinstance(zones, (dict, list)):
        result.error("zones: must be a mapping or list")
        return {}

    items = zones.items() if isinstance(zones, dict) else enumerate(zones, start=1)
    parsed: dict[int, dict[str, Any]] = {}
    for key, value in items:
        if not isinstance(value, dict):
            result.error(f"zones.{key}: zone entry must be a mapping")
            continue
        zone = _as_zone_id(key, value)
        if zone is None:
            result.error(f"zones.{key}: cannot resolve zone id")
            continue
        if zone in parsed:
            result.error(f"zones.{key}: duplicate zone {zone}")
            continue
        parsed[zone] = value
    return parsed


def _goal_mapping(zone_id: int, zone: dict[str, Any], result: Validation) -> dict[str, Any] | None:
    goal = zone.get("goal") or zone.get("center") or zone.get("pose") or zone
    if isinstance(goal, (list, tuple)):
        if len(goal) < 2:
            result.error(f"zones.{zone_id}.goal: list must contain at least x,y")
            return None
        keys = ("x", "y", "z", "yaw")
        return {keys[idx]: value for idx, value in enumerate(goal[:4])}
    if not isinstance(goal, dict):
        result.error(f"zones.{zone_id}.goal: must be mapping or list")
        return None
    return goal


def _validate_measurement(data: dict[str, Any], result: Validation, allow_missing: bool) -> None:
    measurement = data.get("measurement") or data.get("measured_source")
    if measurement is None:
        if not allow_missing:
            result.error("measurement: missing source evidence")
        return
    if not isinstance(measurement, dict):
        result.error("measurement: must be a mapping")
        return
    for field in ("source_map", "method"):
        value = measurement.get(field)
        if _is_placeholder(value):
            result.error(f"measurement.{field}: missing measured value")
    source_frame = measurement.get("source_frame") or data.get("frame") or data.get("map_frame")
    if _is_placeholder(source_frame):
        result.error("measurement.source_frame/frame: missing frame")
    source_map = measurement.get("source_map")
    if isinstance(source_map, str) and source_map.strip() and not Path(source_map).expanduser().exists():
        result.warn(f"measurement.source_map: path does not currently exist: {source_map}")


def _validate_zones(data: dict[str, Any], result: Validation) -> None:
    parsed = _iter_zones(data, result)
    missing = REQUIRED_ZONES.difference(parsed)
    if missing:
        result.error(f"zones: missing required zones {sorted(missing)}")

    for zone_id, zone in parsed.items():
        goal = _goal_mapping(zone_id, zone, result)
        if goal is None:
            continue
        for field in ("x", "y"):
            if not _finite_number(goal.get(field)):
                result.error(f"zones.{zone_id}.goal.{field}: finite measured number required")
        for field in ("z", "yaw"):
            if field in goal and not _finite_number(goal.get(field)):
                result.error(f"zones.{zone_id}.goal.{field}: finite number required when present")
        frame = goal.get("frame") or zone.get("frame") or data.get("frame") or data.get("map_frame")
        if _is_placeholder(frame):
            result.error(f"zones.{zone_id}.frame: missing frame")

        mission_area = zone.get("mission_area")
        if mission_area is not None:
            _validate_mission_area(zone_id, mission_area, result)


def _validate_mission_area(zone_id: int, mission_area: Any, result: Validation) -> None:
    if not isinstance(mission_area, dict):
        result.error(f"zones.{zone_id}.mission_area: must be a mapping")
        return
    size = mission_area.get("size_m") or mission_area.get("size")
    if size is None:
        result.warn(f"zones.{zone_id}.mission_area.size_m: missing; expected about [1.2, 1.2]")
        return
    if not isinstance(size, (list, tuple)) or len(size) < 2:
        result.error(f"zones.{zone_id}.mission_area.size_m: must be [width, height]")
        return
    if not all(_finite_number(value) for value in size[:2]):
        result.error(f"zones.{zone_id}.mission_area.size_m: finite numbers required")
        return
    width, height = float(size[0]), float(size[1])
    if abs(width - 1.2) > 0.15 or abs(height - 1.2) > 0.15:
        result.warn(f"zones.{zone_id}.mission_area.size_m: expected near 1.2 x 1.2, got {width:.2f} x {height:.2f}")


def _validate_walls(data: dict[str, Any], result: Validation) -> set[str]:
    walls = data.get("walls", {})
    if walls is None:
        return set()
    if not isinstance(walls, dict):
        result.error("walls: must be a mapping when present")
        return set()
    wall_ids = set(str(k) for k in walls)
    for wall_id, wall in walls.items():
        if not isinstance(wall, dict):
            result.error(f"walls.{wall_id}: must be a mapping")
            continue
        points = wall.get("line") or wall.get("points")
        if points is not None:
            if not isinstance(points, (list, tuple)) or len(points) < 2:
                result.error(f"walls.{wall_id}.line: must contain at least two points")
            else:
                for idx, point in enumerate(points[:2]):
                    if not isinstance(point, dict) or not _finite_number(point.get("x")) or not _finite_number(point.get("y")):
                        result.error(f"walls.{wall_id}.line[{idx}]: point with finite x,y required")
        normal = wall.get("normal")
        if normal is not None and (
            not isinstance(normal, dict) or not _finite_number(normal.get("x")) or not _finite_number(normal.get("y"))
        ):
            result.error(f"walls.{wall_id}.normal: finite x,y required when present")
    return wall_ids


def _validate_missions(data: dict[str, Any], wall_ids: set[str], result: Validation) -> None:
    missions = data.get("missions", {})
    if missions is None:
        return
    if not isinstance(missions, dict):
        result.error("missions: must be a mapping when present")
        return
    for zone_key, by_color in missions.items():
        zone_text = str(zone_key).strip().lower().replace("zone", "")
        if zone_text not in {"1", "2", "3", "4"}:
            result.error(f"missions.{zone_key}: zone key must be 1-4 or zone1-zone4")
            continue
        if not isinstance(by_color, dict):
            result.error(f"missions.{zone_key}: must map colors to actions")
            continue
        for color, action in by_color.items():
            color_text = str(color).strip().lower()
            if color_text not in ALLOWED_COLORS:
                result.error(f"missions.{zone_key}.{color}: color must be orange or red")
            if not isinstance(action, dict):
                result.error(f"missions.{zone_key}.{color}: action must be a mapping")
                continue
            action_type = str(action.get("type", "")).strip().lower()
            if action_type not in ALLOWED_MISSION_TYPES:
                result.error(f"missions.{zone_key}.{color}.type: unsupported mission type {action_type!r}")
            side = action.get("side")
            if side is not None and str(side).strip().lower() not in ALLOWED_SIDES:
                result.error(f"missions.{zone_key}.{color}.side: side must be left or right")
            wall_id = action.get("wall_id")
            if wall_id is not None and wall_ids and str(wall_id) not in wall_ids:
                result.error(f"missions.{zone_key}.{color}.wall_id: unknown wall {wall_id!r}")


def _validate_risk_regions(data: dict[str, Any], result: Validation) -> None:
    regions = data.get("risk_regions", [])
    if regions is None:
        return
    if not isinstance(regions, list):
        result.error("risk_regions: must be a list when present")
        return
    for idx, region in enumerate(regions):
        if not isinstance(region, dict):
            result.error(f"risk_regions[{idx}]: must be a mapping")
            continue
        if _is_placeholder(region.get("id")):
            result.error(f"risk_regions[{idx}].id: missing id")
        if _is_placeholder(region.get("risk")):
            result.error(f"risk_regions[{idx}].risk: missing risk label")
        polygon = region.get("polygon")
        if polygon is not None:
            if not isinstance(polygon, list) or len(polygon) < 3:
                result.error(f"risk_regions[{idx}].polygon: at least three points required")
            for point_idx, point in enumerate(polygon if isinstance(polygon, list) else []):
                if not isinstance(point, dict) or not _finite_number(point.get("x")) or not _finite_number(point.get("y")):
                    result.error(f"risk_regions[{idx}].polygon[{point_idx}]: point with finite x,y required")


def validate(data: dict[str, Any], allow_missing_measurement: bool = False) -> Validation:
    result = Validation()
    frame = data.get("frame") or data.get("map_frame")
    if _is_placeholder(frame):
        result.error("frame/map_frame: missing frame")
    _validate_measurement(data, result, allow_missing_measurement)
    _validate_zones(data, result)
    wall_ids = _validate_walls(data, result)
    _validate_missions(data, wall_ids, result)
    _validate_risk_regions(data, result)
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("semantic_map", type=Path)
    parser.add_argument("--allow-missing-measurement", action="store_true")
    args = parser.parse_args(argv)

    try:
        data = _load_mapping(args.semantic_map)
        result = validate(data, allow_missing_measurement=args.allow_missing_measurement)
    except Exception as exc:
        print(f"ERROR load_failed: {exc}", file=sys.stderr)
        return 2

    for warning in result.warnings:
        print(f"WARN {warning}")
    for error in result.errors:
        print(f"ERROR {error}")

    if result.errors:
        print(f"FAIL semantic_map={args.semantic_map} errors={len(result.errors)} warnings={len(result.warnings)}")
        return 1
    print(f"OK semantic_map={args.semantic_map} warnings={len(result.warnings)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
