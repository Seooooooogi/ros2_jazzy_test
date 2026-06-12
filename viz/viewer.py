#!/usr/bin/env python3
"""host 에서 도는 단독 시각화 창 — 카메라 + YOLO 박스 + 음성 상태 오버레이.

한 창에 다음을 합쳐 띄운다:
  1. host realsense2_camera 의 원본 color 프레임
  2. yolo-viz 컨테이너가 보내는 /yolo/detections 의 박스 + 클래스명
  3. 좌상단 텍스트: wakeword 감지 상태 / 현재 target / 현재 pos

카메라 프레임은 host 가 이미 소유(realsense2_camera)하므로 컨테이너에서 끌어올
필요 없이 토픽을 바로 구독한다. 박스만 컨테이너에서 받아 원본 위에 겹친다.
host 는 apt 의 rclpy/cv2/cv_bridge 만 쓰므로 pip 설치가 필요 없다(application
Python 은 컨테이너 책임이라는 분리 원칙 유지).

실행(host):
    set -a; source resources/config.sh; set +a   # ROS_DISTRO 설정(단일 진실 소스)
    source /opt/ros/${ROS_DISTRO}/setup.bash
    python3 viz/viewer.py
종료: 창에서 q.
"""

import json

import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data

import cv2
import numpy as np
from cv_bridge import CvBridge
from sensor_msgs.msg import Image
from std_msgs.msg import Bool, String


COLOR_TOPIC = "/camera/camera/color/image_raw"
DETECTIONS_TOPIC = "/yolo/detections"
WAKEWORD_TOPIC = "/wakeword_detected"
TASK_TOPIC = "/ui/current_task"

WINDOW_NAME = "YOLO Live"

# wakeword 는 감지 순간 1회 pulse(Bool=True)만 온다 → 받은 뒤 이 시간 동안 강조 표시.
WAKEWORD_FLASH_SEC = 3.0
# detection 이 이 시간보다 오래되면(컨테이너 정지 등) 박스를 지워 낡은 박스 잔상 방지.
DETECTIONS_STALE_SEC = 1.0

# 클래스별 박스 색(BGR). 미정의 클래스는 기본색으로 그린다.
CLASS_COLORS = {
    "drill": (0, 200, 255),
    "hammer": (0, 255, 0),
    "pliers": (255, 200, 0),
    "screwdriver": (255, 0, 200),
    "wrench": (0, 128, 255),
}
DEFAULT_COLOR = (200, 200, 200)


