import os
import time
import sys
import json
from scipy.spatial.transform import Rotation
import numpy as np
import rclpy
from rclpy.node import Node
import DR_init

from od_msg.srv import SrvDepthPosition
from std_srvs.srv import Trigger
from std_msgs.msg import Bool, String
from ament_index_python.packages import get_package_share_directory
from robot_control.onrobot import RG

package_path = get_package_share_directory("robot_control")

# for single robot
ROBOT_ID = "dsr01"
ROBOT_MODEL = "m0609"
VELOCITY, ACC = 60, 60
BUCKET_POS = [4.00, 38.00, 64.00, -0.1, 78.0, 4]
JHOME_POS = [0, -30, 90, 0, 90, 0]
# 음성 명령의 목적지(pos1/2/3) → 실제 base 기준 task 좌표(posx). 핸드가이드 티칭으로 기록.
PLACE_POSITIONS = {
    "pos1": [309.455, -164.533, 314.995, 168.498, 179.790, 168.799],
    "pos2": [677.722, -154.152, 306.509, 39.190, 179.813, 39.228],
    "pos3": [686.782, 145.015, 301.718, 33.625, 179.609, 33.701],
}
PLACE_LIFT = 250.0  # 집은 뒤 목적지 이동 전 들어올릴 높이(mm) — 테이블 끌림 방지
PLACE_Z_OFFSET = 50.0  # 목적지(pos1/2/3) 놓기 높이 보정(mm) — 티칭점보다 이만큼 위에서 놓음
GRIPPER_NAME = "rg2"
TOOLCHARGER_IP = "192.168.1.1"
TOOLCHARGER_PORT = "502"
DEPTH_OFFSET = -35.0
MIN_DEPTH = 2.0


DR_init.__dsr__id = ROBOT_ID
DR_init.__dsr__model = ROBOT_MODEL

rclpy.init()
dsr_node = rclpy.create_node("robot_control_node", namespace=ROBOT_ID)
DR_init.__dsr__node = dsr_node

try:
    from DSR_ROBOT2 import movej, movel, get_current_posx, mwait, trans
except ImportError as e:
    print(f"Error importing DSR_ROBOT2: {e}")
    sys.exit()

########### Gripper Setup. Do not modify this area ############

gripper = RG(GRIPPER_NAME, TOOLCHARGER_IP, TOOLCHARGER_PORT)


########### Robot Controller ############


