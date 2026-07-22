# README §기동 — m0609 와 RealSense 개별 기동 안내 (설계)

- 일자: 2026-07-22
- 브랜치: `feat/m0609-rg2-bringup`
- 변경 범위: `README.md` §기동 + `containers/docker-compose.yml` 주석. 실행 코드 변경 없음.

## 배경

`m0609_rg2_bringup/bringup.launch.py` 는 RealSense 드라이버를 조건부로 띄운다.

```python
# ~/M0609_RG2_Integration/src/m0609_rg2_bringup/launch/bringup.launch.py:249-252
camera_enabled = PythonExpression([
    "'", LaunchConfiguration('mode'), "' == 'real' or '",
    LaunchConfiguration('camera'), "' == 'true'"
])
```

| 실행 | RealSense 드라이버 |
|---|---|
| 기본 (`mode:=virtual`, `camera:=false`) | 안 뜸 |
| `camera:=true` | 뜸 |
| `mode:=real` | 무조건 뜸 (`camera:=false` 를 줘도 OR 라 무시) |

즉 **"카메라 없이 m0609 만" 은 이미 기본 동작**이다. 그런데 README 가 그 사실을
드러내지 않아, 카메라를 따로 띄워 배우는 흐름(강의 진행 방식)을 안내할 자리가 없다.

목적은 하드웨어 부재 대응이 아니라 **학습용 분리 기동 안내**다. `mode:=real` 의
카메라 강제 기동은 본 작업 범위 밖이다.

## 문제 — 토픽 경로가 두 방식에서 갈린다

| 기동 방식 | 토픽 |
|---|---|
| 통합 (`camera:=true`) — launch `:271-272` `namespace='/'`, `name='camera'` | `/camera/*` |
| README 현행 개별 (`rs_align_depth_launch.py`, upstream 기본) | `/camera/camera/*` |

`/camera/camera/*` 는 누가 매핑한 것이 아니라 upstream `realsense2_camera` 의 기본값이다.
노드가 스트림 토픽을 private(`~/`)으로 만들고(최종 이름 `/<node_ns>/<node_name>/<stream>`),
노드 기본 namespace 가 upstream 소스에 `/camera` 로 하드코딩돼 있어
(`realsense_node_factory.cpp:34` `RosNodeBase("camera", "/camera", ...)`) 중복 한 단계가 생긴다.
m0609 launch 는 이를 **실행 시점 인자로만** 덮어쓴다 — realsense 패키지 소스는 무패치.

소비자(`object_detection`, `pick_and_place_*` 의 `realsense.py::ImgNode`)는 이 경로를 구독한다.
따라서 학습자가 개별 기동으로 갈아타는 순간 경로가 어긋나 **에러 없이 토픽만 빈다**.
(설계 시점에는 소비자가 상대 이름 + `-r img_node:__ns:=/camera` remap 이었다. 그 remap 누락이
실제 사고로 이어져 2026-07-22 에 절대 경로로 되돌렸다 — ADR-037. 아래 4번 항목도 그에 맞춰 갱신.)

## 설계

README §기동을 네 군데 고친다.

1. **표 `:89` 문구** — `로봇 + 그리퍼 + 브라켓/카메라 모델 + RViz` 를
   `로봇 + 그리퍼 + RViz (URDF 에 브라켓·D435 모델 포함 — 카메라 드라이버는 안 뜸)` 로.
   현재 문구는 URDF 모델을 뜻하는데 드라이버가 뜨는 것처럼 읽힌다.

2. **개별 기동 블록 도입부** — 기본값에서 RealSense 가 뜨지 않는다는 것, 그래서 카메라를
   따로 띄워 배우는 흐름이 가능하다는 것을 한 줄로 명시.

3. **"RealSense 카메라만 따로" 블록 (`:142-161`) 교체** — 개별 기동도 `/camera/*` 를 내도록
   `ros2 run` 방식으로 바꾼다. launch `:268-283` 의 Node 설정을 그대로 CLI 로 옮긴 것이다.

   ```bash
   ros2 run realsense2_camera realsense2_camera_node --ros-args \
     -r __ns:=/ -r __node:=camera \
     -p enable_color:=true -p enable_depth:=true \
     -p depth_module.depth_profile:=848x480x30 -p rgb_camera.color_profile:=1280x720x30 \
     -p align_depth.enable:=true -p enable_rgbd:=true -p enable_sync:=true \
     -p pointcloud.enable:=true -p initial_reset:=true
   ```

   remap 두 개가 필요한 이유(upstream 기본 ns 하드코딩 → 안 주면 `/camera/camera/*`)를 2줄로 덧붙인다.
   구 `rs_align_depth_launch.py` 명령은 각주 한 줄로 강등한다 — 타 자료의 그 명령은
   `/camera/camera/*` 로 나온다는 대조용.

