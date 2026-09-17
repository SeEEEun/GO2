# ICROS2026 Rules And Orientation Summary

Last updated: 2026-06-25 KST

## Official Sources

- Main page: https://icros2026.qrckorea.org/
- Rules page: https://icros2026.qrckorea.org/race_ressources.html
- Timeline page: https://icros2026.qrckorea.org/timeline.html
- Local orientation PDF:
  `/home/jairlab/GO2/ICROS_2026_4족보행_대회 (0613) 오리엔테이션.pdf`

The local rules file and the official rules page both indicate the rules page
was updated on 2026-06-11. Rules can still change, so re-check the official page
before final competition setup.

## Schedule

- Orientation: 2026-06-13, 21:00, online.
- Registration period shown in the orientation and timeline: 2026-04-14 to
  2026-06-24.
- Competition: 2026-07-01 to 2026-07-03 at Daegu EXCO.
- 2026-07-01 includes team introduction, track reveal, team mapping, and
  practice.
- 2026-07-02 is preliminary competition.
- 2026-07-03 is final competition and awards.

## Arena

- Field size: 8 m x 6 m.
- Wall height: 0.6 m.
- Zones: four mission zones, numbered 1, 2, 3, 4.
- Start and finish: always zone 1.
- Each zone corner has an industrial stack light.
- Mission area size from orientation: 1.2 m x 1.2 m.

## Route Cards

Public example route cards:

```text
A: 1 -> 2 -> 4 -> 3 -> 1
B: 1 -> 3 -> 2 -> 4 -> 1
C: 1 -> 3 -> 4 -> 2 -> 1
```

Preliminary notes from the orientation say the route card is visible to teams.
Final notes say teams draw a route card but do not know the route order. Treat
the final as route-unknown until the organizer message arrives.

## Obstacles

```text
1 <-> 2: left vertical path, crosswalk obstacle
1 <-> 4: top horizontal path, shaking bridge + entry blocks
3 <-> 4: right vertical path, rough tile obstacle
2 <-> 3: bottom horizontal path, hidden obstacle
center: stair/slope cross structure, max height 0.45 m, direction screens
```

Operational implication:

- The central cross cannot be treated as a simple obstacle to avoid. Diagonal
  routes force the robot to climb or traverse it.
- The hidden lower segment must be handled by live sensing and conservative
  speed limits.
- The bridge and rough tiles should use low speed, larger stop margin, and
  recovery behavior.

## Autonomy Rules

For autonomous mode:

- Robot must operate fully autonomously.
- Only onboard sensors and onboard computing are allowed.
- External fixed cameras, external sensors, and remote control are forbidden
  except emergency handling.
- Wired connection to the robot is forbidden during the run.
- Wireless router use is allowed, but SSID must be the team name.
- Organizer PC joins the team's wireless network and sends ROS2 messages for
  destinations and mission information.

## Scoring

Official rules page:

- Per segment base score: movement 10 + mission 10 = 20.
- Autonomous mode multiplies the remote-control scoring basis by 2.
- Time bonus: integer remaining seconds divided by 10, multiplied by the
  participation multiplier.
- Final-style example: five segments, 25 minutes.

Orientation detail:

- Preliminary: 3 missions, 17 minutes, 60 points base or 120 autonomous base.
- Final: 5 missions, 25 minutes, 100 points base or 200 autonomous base.

Pass and retry:

- There is no minimum movement time.
- Passing to the next segment is allowed only after 4 minutes have elapsed.
- Pass score uses the last robot position and divides the route into fifths.
- Mission score is 0 if the robot does not reach the mission zone.
- Retry grants 2 minutes of maintenance time in the orientation notes, but the
  challenge clock still matters. Confirm the exact current interpretation with
  the judges on-site.

## Missions

Mission information is sent by ROS2 message from the organizer.

Known mission types:

- Button press.
- Photo capture.

Orientation examples:

- Orange/red stack light determines left/right wall touch for a button mission.
- Orange/red stack light determines left/right QR photo target for a camera
  mission.
- After mission completion, the next mission appears within about 3 seconds.

## Strategy Implications

- Main score path should prioritize reliable autonomous movement and mission
  completion, not aggressive speed.
- The Sport backend is the current main plan because it preserves Unitree's
  gait controller while our stack handles autonomy.
- Low-level RL should remain off the main run until repeated real-hardware
  safety gates pass.
- The route/mission adapter must be flexible because the organizer ROS2 message
  type can still differ from rehearsal topics.
