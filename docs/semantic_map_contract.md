# ICROS2026 Semantic Map Contract

Last updated: 2026-06-26 KST

This file defines the measured semantic map used by the non-hardcoded
competition stack.

## Purpose

The semantic map is not a motion script. It is the measured description of the
course:

- zone goal poses,
- 1.2 m x 1.2 m mission areas,
- wall geometry for guarded touch/photo alignment,
- QR/photo wall sides,
- obstacle risk regions.

The robot still chooses motion through localization, TRG planning, Sport command
limits, and live safety feedback.

## Hardcoding Boundary

Allowed in the semantic map:

- measured zone centers/goals from the actual mapped course,
- measured wall lines and normals,
- measured mission area geometry,
- measured obstacle/risk polygons,
- organizer-defined mission semantics such as orange/red -> left/right action.

Not allowed:

- "walk forward N meters",
- "turn N degrees",
- "move for N seconds",
- dense replay waypoint scripts,
- guessed zone coordinates copied from the rule PDF instead of measured map
  alignment.

## Required Runtime Fields

Use `/home/jairlab/GO2/templates/icros2026_semantic_map.template.yaml` as the
starting point. The runtime file must replace all `null` and `TODO` values.

Required:

- `frame` or `map_frame`
- `measurement.source_map`
- `measurement.method`
- `zones.1` through `zones.4`
- each zone goal with finite `x`, `y`, optional finite `z`, optional finite
  `yaw`

Recommended:

- `zones.<id>.mission_area.center`
- `zones.<id>.mission_area.size_m: [1.2, 1.2]`
- `walls`
- `missions`
- `risk_regions`

## Validation

Run:

```bash
cd /home/jairlab/GO2
python3 tools/validate_icros2026_semantic_map.py path/to/icros2026_semantic_map.yaml
```

Expected runtime result:

```text
OK semantic_map=... warnings=0
```

The template should fail validation until measured values are filled in. That is
intentional.

## Launch Usage

For real launch, pass the measured map path into the goal adapter:

```bash
ros2 launch go2_roughnav 06_real_go2_pipeline.launch.py \
  arena_semantics_path:=/absolute/path/to/icros2026_semantic_map.yaml
```

If this parameter is empty, zone-only organizer messages must not move the
robot. Direct organizer `PoseStamped`, `PointStamped`, or XY messages may still
be forwarded because the organizer is providing the target geometry directly.

## First Real Map Procedure

1. Build or load the aligned FAST-LIO/TRG course map.
2. Mark the four zone goal poses in the same frame used by the navigation stack.
3. Mark each 1.2 m x 1.2 m mission area.
4. Mark left/right wall lines and normals used by touch/photo actions.
5. Mark high-risk obstacle regions:
   - shaking bridge,
   - rough tile,
   - hidden/foot-drop risk,
   - central 0.45 m stair/slope cross.
6. Validate the file.
7. Only then set `arena_semantics_path` in launch or config.

## Runtime Interpretation

The semantic map answers "where is the meaningful course geometry?" It does not
answer "how long should the robot walk?" The planner/controller must still use
live odometry, map alignment, traversability, and safety state.
