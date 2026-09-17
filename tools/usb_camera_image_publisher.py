#!/usr/bin/env python3
"""Publish a USB camera as a ROS2 Image topic.

This is intentionally small and independent from the motion stack. It exists
because the stock v4l2_camera node can fail on some UVC MJPG cameras while
OpenCV can still capture the stream reliably.
"""

from __future__ import annotations

import argparse
import glob
import json
import time
from pathlib import Path

import cv2
import rclpy
from cv_bridge import CvBridge
from rclpy.node import Node
from sensor_msgs.msg import Image
from std_msgs.msg import String


DEFAULT_GENERAL_WEBCAM = "/dev/v4l/by-id/usb-LX-240924-XH_GENERAL_WEBCAM-video-index0"


def resolve_device(device: str) -> str:
    if device != "auto":
        return device

    preferred = Path(DEFAULT_GENERAL_WEBCAM)
    if preferred.exists():
        return str(preferred)

    candidates = sorted(glob.glob("/dev/v4l/by-id/*GENERAL*WEBCAM*video-index0"))
    if candidates:
        return candidates[0]

    non_chicony = [
        path
        for path in sorted(glob.glob("/dev/v4l/by-id/*video-index0"))
        if "Chicony" not in path and "IR" not in path
    ]
    if non_chicony:
        return non_chicony[0]

    video_nodes = sorted(glob.glob("/dev/video*"))
    if video_nodes:
        return video_nodes[-1]

    raise FileNotFoundError("No /dev/video* camera device found")


class UsbCameraImagePublisher(Node):
    def __init__(
        self,
        device: str,
        image_topic: str,
        status_topic: str,
        frame_id: str,
        width: int,
        height: int,
        fps: float,
        fourcc: str,
    ) -> None:
        super().__init__("go2_usb_camera_publisher")
        self.device = resolve_device(device)
        self.image_topic = image_topic
        self.status_topic = status_topic
        self.frame_id = frame_id
        self.width = width
        self.height = height
        self.fps = max(1.0, fps)
        self.fourcc = fourcc
        self.bridge = CvBridge()
        self.frame_count = 0
        self.last_ok_time = 0.0

        self.image_pub = self.create_publisher(Image, image_topic, 5)
        self.status_pub = self.create_publisher(String, status_topic, 5)

        self.cap = cv2.VideoCapture(self.device, cv2.CAP_V4L2)
        if not self.cap.isOpened():
            raise RuntimeError(f"failed to open USB camera: {self.device}")

        if fourcc:
            self.cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*fourcc[:4]))
        self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, float(width))
        self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, float(height))
        self.cap.set(cv2.CAP_PROP_FPS, float(self.fps))

        self.actual_width = int(self.cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        self.actual_height = int(self.cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        self.actual_fps = float(self.cap.get(cv2.CAP_PROP_FPS))

        self.create_timer(1.0 / self.fps, self._timer_cb)
        self.create_timer(1.0, self._publish_status)
        self.get_logger().info(
            "USB camera publisher ready: "
            f"device={self.device}, topic={image_topic}, "
            f"requested={width}x{height}@{self.fps:.1f}/{fourcc}, "
            f"actual={self.actual_width}x{self.actual_height}@{self.actual_fps:.1f}"
        )

    def _timer_cb(self) -> None:
        ok, frame = self.cap.read()
        if not ok or frame is None or frame.size == 0:
            self.get_logger().warn(f"failed to read frame from {self.device}", throttle_duration_sec=2.0)
            return

        self.frame_count += 1
        self.last_ok_time = time.time()
        msg = self.bridge.cv2_to_imgmsg(frame, encoding="bgr8")
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.header.frame_id = self.frame_id
        self.image_pub.publish(msg)

    def _publish_status(self) -> None:
        payload = {
            "state": "OK" if self.last_ok_time else "WAIT_FRAME",
            "device": self.device,
            "image_topic": self.image_topic,
            "frame_id": self.frame_id,
            "requested_width": self.width,
            "requested_height": self.height,
            "requested_fps": self.fps,
            "fourcc": self.fourcc,
            "actual_width": self.actual_width,
            "actual_height": self.actual_height,
            "actual_fps": round(self.actual_fps, 3),
            "frame_count": self.frame_count,
            "age_since_last_frame_s": round(time.time() - self.last_ok_time, 3) if self.last_ok_time else None,
        }
        self.status_pub.publish(String(data=json.dumps(payload, ensure_ascii=False)))

    def destroy_node(self) -> bool:
        if hasattr(self, "cap"):
            self.cap.release()
        return super().destroy_node()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Publish an external USB camera as ROS2 Image.")
    parser.add_argument("--device", default="auto", help="Camera device path, or 'auto'.")
    parser.add_argument("--image-topic", default="/go2/usb_camera/image_raw")
    parser.add_argument("--status-topic", default="/go2/usb_camera/status")
    parser.add_argument("--frame-id", default="go2_usb_camera_optical_frame")
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--height", type=int, default=720)
    parser.add_argument("--fps", type=float, default=15.0)
    parser.add_argument("--fourcc", default="MJPG")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    rclpy.init()
    node = UsbCameraImagePublisher(
        device=args.device,
        image_topic=args.image_topic,
        status_topic=args.status_topic,
        frame_id=args.frame_id,
        width=args.width,
        height=args.height,
        fps=args.fps,
        fourcc=args.fourcc,
    )
    try:
        rclpy.spin(node)
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
