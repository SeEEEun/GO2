# Autonomy Directions

Last updated: 2026-06-26 KST

## Final Recommendation

Use directions 1, 2, and 5 as the competition main plan:

```text
1. Stable completion with Sport backend
2. Fast mapping and operation optimization
5. Conservative scoring and pass policy
```

Direction 3 is an experiment track. Direction 4 is a long-term research track.

Hardcoded movement scripts are not part of the main plan. Fixed forward
distance, fixed turn angle, fixed timed lateral motion, and fixed zone
coordinates are treated as rehearsal-only behavior. The competition path must be
driven by organizer messages, measured map semantics, TRG planning, and live
state feedback. See `docs/non_hardcoded_obstacle_strategy.md`.

## 1. Stable Completion

Stack:

```text
MID360 -> FAST-LIO2 -> saved-map localization -> TRG -> path_to_cmd_vel -> Go2 SportClient
```

Use this as the main competition candidate.

Why:

- Unitree's high-level gait controller remains active.
- Existing scripts already support saved-map localization, TRG, SportClient
  command bridging, and short-goal tests.
- Recovery is simpler than low-level motor control.

Risk:

- Technical novelty is lower than a fully learned low-level controller.
- Central 0.45 m structures, shaking bridge, and hidden obstacle still require
  careful speed limits and route validation.
- Sport mode does not explicitly choose footholds, so foot-drop/gap-like
  obstacles must be treated as high-risk terrain with abort/pass criteria.

## 2. Mapping And Operation Optimization

Goal:

Build a reliable map and route setup quickly after the track is opened.

Core practices:

- Never overwrite raw FAST-LIO PCD maps.
- Keep localization dense map and TRG planner source map separate.
- Preserve low terrain details such as ramps, rough tiles, bridge entries, and
  climbable structures.
- Remove ceiling, walls from traversability, people, and high interior clutter
  from planner source maps.
- Use multi-pass temporal confidence where time allows.

Why:

- The official schedule gives only limited team mapping and practice time.
- Good map hygiene gives a larger reliability gain than aggressive controller
  tuning.

## 3. Hybrid Technology Track

Stack:

```text
Sport main run + low-level RL harness/off-ground experiments
```

Use:

- Keep Sport as the scoring candidate.
- Continue low-level RL only as a separately gated experiment.
- Promote it only after repeated handoff and short-gait tests pass.

Gate:

- No active floor run from low-level RL until current-hold, motor order, action
  sign, default posture, and 5-30 cm gait smoke tests are repeatable.

## 4. Full Low-Level RL Challenge

Stack:

```text
TRG local goal -> height scan -> learned policy -> SDK2 low-level targets
```

This is the highest technical-impact direction, but it is not the current
competition mainline.

Main blockers:

- Low-level handoff to real Go2 is still high risk.
- Real gait has not yet been proven reliable enough on the floor.
- A failed low-level run can damage the robot, waste competition time, and
  break joystick/manual recovery.

## 5. Conservative Scoring Strategy

Use the 4-minute pass rule intentionally.

Policy:

- Try to complete every segment, but define pass thresholds before the run.
- If the robot is stuck, unstable, or repeatedly missing a mission approach,
  prefer a controlled pass after 4 minutes rather than a damaging attempt.
- Because autonomous mode has a 2x multiplier, partial movement plus reliable
  missions can outperform one risky full-send attempt.
- For the central 0.45 m stair/slope cross, require a proven practice climb or
  use partial-score/pass strategy instead of treating Sport mode as guaranteed.

Suggested thresholds:

- If no meaningful progress for 30-45 seconds: recovery once.
- If recovery fails twice in the same obstacle: stop aggressive movement.
- After 4 minutes: pass if the robot is stable but cannot finish the segment.
- Stop immediately on tilt, repeated foot slip, localization jump, or command
  publisher confusion.

## Direction Matrix

| Direction | Competition role | Stability | Development cost | Main risk |
| --- | --- | --- | --- | --- |
| Stable Sport completion | Main | High | Medium | Hard terrain tuning |
| Mapping/operation optimization | Main support | High | Medium | Time pressure |
| Hybrid Sport + RL | Experiment | Medium | High | Split focus |
| Full low-level RL | Long-term | Low now | Very high | Real-hardware handoff |
| Conservative scoring | Main operation | High | Low | Needs clear judgment |
