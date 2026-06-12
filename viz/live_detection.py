#!/usr/bin/env python3
"""yolo-detection 컨테이너에서 도는 시각화 전용 연속추론 노드.

기존 object_detection 서비스 노드(/get_3d_position)는 호출 시점에만 추론하므로
실시간 박스를 그릴 토픽이 없다. 이 노드는 카메라 color 스트림을 계속 추론해
바운딩 박스 + 클래스명을 경량 JSON 토픽으로 publish 한다. host viewer 가 이를
구독해 원본 프레임 위에 그린다(추론은 torch 가 있는 컨테이너에서만 가능).

이미지를 다시 publish 하지 않고 좌표만 보내는 이유: 원본 프레임은 host
realsense2_camera 가 이미 publish 하므로, 박스 좌표(수백 바이트)만 보내면
1280x720 BGR 프레임(~2.6MB) 재전송을 피할 수 있다.

컨테이너 entrypoint 가 ROS overlay(/ws/install) 와 venv(/opt/venv) PYTHONPATH 를
주입한 뒤 이 스크립트를 실행하므로 rclpy/cv_bridge(ROS) 와 torch/ultralytics/cv2
(venv) 가 모두 import 가능하다(기존 object_detection 노드와 동일 실행 경로).
"""

import json
import os

import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data

from ament_index_python.packages import get_package_share_directory
from sensor_msgs.msg import Image
from std_msgs.msg import String
from cv_bridge import CvBridge
from ultralytics import YOLO


# object_detection 패키지가 이미지 overlay 에 설치돼 있어 모델·리소스를 거기서 찾는다.
PACKAGE_NAME = "object_detection"
YOLO_MODEL_FILENAME = "yolov8n_tools_0122.pt"

# 카메라 color 토픽 — host realsense2_camera 가 publish(bgr8, 1280x720@30).
COLOR_TOPIC = "/camera/camera/color/image_raw"
# viewer 가 구독할 경량 detection 토픽.
DETECTIONS_TOPIC = "/yolo/detections"

CONF_THRESHOLD = 0.5
# 추론 스로틀. 카메라는 30fps 지만 이 주파수로 제한해 서비스 노드와의 GPU 경합과
# 불필요한 부하를 줄인다. 데모 관찰용이라 15Hz 로 충분하다.
INFER_HZ = 15
INFER_MIN_INTERVAL = 1.0 / INFER_HZ


class YoloLiveDetector(Node):
    """color 스트림을 연속 추론해 박스+클래스를 JSON 으로 publish 하는 노드.

    Subscribes:
        /camera/camera/color/image_raw (sensor_msgs/Image): host 카메라 원본(bgr8).

    Publishes:
        /yolo/detections (std_msgs/String): JSON. full-frame 픽셀좌표 박스 리스트.
            형식: {"dets": [{"box": [x1,y1,x2,y2], "cls": "hammer", "conf": 0.91}, ...]}
            클래스명을 문자열로 직접 담아 viewer 가 id->name 매핑을 들 필요가 없다.

    Note:
        카메라 구독은 SensorDataQoS(best-effort)를 쓴다. realsense2_camera 의 이미지
        publisher QoS 는 설정에 따라 reliable 또는 best-effort 일 수 있는데, best-effort
        subscriber 는 양쪽 publisher 와 모두 호환된다. reliable subscriber 였다면
        best-effort publisher 와 매칭 실패로 프레임이 0 이 될 수 있어 더 견고한 쪽을 택했다.
    """

    def __init__(self):
        super().__init__("yolo_live_detector")
        self.bridge = CvBridge()

        share = get_package_share_directory(PACKAGE_NAME)
        model_path = os.path.join(share, "resource", YOLO_MODEL_FILENAME)
        self.model = YOLO(model_path)
        # device(cpu/cuda)는 ultralytics 가 torch.cuda 가용 여부로 자동 선택한다.
        self.get_logger().info(f"YOLO model loaded: {model_path}")

        self.det_pub = self.create_publisher(String, DETECTIONS_TOPIC, 10)
        self.create_subscription(
            Image, COLOR_TOPIC, self._on_color, qos_profile_sensor_data
        )

        # 마지막 추론 시각(ns). 스로틀 기준. None = 아직 추론 안 함.
        self._last_infer_ns = None
        self.get_logger().info(
            f"Subscribing {COLOR_TOPIC}, publishing {DETECTIONS_TOPIC} (~15Hz)"
        )

    def _on_color(self, msg):
        """color 프레임 콜백 — 스로틀을 통과하면 추론 후 detection 을 publish 한다.

        Args:
            msg (sensor_msgs/Image): bgr8 인코딩 원본 프레임.
        """
        now_ns = self.get_clock().now().nanoseconds
        if self._last_infer_ns is not None:
            if (now_ns - self._last_infer_ns) < INFER_MIN_INTERVAL * 1e9:
                return
        self._last_infer_ns = now_ns

        frame = self.bridge.imgmsg_to_cv2(msg, desired_encoding="bgr8")
        # ultralytics 는 내부에서 리사이즈하지만 박스는 원본 좌표로 돌려준다 → 재스케일 불필요.
        results = self.model(frame, verbose=False, conf=CONF_THRESHOLD)
        self.det_pub.publish(String(data=self._encode(results)))

    def _encode(self, results):
        """ultralytics 결과를 viewer 가 파싱할 JSON 문자열로 변환한다.

        Args:
            results: ultralytics 가 반환한 Results 리스트.

        Returns:
            str: {"dets": [...]} 형식 JSON. 검출 없으면 빈 리스트.
        """
        dets = []
        if not results:
            return json.dumps({"dets": dets})
        res = results[0]
        names = res.names  # {class_id: class_name}
        for box, conf, cls in zip(
            res.boxes.xyxy.tolist(),
            res.boxes.conf.tolist(),
            res.boxes.cls.tolist(),
        ):
            dets.append(
                {
                    "box": [int(v) for v in box],
                    "cls": names[int(cls)],
                    "conf": round(float(conf), 3),
                }
            )
        return json.dumps({"dets": dets})


def main(args=None):
    rclpy.init(args=args)
    node = YoloLiveDetector()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
