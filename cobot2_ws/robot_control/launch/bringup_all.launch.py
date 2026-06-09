"""통합 bringup — 로봇 드라이버 + RealSense 카메라 + 애플리케이션 컨테이너를 한 번에.

이 launch 는 세 그룹을 병렬 기동한다(서로 하드 순서 없음 — DDS discovery 가 비동기):
  1. Doosan m0609 드라이버/컨트롤러 (dsr_bringup2) — 자율 모션 없음, 드라이버만.
  2. host 소유 RealSense (realsense2_camera) — /camera/camera/* publish.
     카메라는 host 가 publish 하고 yolo 컨테이너가 DDS 로 subscribe 한다(컨테이너 안에 카메라 없음).
  3. yolo / voice 애플리케이션 컨테이너 (docker compose up -d).
     각 이미지의 ENTRYPOINT 가 ROS2 환경 + colcon overlay 를 source 한 뒤 CMD 로
     노드(service server)를 자동 실행하므로, compose up 한 줄이 노드 기동까지 일으킨다.

robot_control(실제 pick 모션 + 무한 루프)은 이 launch 에 포함하지 않는다. bringup 은
인프라(드라이버+카메라+컨테이너)만 올리고, 작업 시작은 분리한다. 인프라 기동 후 별도
터미널에서 수동 실행한다(음성 명령 흐름이라 Ctrl+C 로 자주 재기동 → 전용 터미널 권장):
    ros2 run robot_control robot_control

실행 전제 (이게 없으면 기동 실패):
  - 셸에 다음 3개가 source 돼 있어야 한다(overlay 가 dsr_bringup2/robot_control/DSR_ROBOT2 를 제공):
      set -a; source <repo>/resources/config.sh; set +a   # ROS_DISTRO/ROS_DOMAIN_ID/RMW/CYCLONEDDS_*
      source /opt/ros/jazzy/setup.bash                      # underlay
      source ~/cobot2_ws/install/setup.bash                 # overlay (colcon 빌드 산출물)
  - containers:=true 인 경우:
      * 이미지가 이미 빌드/pull 돼 있어야 한다(없으면 compose up 실패 → containers:=false 로).
      * <repo>/.env 존재(voice 의 OPENAI_API_KEY 런타임 주입; env_file 누락 시 compose 에러).
      * host 의 cyclonedds.xml 이 렌더돼 있어야 한다(컨테이너가 read-only mount; 없으면 mount 실패).

안전 경고:
  - mode:=real 은 기동 시 로봇 컨트롤러(host:=192.168.1.100, port 12345)에 연결을 시도한다.
    컨트롤러가 꺼져 있으면 controller_manager spawner 가 멈춘다. 기본값은 안전한 virtual(에뮬레이터).
  - 이 launch 는 드라이버/카메라/컨테이너만 올린다 — 자율 모션 없음. 실제 pick 모션은
    robot_control 을 수동 실행할 때 시작된다(아래 사용 예 참조).

사용 예 (robot_control 패키지에 설치됨 — colcon overlay source 후 패키지명으로 호출):
  # 에뮬레이터 + 카메라/컨테이너 없이 드라이버만(이미지·카메라 불필요한 점검)
  ros2 launch robot_control bringup_all.launch.py mode:=virtual camera:=false containers:=false
  # 실기 + 카메라 + 컨테이너(이미지 빌드/.env/cyclonedds.xml 준비 후)
  ros2 launch robot_control bringup_all.launch.py mode:=real host:=192.168.1.100
  # 인프라 기동 후, 별도 터미널에서 음성 pick&place 시작:
  ros2 run robot_control robot_control
"""
import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import (
    DeclareLaunchArgument,
    ExecuteProcess,
    IncludeLaunchDescription,
    RegisterEventHandler,
)
from launch.conditions import IfCondition
from launch.event_handlers import OnShutdown
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration

# 레포 소스 트리 루트 — compose 파일(containers/)과 config.sh(resources/)는 colcon 이
# install 하지 않는 레포 자산이라 여기서 직접 참조한다. 이 launch 는 robot_control 패키지로
# 설치되므로 __file__ 은 install/share/ 를 가리켜 레포를 못 찾는다. 대신 config.sh 가 export
# 하는 ROS2_JAZZY_TEST_REPO 를 쓴다(config.sh 를 source 하면 자동 설정 — 실행 전제). 미설정 시
# 표준 클론 위치로 폴백. 레포 경로는 한 곳(config.sh, 자기 위치에서 계산)에서만 정의된다.
REPO = os.environ.get("ROS2_JAZZY_TEST_REPO") or os.path.expanduser("~/ros2_jazzy_test")
COMPOSE = os.path.join(REPO, "containers", "docker-compose.yml")
CONFIG = os.path.join(REPO, "resources", "config.sh")

