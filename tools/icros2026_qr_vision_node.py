#!/usr/bin/env python3
"""ICROS2026 QR vision node.

YOLO finds QR-code regions. OpenCV decodes the QR content from each crop and
from the full frame as a fallback. This node is intentionally independent from
the motion stack so QR/camera tests cannot command the robot.
"""

from __future__ import annotations

import argparse
import json
import math
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import cv2
import numpy as np
import rclpy
from cv_bridge import CvBridge
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from sensor_msgs.msg import Image
from std_msgs.msg import String
from ultralytics import YOLO


@dataclass
class QrCandidate:
    bbox_xyxy: tuple[int, int, int, int]
    confidence: float
    decoded_text: str
    source: str


def _clamp_bbox(
    bbox: Iterable[float],
    width: int,
    height: int,
    margin_ratio: float,
) -> tuple[int, int, int, int] | None:
    x1, y1, x2, y2 = [float(v) for v in bbox]
    bw = max(1.0, x2 - x1)
    bh = max(1.0, y2 - y1)
    mx = bw * margin_ratio
    my = bh * margin_ratio
    x1 = max(0, int(math.floor(x1 - mx)))
    y1 = max(0, int(math.floor(y1 - my)))
    x2 = min(width - 1, int(math.ceil(x2 + mx)))
    y2 = min(height - 1, int(math.ceil(y2 + my)))
    if x2 <= x1 or y2 <= y1:
        return None
    return x1, y1, x2, y2


def _qr_decode_variants(detector: cv2.QRCodeDetector, image_bgr: np.ndarray) -> str:
    if image_bgr.size == 0:
        return ""
    variants = [image_bgr]
    gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
    variants.append(gray)
    variants.append(cv2.equalizeHist(gray))
    variants.append(cv2.GaussianBlur(gray, (3, 3), 0))
    variants.append(cv2.adaptiveThreshold(gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 31, 2))
    for variant in variants:
        try:
            text, _points, _straight = detector.detectAndDecode(variant)
        except cv2.error:
            continue
        if text:
            return str(text)
    return ""


