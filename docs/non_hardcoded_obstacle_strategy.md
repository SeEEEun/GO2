# Non-Hardcoded Obstacle And Mission Strategy

Last updated: 2026-06-26 KST

## Short Answer

Sport mode is the safest main locomotion backend, but it does not guarantee every
ICROS2026 obstacle.

- Rough tile, crosswalk-like low uneven terrain, and 0.2 m bridge entry blocks
  are plausible only after slow real tests with good localization.
- The 0.45 m central stair/slope cross is high risk for Sport-only control. It
  may be possible on a ramp-like face with precise approach, but it should not be
  treated as guaranteed.
- Foot-drop or gap-like obstacles are high risk because Sport mode does not give
  us explicit foothold planning. A body-path planner can avoid the center of a
  gap, but it cannot promise where each foot will land.

The main competition plan should therefore be:

```text
go as far as the map, live sensing, and stability gates allow
avoid timed/fixed-distance actions
use the 4-minute pass rule before damage or repeated instability
```

## What Counts As Hardcoding

Avoid these as competition behavior:

- "walk forward N meters"
- "turn N degrees"
- "move left for N seconds"
- "zone 2 always means fixed coordinate X/Y"
- "if route A then replay this motion script"
- "touch wall by blind timed lateral motion"

Allowed only as low-level safety limits:

- maximum velocity,
- timeout guards,
- tilt/slip/stuck thresholds,
- minimum sensor freshness,
- map-derived goal tolerance,
- pass-after-4-min timing from the rules.

The difference is that limits stop unsafe behavior; they do not decide where to
go or what mission to perform.

## Non-Hardcoded Main Loop

```text
1. Receive organizer ROS2 message.
2. Normalize it into target zone, mission type, color, side, and deadline.
3. Resolve target zone through the measured semantic map.
4. Plan with TRG on the current traversable map.
5. Follow the path with SportClient using bounded velocity.
6. Monitor progress, terrain risk, localization, tilt, and stuck state.
7. In the 1.2 m mission area, execute a sensor-confirmed mission action.
8. Report done only after evidence or explicit success condition.
9. If progress is unsafe or repeatedly blocked, wait for legal pass timing.
```

## Obstacle Policy

### Crosswalk / Low Uneven Terrain

Use Sport mode with conservative velocity and normal TRG path following. Pass
condition is continuous odometry progress without tilt/slip alarms.

### Shaking Bridge And 0.2 m Entry Blocks

Allow only if the measured map produces a centered traversable corridor and the
approach angle is aligned. Slow down before entry and abort on lateral drift,
large roll, or repeated stuck detection.

### Rough Tile

Use TRG traversability plus height-scan speed limiting. This is a reasonable
Sport-mode target, but should be tested before treating it as reliable.

### Hidden / Foot-Drop Risk

Treat as unknown terrain. The robot should not blindly replay a path. Require
live sensing, slow speed, and progress monitoring. If feet repeatedly drop or
body pitch/roll spikes, stop the attempt and prepare for pass.

### Central 0.45 m Stair/Slope Cross

This is the biggest risk. For Sport-only control, the route should attempt the
least steep mapped face only after:

- localization is stable,
- TRG graph has a continuous climbable path,
- the approach corridor is centered,
- a short practice climb succeeded,
- pass policy is already decided.

If those gates are not met, the scoring strategy should prefer partial progress
and pass over a damaging climb.

## Mission Policy

### Stack Light Color

Use organizer ROS2 message as the primary truth. Use Go2 front camera as
verification and evidence, not as the only dependency.

### Wall Touch

Do not touch by blind timed motion. Use mission side from the message, the
measured map wall geometry, range/odom feedback, and a low-speed guarded nudge.
Stop immediately on contact indication, odom stall, tilt spike, or timeout.

### QR Photo

Use the Go2 front camera SDK stream. The photo module should turn toward the
selected wall using map/localization feedback, capture an onboard image, run QR
or image-quality validation, then publish/save the required evidence.

## First Implementation Target

The first code target should be the mission/goal normalization layer:

- remove default fixed zone coordinates from the live goal adapter,
- require measured semantic-map data for zone goals,
- validate the semantic map before launch,
- accept organizer-provided pose/point/XY directly when available,
- publish a clear `MISSING_SEMANTIC_MAP` status instead of guessing,
- add a Go2 SDK front-camera ROS image bridge for photo missions.

This gives us the core non-hardcoded contract before any real movement is
enabled.

Implemented support files:

- `/home/jairlab/GO2/docs/semantic_map_contract.md`
- `/home/jairlab/GO2/templates/icros2026_semantic_map.template.yaml`
- `/home/jairlab/GO2/tools/validate_icros2026_semantic_map.py`