4. **학습용 3터미널 흐름 추가** — 터미널1 `bringup.launch.py`(카메라 없이) /
   터미널2 위 `ros2 run` realsense / 터미널3 소비자 노드.
   통합 기동과 토픽이 동일하다는 점을 명시. (소비자가 절대 경로로 바뀌어 remap 인자는 불필요 — ADR-037)

5. **`containers/docker-compose.yml:13-15` 주석 정정** — 소스와 어긋난 서술 2건을 고친다.
   `:14` 는 launch 가 "namespace/name 둘 다 `camera`" 로 띄운다고 적었으나 실제는
   `namespace='/'`, `name='camera'` (launch `:271-272`). `:13,15` 는 "토픽 이름은 그대로 /
   rs_launch.py 기본값과 같은 `/camera/*`" 라 적었으나 upstream 기본은 `/camera/camera/*` 이고
   경로는 실제로 바뀌었다. 같은 레포 `containers/README.md:54` 의 정확한 서술에 맞춘다.
   주석만 고치며 compose 의 서비스 정의는 건드리지 않는다. README 변경과는 별개 논리 단위라
   **커밋을 분리**한다.

### 채택 근거

개별 기동을 `/camera/camera/*` 인 채로 두고 소비자 remap 을 그때만 바꾸도록 안내하는 안도
있었으나, 학습자가 경로 두 벌과 remap 두 벌을 외워야 한다. "따로 띄워도 통합과 똑같은
토픽이 나온다" 가 개념적으로 단순하고, 소비자 실행 명령이 한 벌로 유지된다.

`rs_align_depth_launch.py camera_namespace:=/ camera_name:=camera` 로 줄이는 안은 그 두 인자의
jazzy 지원 여부가 미검증이라 채택하지 않았다. 실측 머신에서 확인되면 3의 `ros2 run` 블록을
대체할 수 있다.

## 검증 상태

- **Fact** — `-r __ns:=/ -r __node:=camera` 가 노드를 `/camera` 에 띄운다.
  2026-07-22 실측(ROS humble, `demo_nodes_cpp talker`): 인자 없이 노드 `/talker`,
  인자 적용 시 노드 `/camera`. realsense 의 private 스트림 토픽은 이 노드 아래 `/camera/*` 로 나온다.
- **Fact** — 파라미터 9개 값은 launch `:273-282` 와 대조 일치.
- **Claim (미검증)** — 위 `ros2 run` 명령이 실제 D435 를 물고
  `/camera/color/image_raw`, `/camera/aligned_depth_to_color/image_raw`,
  `/camera/color/camera_info` 를 내는 것. jazzy + 실 카메라가 필요하다.
  **실측 머신 게이트** — 통과 시 본 문서 이 절에 일자를 기록한다.
  이 게이트는 **머지를 막지 않는다**(사용자 결정 2026-07-22 — 실측은 나중에).
  통합 기동(`camera:=true`) 경로는 이미 실측된 바 있어 학습자가 막히면 그쪽으로 우회 가능하다.

실측 확인 명령:

```bash
# 터미널 1
ros2 launch m0609_rg2_bringup bringup.launch.py
# 터미널 2
ros2 run realsense2_camera realsense2_camera_node --ros-args -r __ns:=/ -r __node:=camera ...
# 터미널 3
ros2 topic list | grep '^/camera/'   # /camera/camera/ 가 하나도 없어야 통과
```

## 범위 밖 (별건으로 기록)

- `mode:=real` 이 카메라를 강제 기동하는 것 — 끄려면 `M0609_RG2_Integration` 레포의
  `camera_enabled` OR 조건을 고쳐야 한다. 타 레포 변경이라 분리.
- `docs/lecture-jazzy/협동로봇2_강의안_jazzy.md:84` 가 구 `rs_align_depth_launch.py` 를 쓴다.
  미추적 문서이며 본 작업이 건드리지 않는다. 강의안을 새 경로로 옮길지는 별도 판단.