class IcrosQrVisionNode(Node):
    def __init__(
        self,
        model_path: Path,
        image_topic: str,
        result_topic: str,
        status_topic: str,
        debug_image_topic: str,
        evidence_dir: Path,
        conf_threshold: float,
        imgsz: int,
        process_hz: float,
        crop_margin_ratio: float,
        save_all_detections: bool,
        publish_debug_image: bool,
    ) -> None:
        super().__init__("icros2026_qr_vision_node")
        self.model_path = model_path
        self.image_topic = image_topic
        self.evidence_dir = evidence_dir
        self.conf_threshold = conf_threshold
        self.imgsz = imgsz
        self.min_period_s = 1.0 / max(0.1, process_hz)
        self.crop_margin_ratio = crop_margin_ratio
        self.save_all_detections = save_all_detections
        self.publish_debug_image = publish_debug_image

        self.bridge = CvBridge()
        self.detector = cv2.QRCodeDetector()
        self.model = YOLO(str(model_path))
        self.evidence_dir.mkdir(parents=True, exist_ok=True)

        self.result_pub = self.create_publisher(String, result_topic, 10)
        self.status_pub = self.create_publisher(String, status_topic, 10)
        self.debug_pub = self.create_publisher(Image, debug_image_topic, 2)
        self.create_subscription(Image, image_topic, self._image_cb, 2)
        self.create_timer(1.0, self._heartbeat)

        self.last_process = 0.0
        self.frame_count = 0
        self.detect_count = 0
        self.decode_count = 0
        self.last_result: dict[str, object] = {
            "state": "WAIT_IMAGE",
            "image_topic": image_topic,
            "model_path": str(model_path),
        }
        self.get_logger().info(
            "ICROS2026 QR vision ready: "
            f"image={image_topic}, model={model_path}, conf={conf_threshold:.2f}, "
            f"evidence_dir={evidence_dir}"
        )

    def _heartbeat(self) -> None:
        self.status_pub.publish(String(data=json.dumps(self.last_result, ensure_ascii=False)))

    def _image_cb(self, msg: Image) -> None:
        now = time.monotonic()
        if now - self.last_process < self.min_period_s:
            return
        self.last_process = now
        self.frame_count += 1

        try:
            image = self.bridge.imgmsg_to_cv2(msg, desired_encoding="bgr8")
        except Exception as exc:
            self.last_result = {"state": "IMAGE_CONVERT_ERROR", "error": str(exc)}
            self._heartbeat()
            return

        height, width = image.shape[:2]
        candidates: list[QrCandidate] = []
        detections = []
        try:
            results = self.model.predict(
                image,
                conf=self.conf_threshold,
                imgsz=self.imgsz,
                verbose=False,
                device="cpu",
            )
        except Exception as exc:
            self.last_result = {"state": "YOLO_ERROR", "error": str(exc)}
            self._heartbeat()
            return

        for result in results:
            boxes = getattr(result, "boxes", None)
            if boxes is None:
                continue
            for box in boxes:
                conf = float(box.conf[0]) if box.conf is not None else 0.0
                xyxy = box.xyxy[0].detach().cpu().numpy().tolist()
                bbox = _clamp_bbox(xyxy, width, height, self.crop_margin_ratio)
                if bbox is None:
                    continue
                x1, y1, x2, y2 = bbox
                crop = image[y1:y2, x1:x2]
                text = _qr_decode_variants(self.detector, crop)
                detections.append(
                    {
                        "bbox_xyxy": [x1, y1, x2, y2],
                        "confidence": round(conf, 4),
                        "decoded": bool(text),
                        "text": text,
                    }
                )
                candidates.append(QrCandidate(bbox, conf, text, "yolo_crop"))

        fallback_text = ""
        if not any(c.decoded_text for c in candidates):
            fallback_text = _qr_decode_variants(self.detector, image)
            if fallback_text:
                candidates.append(QrCandidate((0, 0, width - 1, height - 1), 0.0, fallback_text, "full_frame"))

        decoded = [c for c in candidates if c.decoded_text]
        self.detect_count += len(detections)
        if decoded:
            self.decode_count += 1

        debug = image.copy()
        for det in detections:
            x1, y1, x2, y2 = det["bbox_xyxy"]
            color = (0, 220, 0) if det["decoded"] else (0, 165, 255)
            cv2.rectangle(debug, (x1, y1), (x2, y2), color, 2)
            label = f"qr {det['confidence']:.2f}"
            if det["decoded"]:
                label += " decoded"
            cv2.putText(debug, label, (x1, max(20, y1 - 8)), cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 2)
        if fallback_text and not detections:
            cv2.putText(debug, "OpenCV full-frame QR decoded", (20, 35), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 220, 0), 2)

        best = max(decoded, key=lambda c: c.confidence) if decoded else None
        stamp = msg.header.stamp.sec + msg.header.stamp.nanosec * 1e-9
        result_msg = {
            "state": "DECODED" if best else ("DETECTED" if detections else "NO_QR"),
            "stamp": round(float(stamp), 6),
            "frame_id": msg.header.frame_id,
            "image_width": int(width),
            "image_height": int(height),
            "detections": detections,
            "decoded_text": best.decoded_text if best else "",
            "decoded_source": best.source if best else "",
            "decoded_bbox_xyxy": list(best.bbox_xyxy) if best else [],
            "frame_count": self.frame_count,
            "detect_count": self.detect_count,
            "decode_count": self.decode_count,
        }

        saved = {}
        if best or (detections and self.save_all_detections):
            saved = self._save_evidence(image, debug, result_msg, best)
            result_msg["saved"] = saved

        payload = json.dumps(result_msg, ensure_ascii=False)
        self.last_result = result_msg
        self.result_pub.publish(String(data=payload))
        self.status_pub.publish(String(data=payload))

        if self.publish_debug_image:
            try:
                dbg_msg = self.bridge.cv2_to_imgmsg(debug, encoding="bgr8")
                dbg_msg.header = msg.header
                self.debug_pub.publish(dbg_msg)
            except Exception as exc:
                self.get_logger().warn(f"failed to publish debug image: {exc}")

        if best:
            self.get_logger().info(
                f"QR decoded source={best.source} conf={best.confidence:.3f} "
                f"text={best.decoded_text!r} saved={saved}"
            )

    def _save_evidence(
        self,
        image: np.ndarray,
        debug: np.ndarray,
        result_msg: dict[str, object],
        best: QrCandidate | None,
    ) -> dict[str, str]:
        ts = time.strftime("%Y%m%d_%H%M%S")
        suffix = f"{ts}_{self.frame_count:06d}"
        raw_path = self.evidence_dir / f"qr_{suffix}_raw.jpg"
        debug_path = self.evidence_dir / f"qr_{suffix}_debug.jpg"
        json_path = self.evidence_dir / f"qr_{suffix}.json"
        cv2.imwrite(str(raw_path), image)
        cv2.imwrite(str(debug_path), debug)
        meta = dict(result_msg)
        if best:
            x1, y1, x2, y2 = best.bbox_xyxy
            crop = image[y1:y2, x1:x2]
            crop_path = self.evidence_dir / f"qr_{suffix}_crop.jpg"
            cv2.imwrite(str(crop_path), crop)
            meta["crop_path"] = str(crop_path)
        json_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
        saved = {
            "raw_image": str(raw_path),
            "debug_image": str(debug_path),
            "metadata": str(json_path),
        }
        if best:
            saved["crop_image"] = str(meta["crop_path"])
        return saved


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run ICROS2026 QR YOLO + OpenCV decoder node.")
    parser.add_argument("--model", default="/home/jairlab/GO2/models/qr/best.pt")
    parser.add_argument("--image-topic", default="/go2/front_camera/image_raw")
    parser.add_argument("--result-topic", default="/icros2026/vision/qr/result")
    parser.add_argument("--status-topic", default="/icros2026/vision/qr/status")
    parser.add_argument("--debug-image-topic", default="/icros2026/vision/qr/debug_image")
    parser.add_argument("--evidence-dir", default="/home/jairlab/GO2/artifacts/qr_evidence")
    parser.add_argument("--conf", type=float, default=0.25)
    parser.add_argument("--imgsz", type=int, default=640)
    parser.add_argument("--process-hz", type=float, default=2.0)
    parser.add_argument("--crop-margin-ratio", type=float, default=0.20)
    parser.add_argument("--save-all-detections", action="store_true")
    parser.add_argument("--no-debug-image", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    model_path = Path(args.model).expanduser()
    if not model_path.exists():
        raise FileNotFoundError(f"QR YOLO model does not exist: {model_path}")
    rclpy.init()
    node = IcrosQrVisionNode(
        model_path=model_path,
        image_topic=args.image_topic,
        result_topic=args.result_topic,
        status_topic=args.status_topic,
        debug_image_topic=args.debug_image_topic,
        evidence_dir=Path(args.evidence_dir).expanduser(),
        conf_threshold=args.conf,
        imgsz=args.imgsz,
        process_hz=args.process_hz,
        crop_margin_ratio=args.crop_margin_ratio,
        save_all_detections=args.save_all_detections,
        publish_debug_image=not args.no_debug_image,
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
