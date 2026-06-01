# TROUBLESHOOTING

설치/실행 중 마주친 증상과 복구 절차 카탈로그. 증상 → 원인 → 복구 → 예방 순.

---

## 재부팅 후 검은 화면 + 깜빡이는 `_` 로 부팅 정지

**증상**: NVIDIA 드라이버 설치 후 재부팅하면 화면이 검은색이고 좌상단에 `_` 커서만 깜빡이며 부팅이 진행되지 않음. `nomodeset` 커널 파라미터를 줘도 동일.

**원인** (한 가지 이상 중첩 가능):
1. **반쪽 HWE 커널 — `modules-extra` 누락**: 드라이버 자동선택(`ubuntu-drivers install`)이 HWE 커널 이미지를 의존성으로 끌어오지만 `linux-modules-extra-<kernel>`(wifi / 일부 USB 입력 드라이버 수록)는 함께 오지 않아, 그 커널로 부팅하면 wifi·USB 키보드가 사라진다. 그래픽이 아니라 입력/네트워크가 죽는 형태로도 나타남.
2. **드라이버 커널 모듈 부재**: 부팅하는 커널에 nvidia 커널 모듈(`nvidia.ko`)이 빌드/설치되지 않아 디스플레이 드라이버가 없음. nouveau 는 nvidia 패키지가 블랙리스트하므로 폴백도 없어 검은 화면.

**복구**:
1. **이전(정상) 커널로 부팅** — 부팅 시 `Shift`/`Esc` 로 GRUB → `Advanced options for Ubuntu` → 모듈이 온전한 이전 커널 선택. wifi·키보드가 돌아오면 현재 커널만 깨진 것.
2. **드라이버 제거로 디스플레이 복구** (그래픽이 검은 화면일 때) — GRUB → recovery mode → root shell:
   ```bash
   mount -o remount,rw /
   apt-mark unhold 'nvidia-driver-*' 2>/dev/null || true
   apt-get purge -y '^nvidia-.*'
   apt-get autoremove -y
   reboot
   ```
   nouveau 로 정상 부팅됨. (주의: `autoremove` 가 지우는 목록을 확인 — 의도치 않은 커널/모듈 제거 방지.)
3. **깨진 커널에 모듈 채우기** — 정상 커널로 부팅한 뒤(네트워크 필요: wifi 죽었으면 휴대폰 USB 테더링/유선), 대상 커널용 모듈을 설치:
   ```bash
   sudo apt-get install -y \
     linux-image-<kernel> linux-modules-<kernel> linux-modules-extra-<kernel>
   sudo update-initramfs -u -k <kernel>
   ```
   커널 모듈은 버전별로 따로 설치되므로, 현재 실행 커널이 달라도 대상 커널용 패키지를 설치하면 그 커널로 부팅했을 때 적용된다.

**예방** (현재 installer 에 반영됨):
- 커널 베이스라인 단계(`resources/kernel-baseline.sh`)가 nvidia 보다 먼저 실행돼 `linux-generic-hwe-24.04` + 헤더 메타를 `--install-recommends` 로 설치 → 이미지 + 헤더 + `modules-extra` 를 항상 함께 보장.
- nvidia 드라이버를 자동선택 대신 명시 핀(`nvidia-driver-595` closed)으로 설치하고, 커널-모듈 메타로 커널 업데이트를 자동 추적. (Optimus 노트북 디스플레이 안정성 위해 open 대신 closed 채택.)
- nvidia 설치 직후 **부팅 예정 커널에 `nvidia.ko` 가 실제로 있는지 검증**하고 없으면 재부팅 단계로 넘어가기 전에 중단(silent brick → 재부팅 전 시끄러운 실패).

**참고 — Secure Boot 가 켜진 환경** (이 프로젝트 타깃은 disabled): 서명 안 된 nvidia DKMS 모듈을 커널이 거부해 같은 검은 화면이 날 수 있다. `mokutil --sb-state` 로 확인, BIOS 에서 Secure Boot 비활성 또는 MOK 등록(`sudo mokutil --import /var/lib/dkms/mok.pub` 후 재부팅 시 파란 화면에서 enroll) 필요.

---

## 왜 커널이 여러 개 설치되나 (정상 동작)

설치 후 `/lib/modules` 에 커널이 2개 이상 보이는 것은 정상이다.
- **이전 커널 보존(안전망)**: 커널 업데이트 시 apt 가 직전 커널을 지우지 않아, 새 커널이 부팅을 깨면 GRUB 에서 되돌릴 수 있다.
- **GA vs HWE 트랙**: 24.04 는 출시 커널 라인(GA, 6.8.x)과 신형 하드웨어 지원용 롤링 트랙(HWE, 6.11→6.14→6.17…)이 별개 패키지로 공존한다. 본 installer 는 HWE 트랙으로 통일(`linux-generic-hwe-24.04`).
