# viz — 실시간 YOLO + 음성 상태 시각화 창

RealSense color 화면 위에 **YOLO 실시간 박스 + 클래스**, 좌상단에 **wakeword / target / pos** 텍스트를 겹쳐 띄우는 데모·디버깅용 관찰 창.

기존 pick-and-place 동작은 건드리지 않는 add-on 이며, viz 토픽만 추가한다.

## 구성

| 파일 | 실행 위치 | 역할 |
|------|----------|------|
| `live_detection.py` | yolo-viz **컨테이너** | color 스트림 연속추론 → `/yolo/detections`(박스+클래스, JSON) publish |
| `viewer.py` | **host** | 원본 프레임 + 박스 + 상태 텍스트를 한 cv2 창에 합성 |

카메라 프레임은 host `realsense2_camera` 가 이미 publish 하므로, viewer 가 원본을 직접 구독하고 컨테이너는 박스 좌표만 보낸다(프레임 재전송 없음). 추론에 필요한 torch/ultralytics 는 컨테이너 전용이라 추론만 컨테이너에서 돈다.

## 토픽

| 토픽 | 타입 | publisher |
|------|------|-----------|
| `/camera/camera/color/image_raw` | sensor_msgs/Image | host realsense2_camera (기존) |
| `/yolo/detections` | std_msgs/String (JSON) | yolo-viz 컨테이너 (신규) |
| `/ui/current_task` | std_msgs/String (JSON) | robot_control (신규) |
| `/wakeword_detected` | std_msgs/Bool | voice get_keyword (기존) |

`/yolo/detections` 형식: `{"dets": [{"box": [x1,y1,x2,y2], "cls": "hammer", "conf": 0.91}, ...]}`
`/ui/current_task` 형식: `{"target": "hammer", "pos": "pos1"}` (idle 시 `{}`)

## 실행

### 1. host 카메라 기동 (필수)
```
ros2 launch realsense2_camera rs_launch.py align_depth.enable:=true
ros2 topic hz /camera/camera/color/image_raw   # 프레임 확인
```

### 2. yolo-viz 컨테이너 기동
전제: `~/.ros2_jazzy_test/cyclonedds.xml` 존재(dds-tuning), `.env` 의 `DOCKERHUB_USER`/`YOLO_TAG` 가 빌드된 yolo 이미지를 가리켜야 함.
```
set -a; source resources/config.sh; set +a
docker compose -f containers/docker-compose.yml --profile viz up -d yolo-viz
docker compose -f containers/docker-compose.yml logs -f yolo-viz   # 모델 로드 확인
ros2 topic echo /yolo/detections --once                            # 박스 JSON 확인
```

### 3. host viewer 기동
```
set -a; source resources/config.sh; set +a   # ROS_DISTRO 설정(단일 진실 소스)
source /opt/ros/${ROS_DISTRO}/setup.bash
python3 viz/viewer.py
```
창에 라이브 피드 + 공구 추적 박스가 뜬다. 좌상단 wakeword/target/pos 는 voice·robot_control 이 함께 돌 때만 채워진다(아니면 `-`). 종료: 창에서 `q`.

## 트러블슈팅

- **박스가 안 뜸 / `/yolo/detections` 가 비어 있음**: 컨테이너가 카메라 프레임을 못 받는 경우. 카메라 구독은 best-effort(SensorDataQoS)라 realsense publisher QoS 와 무관하게 호환되지만, 토픽명/도메인(`ROS_DOMAIN_ID=42`)·RMW 일치 여부와 `ros2 topic hz /camera/camera/color/image_raw` 로 host publish 자체를 먼저 확인한다.
- **viewer 창이 안 뜸**: host 데스크톱 세션의 `DISPLAY` 가 필요하다(SSH 면 X11 forwarding 또는 로컬 데스크톱에서 실행).
- **컨테이너가 cyclonedds.xml mount 실패로 안 뜸**: dds-tuning(`install.sh` 마지막 step 또는 단독 실행)이 먼저 끝나 host 에 파일이 렌더돼 있어야 한다.
- **GPU 미사용(느림)**: `nvidia-container-toolkit` 가 host 에 설치돼 있어야 컨테이너가 GPU 를 본다. `docker logs` 에서 추론 device 확인.