class RobotController(Node):
    def __init__(self):
        super().__init__("pick_and_place")
        self.init_robot()

        self.get_position_client = self.create_client(
            SrvDepthPosition, "/get_3d_position"
        )
        while not self.get_position_client.wait_for_service(timeout_sec=3.0):
            self.get_logger().info("Waiting for get_depth_position service...")
        self.get_position_request = SrvDepthPosition.Request()

        self.get_keyword_client = self.create_client(Trigger, "/get_keyword")
        while not self.get_keyword_client.wait_for_service(timeout_sec=3.0):
            self.get_logger().info("Waiting for get_keyword service...")
        self.get_keyword_request = Trigger.Request()

        # voice 가 wakeword 를 감지한 순간을 토픽으로 받아 로깅한다 (get_keyword 응답 대기 중 수신).
        self.create_subscription(Bool, "/wakeword_detected", self._on_wakeword, 10)

        # 시각화 viewer 가 현재 처리 중인 target/pos 를 표시하도록 publish 한다.
        # 모션 로직과 무관한 관찰용 토픽 — pick 직전 항목을 알리고, 유휴 시 비운다.
        self.ui_pub = self.create_publisher(String, "/ui/current_task", 10)
        self._publish_task(None, None)

    def _on_wakeword(self, msg):
        if msg.data:
            self.get_logger().info("Wakeword detected! (from voice node)")

    def _publish_task(self, target, pos):
        """현재 target/pos 를 viewer 용 토픽에 publish 한다.

        Args:
            target (str | None): 집을 대상 도구. 유휴 상태면 None.
            pos (str | None): 목적지(pos1/2/3). 미지정이면 None.

        Note:
            관찰용 add-on 토픽이라 실패해도 pick-and-place 동작에 영향이 없어야 한다.
            payload 는 viewer 가 파싱하는 JSON — 빈 객체 {} 는 유휴를 뜻한다.
        """
        data = {}
        if target:
            data["target"] = target
        if pos:
            data["pos"] = pos
        # 관찰용 publish 가 실패해도 motion 루프(robot_control)는 영향받지 않아야 한다.
        # robot_control() 은 main while 루프에서 try 없이 호출되므로 여기서 예외를 격리한다.
        try:
            self.ui_pub.publish(String(data=json.dumps(data)))
        except Exception as e:
            self.get_logger().warn(f"_publish_task failed (non-critical): {e}")

    def get_robot_pose_matrix(self, x, y, z, rx, ry, rz):
        R = Rotation.from_euler("ZYZ", [rx, ry, rz], degrees=True).as_matrix()
        T = np.eye(4)
        T[:3, :3] = R
        T[:3, 3] = [x, y, z]
        return T

    def transform_to_base(self, camera_coords, gripper2cam_path, robot_pos):
        """
        Converts 3D coordinates from the camera coordinate system
        to the robot's base coordinate system.
        """
        gripper2cam = np.load(gripper2cam_path)
        coord = np.append(np.array(camera_coords), 1)  # Homogeneous coordinate

        x, y, z, rx, ry, rz = robot_pos
        base2gripper = self.get_robot_pose_matrix(x, y, z, rx, ry, rz)

        # 좌표 변환 (그리퍼 → 베이스)
        base2cam = base2gripper @ gripper2cam
        td_coord = np.dot(base2cam, coord)

        return td_coord[:3]

    def robot_control(self):
        target_list = []
        self.get_logger().info("call get_keyword service")
        self.get_logger().info("say 'Hello Rokey' and speak what you want to pick up")
        get_keyword_future = self.get_keyword_client.call_async(self.get_keyword_request)
        rclpy.spin_until_future_complete(self, get_keyword_future)
        if get_keyword_future.result().success:
            get_keyword_result = get_keyword_future.result()

            # message 형식: "도구1 도구2 ... / 목적지1 목적지2 ...". 도구[i] 를 목적지[i] 에 놓는다.
            message = get_keyword_result.message
            if "/" in message:
                obj_part, dst_part = message.split("/", 1)
                tools = obj_part.split()
                dests = dst_part.split()
            else:
                tools = message.split()
                dests = []

            for i, target in enumerate(tools):
                dest = dests[i] if i < len(dests) else None
                # 명령 파싱 즉시 오버레이를 갱신한다. 검출/depth 실패로 pick 까지 못 가도
                # "무엇을 시도 중인지"는 보여야 하므로 get_target_pos 성공 여부와 분리한다.
                self._publish_task(target, dest)

                target_pos = self.get_target_pos(target)
                if target_pos is None:
                    self.get_logger().warn("No target position")
                    continue
                self.get_logger().info(f"target position: {target_pos} -> place: {dest}")
                self.pick_and_place_target(target_pos, dest)
                self.init_robot()

            # 한 명령 처리가 끝나면 viewer 오버레이를 유휴로 되돌린다.
            self._publish_task(None, None)

        else:
            # get_keyword 실패(wakeword 미감지/타임아웃 등) — 다음 루프에서 재호출한다.
            self.get_logger().warn("get_keyword failed (no keyword detected)")
            return

    def get_target_pos(self, target):
        self.get_position_request.target = target
        self.get_logger().info("call depth position service with object_detection node")
        get_position_future = self.get_position_client.call_async(
            self.get_position_request
        )
        rclpy.spin_until_future_complete(self, get_position_future)

        if get_position_future.result():
            result = get_position_future.result().depth_position.tolist()
            self.get_logger().info(f"Received depth position: {result}")
            if sum(result) == 0:
                print("No target position")
                return None

            gripper2cam_path = os.path.join(
                package_path, "resource", "T_gripper2camera.npy"
            )
            robot_posx = get_current_posx()[0]
            td_coord = self.transform_to_base(result, gripper2cam_path, robot_posx)

            if td_coord[2] and sum(td_coord) != 0:
                td_coord[2] += DEPTH_OFFSET  # DEPTH_OFFSET
                td_coord[2] = max(td_coord[2], MIN_DEPTH)  # MIN_DEPTH: float = 2.0

            target_pos = list(td_coord[:3]) + robot_posx[3:]
        return target_pos

    def init_robot(self):
        JReady = [0, 0, 90, 0, 90, 0]
        movej(JReady, vel=VELOCITY, acc=ACC)
        gripper.open_gripper()
        mwait()

    def pick_and_place_target(self, target_pos, dest=None):
        movel(target_pos, vel=VELOCITY, acc=ACC)
        mwait()
        gripper.close_gripper()

        while gripper.get_status()[0]:
            time.sleep(0.5)
        mwait()

        # 집은 뒤 곧장 들어올려 테이블 끌림을 막고, 목적지(pos1/2/3)로 이동해 놓는다.
        lift_pos = target_pos[:2] + [target_pos[2] + PLACE_LIFT] + target_pos[3:]
        movel(lift_pos, vel=VELOCITY, acc=ACC)
        mwait()

        if dest in PLACE_POSITIONS:
            place_pos = list(PLACE_POSITIONS[dest])
            place_pos[2] += PLACE_Z_OFFSET  # 티칭점보다 약간 위에서 놓기
            movel(place_pos, vel=VELOCITY, acc=ACC)
            mwait()
        else:
            # 목적지 미지정/미인식이면 들어올린 자리에서 놓는다.
            self.get_logger().warn(f"Unknown place target '{dest}', releasing at lift position")

        gripper.open_gripper()
        while gripper.get_status()[0]:
            time.sleep(0.5)


def main(args=None):
    node = RobotController()
    while rclpy.ok():
        node.robot_control()
    rclpy.shutdown()
    node.destroy_node()


if __name__ == "__main__":
    main()
