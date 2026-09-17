#!/usr/bin/env python3
"""Wait for one ROS2 message and print it as JSON-friendly text."""

from __future__ import annotations

import argparse
import json
import time

import rclpy
from rclpy.node import Node
from std_msgs.msg import Bool, String


MESSAGE_TYPES = {
    "std_msgs/msg/Bool": Bool,
    "std_msgs/msg/String": String,
    "Bool": Bool,
    "String": String,
}


class WaitForTopic(Node):
    def __init__(self, topic: str, msg_type: type, timeout_s: float) -> None:
        super().__init__("wait_for_topic_once")
        self.topic = topic
        self.timeout_s = timeout_s
        self.deadline = time.monotonic() + timeout_s
        self.message = None
        self.create_subscription(msg_type, topic, self._cb, 10)

    def _cb(self, msg) -> None:  # noqa: ANN001
        self.message = msg

    def wait(self) -> bool:
        while rclpy.ok() and self.message is None and time.monotonic() < self.deadline:
            rclpy.spin_once(self, timeout_sec=0.05)
        return self.message is not None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Wait for one std_msgs Bool/String topic message.")
    parser.add_argument("--topic", required=True)
    parser.add_argument("--type", required=True, choices=sorted(MESSAGE_TYPES))
    parser.add_argument("--timeout-s", type=float, default=10.0)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    rclpy.init()
    node = WaitForTopic(args.topic, MESSAGE_TYPES[args.type], args.timeout_s)
    try:
        if not node.wait():
            raise SystemExit(f"timeout waiting for {args.topic}")
        msg = node.message
        if isinstance(msg, Bool):
            print(json.dumps({"topic": args.topic, "data": bool(msg.data)}))
        elif isinstance(msg, String):
            print(json.dumps({"topic": args.topic, "data": msg.data}, ensure_ascii=False))
        else:
            print(str(msg))
    finally:
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    main()
