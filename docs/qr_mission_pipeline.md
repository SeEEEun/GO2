# QR Mission Pipeline

This is the Go2-off preparation path for ICROS2026 QR/photo missions.

It starts only:

- external USB RGB camera publisher,
- YOLO QR detector using `models/qr/best.pt`,
- OpenCV QR decoder,
- organizer mission normalizer,
- mission monitor that converts QR detection/decoding into mission status.

It does not start FAST-LIO, TRG, Sport, SDK movement, `/rl/cmd_vel`, or any Go2
walking command.

## Competition Meaning

From the current orientation material:

- mission information comes from organizer ROS2 messages,
- stack-light color is orange or red,
- mission actions happen inside a `1.2 m x 1.2 m` mission zone,
- QR/photo mission example:
  - zone 3 orange: take QR/photo on the right wall,
  - zone 3 red: take QR/photo on the left wall.

The organizer ROS message is the primary truth for `zone`, `color`,
`mission_type`, and `side`. The camera is used to verify/capture evidence after
the navigation stack has reached the correct wall-facing pose.

## Topics

Inputs:

```text
/go2/usb_camera/image_raw
/icros2026/organizer/mission
/icros2026/organizer/zone
/icros2026/organizer/color
/icros2026/organizer/mission_type
```

Vision outputs:

```text
/icros2026/vision/qr/status
/icros2026/vision/qr/result
/icros2026/vision/qr/debug_image
```

Mission outputs:

```text
/icros2026/mission/normalized   std_msgs/String JSON
/icros2026/mission/request      std_msgs/String JSON
/icros2026/mission/status       std_msgs/String JSON
/icros2026/mission_done         std_msgs/Bool
/icros2026/mission/result       std_msgs/String JSON
/icros2026/mission/qr_evidence  std_msgs/String JSON
```

`/icros2026/mission_done` is the compatibility completion signal and publishes
`true` only after the active QR/photo mission is satisfied. Detailed evidence is
published on `/icros2026/mission/result`.

## Start

```bash
cd /home/jairlab/GO2
./scripts/start_usb_camera_qr_mission.sh
```

Useful viewers:

```bash
ROS_DOMAIN_ID=88 rqt_image_view /icros2026/vision/qr/debug_image
ROS_DOMAIN_ID=88 ros2 topic echo /icros2026/vision/qr/status
ROS_DOMAIN_ID=88 ros2 topic echo /icros2026/mission/status
ROS_DOMAIN_ID=88 ros2 topic echo /icros2026/mission_done
```

The default USB camera selection uses stable `/dev/v4l/by-id` paths first. Do
not depend on `/dev/videoN`; the number changes after reconnecting cameras.

## Mock Mission Test

In another terminal:

```bash
cd /home/jairlab/GO2
./scripts/mock_qr_photo_mission.sh
```

Default mock mission:

```json
{
  "mission_id": "mock_qr_zone3_orange",
  "mission_type": "qr_photo",
  "zone": 3,
  "color": "orange",
  "side": "right",
  "wall_id": "right_wall",
  "timeout_s": 30.0,
  "require_decode": true
}
```

To test the red/left-wall branch:

```bash
COLOR=red SIDE=left WALL_ID=left_wall MISSION_ID=mock_qr_zone3_red \
./scripts/mock_qr_photo_mission.sh
```

## Success Criteria

Before turning on the real Go2 for the next navigation stage:

- USB camera publishes `/go2/usb_camera/image_raw`.
- QR node publishes `/icros2026/vision/qr/debug_image`.
- Showing a QR code to the camera changes QR status to `DECODED`.
- After a mock `qr_photo` mission, `/icros2026/mission_done` publishes
  `data: true`.
- `/icros2026/mission/result` publishes a JSON result with
  `result: qr_success`.
- Evidence image/json files are saved under `artifacts/qr_evidence/`.
- Mission-scoped copies are saved under `artifacts/mission_evidence/`.

## Synthetic End-To-End Test

This test does not need a physical camera. It generates a QR image with OpenCV,
publishes it as `/go2/usb_camera/image_raw`, sends a mock organizer mission, and
waits for both mission completion topics.

```bash
cd /home/jairlab/GO2
./scripts/test_qr_mission_synthetic.sh
```

Expected output includes:

```text
[synthetic-test] mission_done:
{"topic": "/icros2026/mission_done", "data": true}
[synthetic-test] mission_result:
... "result": "qr_success" ...
```

## Boundary

This module only validates that the correct QR/photo evidence was observed.
Navigation still has to move the robot to the mission zone and face the selected
wall using the saved map, live localization, and TRG path. Blind timed movement
is still disallowed.
