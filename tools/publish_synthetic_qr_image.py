#!/usr/bin/env python3
"""Publish a generated QR image as a ROS2 sensor_msgs/Image test input."""

from __future__ import annotations

import argparse
import time

import cv2
import numpy as np
import rclpy
from rclpy.node import Node
from sensor_msgs.msg import Image


def make_qr_canvas(text: str, width: int, height: int) -> np.ndarray:
    encoder = cv2.QRCodeEncoder_create()
    qr = encoder.encode(text)
    qr = cv2.resize(qr, (min(width, height) // 2, min(width, height) // 2), interpolation=cv2.INTER_NEAREST)
    canvas = np.full((height, width), 255, dtype=np.uint8)
    y = (height - qr.shape[0]) // 2
    x = (width - qr.shape[1]) // 2
    canvas[y : y + qr.shape[0], x : x + qr.shape[1]] = qr
    bgr = cv2.cvtColor(canvas, cv2.COLOR_GRAY2BGR)
    cv2.putText(bgr, text[:48], (20, height - 30), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (20, 20, 20), 2)
    return bgr


class SyntheticQrPublisher(Node):
    def __init__(self, topic: str, frame_id: str, image: np.ndarray, rate_hz: float, count: int) -> None:
        super().__init__("synthetic_qr_image_publisher")
        self.pub = self.create_publisher(Image, topic, 10)
        self.frame_id = frame_id
        self.image = image
        self.period_s = 1.0 / max(rate_hz, 0.1)
        self.count = count
        self.sent = 0
        self.get_logger().info(f"publishing synthetic QR image to {topic}, count={count}")

    def publish_loop(self) -> None:
        while rclpy.ok() and (self.count <= 0 or self.sent < self.count):
            msg = Image()
            now = self.get_clock().now().to_msg()
            msg.header.stamp = now
            msg.header.frame_id = self.frame_id
            msg.height = int(self.image.shape[0])
            msg.width = int(self.image.shape[1])
            msg.encoding = "bgr8"
            msg.is_bigendian = False
            msg.step = int(self.image.shape[1] * 3)
            msg.data = self.image.tobytes()
            self.pub.publish(msg)
            self.sent += 1
            rclpy.spin_once(self, timeout_sec=0.01)
            time.sleep(self.period_s)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Publish a generated QR test image.")
    parser.add_argument("--topic", default="/go2/usb_camera/image_raw")
    parser.add_argument("--frame-id", default="synthetic_qr_camera")
    parser.add_argument("--text", default="ICROS2026_SYNTHETIC_QR")
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--height", type=int, default=720)
    parser.add_argument("--rate-hz", type=float, default=5.0)
    parser.add_argument("--count", type=int, default=30)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    image = make_qr_canvas(args.text, args.width, args.height)
    rclpy.init()
    node = SyntheticQrPublisher(args.topic, args.frame_id, image, args.rate_hz, args.count)
    try:
        node.publish_loop()
    finally:
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    main()