class YoloViewer(Node):
    """카메라·detection·음성 상태를 구독해 cv2 창에 합성하는 노드.

    Subscribes:
        /camera/camera/color/image_raw (sensor_msgs/Image): 원본 프레임(bgr8).
        /yolo/detections (std_msgs/String): JSON 박스+클래스(yolo-viz 컨테이너).
        /wakeword_detected (std_msgs/Bool): voice 의 wakeword 감지 pulse.
        /ui/current_task (std_msgs/String): robot_control 의 현재 target/pos(JSON).

    Note:
        cv2 GUI 호출(imshow/waitKey)은 이 노드가 아니라 main 루프(메인 스레드)에서
        한다 — cv2 창은 메인 스레드에서 다뤄야 안정적이다. 콜백은 상태만 갱신한다.
    """

    def __init__(self):
        super().__init__("yolo_viewer")
        self.bridge = CvBridge()

        self._frame = None
        self._dets = []
        self._dets_stamp_ns = 0
        self._wakeword_until_ns = 0
        self._target = None
        self._pos = None

        # 카메라는 SensorDataQoS(best-effort) — realsense publisher 가 reliable/best-effort
        # 어느 쪽이어도 best-effort subscriber 는 호환된다(reliable subscriber 면 best-effort
        # publisher 와 매칭 실패로 프레임 0 위험).
        self.create_subscription(
            Image, COLOR_TOPIC, self._on_color, qos_profile_sensor_data
        )
        self.create_subscription(String, DETECTIONS_TOPIC, self._on_dets, 10)
        self.create_subscription(Bool, WAKEWORD_TOPIC, self._on_wakeword, 10)
        self.create_subscription(String, TASK_TOPIC, self._on_task, 10)
        self.get_logger().info("yolo_viewer ready — press q in the window to quit")

    def _now_ns(self):
        return self.get_clock().now().nanoseconds

    def _on_color(self, msg):
        self._frame = self.bridge.imgmsg_to_cv2(msg, desired_encoding="bgr8")

    def _on_dets(self, msg):
        try:
            parsed = json.loads(msg.data).get("dets", [])
        except (ValueError, TypeError):
            # 깨진 payload 는 무시하고 직전 박스를 유지(렌더는 staleness 로 정리).
            return
        # "dets" 가 리스트가 아닌 형식 위반 payload 는 렌더에서 TypeError 를 내므로 방어한다.
        if isinstance(parsed, list):
            self._dets = parsed
            self._dets_stamp_ns = self._now_ns()

    def _on_wakeword(self, msg):
        if msg.data:
            self._wakeword_until_ns = self._now_ns() + int(WAKEWORD_FLASH_SEC * 1e9)

    def _on_task(self, msg):
        """현재 task(JSON)를 받아 target/pos 를 갱신한다. 빈 객체면 idle 로 비운다.

        Args:
            msg (std_msgs/String): {"target": "...", "pos": "..."} 또는 {}.
        """
        try:
            data = json.loads(msg.data) if msg.data else {}
        except (ValueError, TypeError):
            data = {}
        self._target = data.get("target") or None
        self._pos = data.get("pos") or None

    def render(self):
        """최신 상태를 한 프레임으로 합성해 창에 그린다.

        Returns:
            bool: 사용자가 q 를 눌러 종료를 요청하면 True.
        """
        if self._frame is None:
            canvas = self._placeholder("waiting for camera...")
        else:
            canvas = self._frame.copy()
            self._draw_detections(canvas)
            self._draw_status(canvas)

        cv2.imshow(WINDOW_NAME, canvas)
        return (cv2.waitKey(1) & 0xFF) == ord("q")

    def _placeholder(self, text):
        canvas = np.zeros((480, 640, 3), dtype="uint8")
        cv2.putText(
            canvas, text, (20, 240),
            cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2, cv2.LINE_AA,
        )
        return canvas

    def _draw_detections(self, canvas):
        """detection 박스+라벨을 그린다. 오래된 detection 은 건너뛴다."""
        if (self._now_ns() - self._dets_stamp_ns) > DETECTIONS_STALE_SEC * 1e9:
            return
        for det in self._dets:
            x1, y1, x2, y2 = det["box"]
            cls = det.get("cls", "?")
            conf = det.get("conf", 0.0)
            color = CLASS_COLORS.get(cls, DEFAULT_COLOR)
            cv2.rectangle(canvas, (x1, y1), (x2, y2), color, 2)
            label = f"{cls} {conf:.2f}"
            (tw, th), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.6, 2)
            # 라벨 배경 — 박스 위쪽에 두되 화면 밖이면 박스 안으로 내린다.
            ly = max(y1, th + 4)
            cv2.rectangle(canvas, (x1, ly - th - 4), (x1 + tw, ly), color, -1)
            cv2.putText(
                canvas, label, (x1, ly - 2),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 0), 2, cv2.LINE_AA,
            )

    def _draw_status(self, canvas):
        """좌상단에 wakeword/target/pos 상태 패널을 그린다."""
        wake_on = self._now_ns() < self._wakeword_until_ns
        lines = [
            ("WAKEWORD: " + ("DETECTED" if wake_on else "..."),
             (0, 255, 0) if wake_on else (180, 180, 180)),
            (f"target: {self._target if self._target else '-'}", (255, 255, 255)),
            (f"pos: {self._pos if self._pos else '-'}", (255, 255, 255)),
        ]
        # 반투명 배경 박스로 가독성 확보.
        overlay = canvas.copy()
        cv2.rectangle(overlay, (10, 10), (330, 110), (0, 0, 0), -1)
        cv2.addWeighted(overlay, 0.45, canvas, 0.55, 0, canvas)
        y = 38
        for text, color in lines:
            cv2.putText(
                canvas, text, (20, y),
                cv2.FONT_HERSHEY_SIMPLEX, 0.7, color, 2, cv2.LINE_AA,
            )
            y += 32


def main(args=None):
    rclpy.init(args=args)
    node = YoloViewer()
    try:
        while rclpy.ok():
            # 토픽 콜백을 비블로킹으로 펌프한 뒤 메인 스레드에서 렌더(cv2 GUI 안전).
            rclpy.spin_once(node, timeout_sec=0.01)
            if node.render():
                break
    except KeyboardInterrupt:
        pass
    finally:
        cv2.destroyAllWindows()
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
