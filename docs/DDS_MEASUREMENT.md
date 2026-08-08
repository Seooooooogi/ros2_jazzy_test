# CycloneDDS 구성별 측정 기록

> append-only. 새 측정은 아래에 추가하고 기존 항목을 고쳐 쓰지 않는다.

## 측정 환경

- 날짜:
- 머신 A: 호스트명 / IP / 링크(유선·무선) / ROS distro
- 머신 B: 호스트명 / IP / 링크(유선·무선) / ROS distro
- AP: 모델 / mesh 구성 여부
- 발행 파라미터: `--width` `--height` `--hz` (무선 대역 한계로 낮췄다면 그 값과 이유)

## 결과

| 구성 | discovery(초) | 드롭률 1회 | 2회 | 3회 | 가입 NIC | 소켓 rb | 컨테이너 |
|---|---|---|---|---|---|---|---|
| m0 unset | | | | | | | |
| m1 SUBNET | | | | | | | |
| m2 LOCALHOST+peers | | | | | | | |
| m3 현행 XML(기준선) | | | | | | | |

## 채택

- 채택 구성:
- 근거:
- 미채택 구성과 그 이유:

## 통신이 실제로 도는지 확인하는 명령

SPDP 멀티캐스트 주소(`239.255.0.1:7400`)는 RTPS 규격 기본값이라 설정 파일 어디에도
적히지 않는다. `~/.bashrc` 는 *선택*을 적는 곳이고, 실제로 도는지는 런타임에서만 보인다.

```bash
# 어느 NIC 가 SPDP 그룹에 가입했나
ip maddr show | awk '/^[0-9]+:/{ifc=$2} /239\.255\.0\.1/{print ifc}' | sort -u

# 누가 7400 을 듣고 있나
ss -uanp | grep :7400

# 멀티캐스트가 실제로 흐르나 (두 터미널 · 두 머신)
ros2 multicast receive
ros2 multicast send
```