# compose 가 ${CYCLONEDDS_XML}/${ROS_DOMAIN_ID}/${RMW_IMPLEMENTATION}/${DOCKERHUB_USER}/${*_TAG} 를
# 보간하고 voice 가 ../.env 를 읽으므로, config.sh 를 먼저 source 해 환경을 채운 뒤 compose 를 호출한다.
_COMPOSE_UP = (
    f"set -a; source {CONFIG}; set +a; "
    f"docker compose -f {COMPOSE} up -d"
)
# down 은 짧은 stop timeout 으로 — launch shutdown 이벤트 루프가 닫히기 전에 끝나야 컨테이너가
# Up 인 채로 남지 않는다(컨테이너 노드는 SIGTERM 에 빠르게 반응). 절단 의심 시 수동 `docker compose down`.
_COMPOSE_DOWN = (
    f"set -a; source {CONFIG}; set +a; "
    f"docker compose -f {COMPOSE} down --timeout 5"
)


def generate_launch_description():
    args = [
        DeclareLaunchArgument(
            "mode", default_value="virtual",
            description="virtual=에뮬레이터(안전 기본) | real=실기 컨트롤러 연결",
        ),
        DeclareLaunchArgument(
            "host", default_value="127.0.0.1",
            description="로봇 IP. 실기는 192.168.1.100",
        ),
        DeclareLaunchArgument("port", default_value="12345", description="DSR 컨트롤러 포트(DRFL). 기본 12345"),
        DeclareLaunchArgument(
            "gui", default_value="false",
            description="dsr_bringup2 로 전달(단 upstream 에서 rviz 는 항상 뜸 — 인자 무효)",
        ),
        DeclareLaunchArgument(
            "camera", default_value="true",
            description="host RealSense(realsense2_camera) 기동 여부",
        ),
        DeclareLaunchArgument(
            "containers", default_value="true",
            description="yolo/voice 컨테이너 docker compose up -d 여부(이미지 빌드 선행 필요)",
        ),
    ]

    dsr_launch = os.path.join(
        get_package_share_directory("dsr_bringup2"),
        "launch", "dsr_bringup2_rviz.launch.py",
    )
    # realsense align-depth launch 는 launch/ 가 아니라 examples/align_depth/ 에 있다.
    rs_launch = os.path.join(
        get_package_share_directory("realsense2_camera"),
        "examples", "align_depth", "rs_align_depth_launch.py",
    )

    # 로봇 드라이버/컨트롤러. model/name 은 robot_control 의 하드코딩(m0609/dsr01)과 일치시켜 고정.
    robot_bringup = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(dsr_launch),
        launch_arguments={
            "mode": LaunchConfiguration("mode"),
            "host": LaunchConfiguration("host"),
            "port": LaunchConfiguration("port"),
            "model": "m0609",
            "name": "dsr01",
            "gui": LaunchConfiguration("gui"),
        }.items(),
    )

    # host 소유 카메라. 프로파일/플래그는 실측 검증된 값(color 1280x720@30, depth 848x480@30, align_depth).
    realsense = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(rs_launch),
        launch_arguments={
            "depth_module.depth_profile": "848x480x30",
            "rgb_camera.color_profile": "1280x720x30",
            "initial_reset": "true",
            "align_depth.enable": "true",
            "enable_rgbd": "true",
            "pointcloud.enable": "true",
        }.items(),
        condition=IfCondition(LaunchConfiguration("camera")),
    )

    # 컨테이너 기동. up -d 는 detached 즉시 반환 → launch 의 anchor 는 dsr_bringup2(장수 노드).
    compose_up = ExecuteProcess(
        cmd=["bash", "-lc", _COMPOSE_UP],
        output="screen",
        condition=IfCondition(LaunchConfiguration("containers")),
    )
    # launch 종료(Ctrl-C) 시 컨테이너 정리 — launch 가 컨테이너 수명주기를 소유.
    # 컨테이너를 launch 와 독립적으로 띄워두려면 containers:=false 로 두고 compose 를 수동 운영.
    compose_down = RegisterEventHandler(
        OnShutdown(on_shutdown=[
            ExecuteProcess(
                cmd=["bash", "-lc", _COMPOSE_DOWN],
                output="screen",
                condition=IfCondition(LaunchConfiguration("containers")),
            ),
        ]),
    )

    # robot_control(실제 pick 모션 + 무한 루프)은 이 launch 에 포함하지 않는다 — 인프라만 올리고
    # 작업 시작은 분리한다. 인프라 기동 후 별도 터미널에서 `ros2 run robot_control robot_control`.
    return LaunchDescription(
        args + [robot_bringup, realsense, compose_up, compose_down]
    )
