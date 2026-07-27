# Session Handoff — LATEST

> 매 세션 종료 전 갱신. 글로벌 `SessionStart` hook 이 자동 로드.
> Forward-looking only — 본 세션에서 한 일이 아니라 다음 세션이 할 일.
> 두 머신 공유 — **[실측]** 머신(로봇/카메라 실기) + **[문서]** 머신(git/문서/lessons). 항목에 담당 표기.

## 다음 세션 — 무엇보다 먼저

**(2026-07-27 세션 — Notion 설치 3페이지 워크스페이스 재명명·역할 재분배 + 브랜치 정리)**
- **워크스페이스 rename `~/cobot_ws` → `~/cobot2_ws`(사용자 결정, 완료)**: Notion 3페이지 + 레포 17파일 동시 반영. 진실 원천은 `resources/config.sh:49` `DSR_WORKSPACE` 기본값(`YOLO_WS`/`VOICE_WS` 는 파생이라 자동 추종). **rename 하지 않은 것 3종** — ① 레포 안 빌드 컨텍스트 staging `cobot_ws/`(`Dockerfile:75-76` COPY 경로 · `build-all.sh:90` · `.gitignore`/`.dockerignore`) ② 구 humble 문맥(COMPATIBILITY humble 행, LECTURE_MIGRATION Before 절, 강의안 "구 `cobot_ws/src/{cobot1_ws,cobot2_ws}`") ③ 불변 기록(ADR·specs·plans·roadmap·backup·세션기록).
- **⚠ [실측] 기설치 머신 조치 필요**: 이미 `~/cobot_ws` 로 빌드된 머신은 스크립트가 새 경로를 보므로 `export DSR_WORKSPACE="$HOME/cobot_ws"` 로 유지하거나 새 경로 재빌드(colcon `install/` 에 절대 경로가 박혀 디렉토리 rename 만으로는 오버레이가 깨짐). README 에 안내 추가함.
- **venv ws rename `~/cobot_demo_ws` → `~/cobot_venv_ws`(사용자 결정, 완료)**: Notion 2페이지 + 레포 5파일(`scripts/venv-demo/LAB.md`, `scripts/venv-demo/uv/setup.sh`, `setup-app.sh` 안내문, `resources/colcon-build.sh` 주석, `README.md`). 불변 기록(ADR-030·plans·specs)은 옛 이름 유지.
- **[문서] main 승격 미실행**: 위 두 rename 은 `feat/m0609-rg2-bringup` 에만 있다(main 대비 31 커밋). `bash scripts/merge-to-main.sh` 로 승격해야 하며, `.claude-main-exclude` 때문에 **main 에 반영되는 건 `README.md`·`.gitignore`·`setup-app.sh`·`resources/*.sh`·`containers/{README.md,bringup.sh,docker-compose.dev.yml}` 뿐** — `docs/`·`CLAUDE.md`·`scripts/`(LAB.md·uv/setup.sh 포함)·`.claude/` 는 main 제외 경로라 dev 에만 남는다.
- **[문서] Notion 부모 인덱스 페이지 미반영**: `(협동2) Humble→Jazzy 마이그레이션` 페이지(§1-1·§1-2·§2-1 mermaid·§3-1 검증 순서·§4-2 홈 구조)에 구 이름 잔존 — 사용자 승인 대기. 단 §4-1 레포 구조의 `cobot_ws/` 는 **빌드 컨텍스트 staging**(Dockerfile:75-76 COPY 경로, `build-all.sh:90`)이라 rename 대상 아님.
- **Notion 페이지 역할 재분배(완료)**: 1.base = doosan/m0609/onrobot 만 clone(cobot2.zip 미삽입) + host voice Python 설치 + corecode.zip 배치·검증(Calibration·VoiceProcessing) / 3.container = 그 ws 에 cobot2 **삽입 후 추가 빌드**(중복 clone·voice 설치 절 삭제).
- **브랜치 정리(완료)**: `feat/camera-naming`(m0609 에 전부 포함)·`feat/application-shell`(내용은 이미 main 반영, 머지 시 통합·삭제된 `run-step.sh`/`host-python-deps.sh`/`realsense-sdk-install.sh` 부활 위험 → 로컬 태그 `archive/application-shell` 로만 보존)·`refactor/installer-shell` 을 로컬·원격 삭제. 잔존 = `feat/m0609-rg2-bringup`(활성)·`feat/application-containers`(main 흡수 완료)·`main`·`backup/pre-github-sync-2026-05-29`(로컬 전용).
- **M0609 로컬 `jazzy` ff 갱신(완료)**: `574135e → 6239903`, main/jazzy/origin 전부 동일.

**(2026-07-24 세션 — RViz pointcloud flicker 근본해결(M0609 3커밋) + DSR 서비스 경로 corecode 반영 + 실측 머신 현장 이동)**
- **완료 요약(참조)**: RViz PointCloud2 status error↔OK 반복 = 원인 3중 — ① `pointcloud.stream_filter` 미지정 시 0(ANY)→무텍스처 cloud(`2dec7d2`) ② rs_launch 우회 시 IMU 가 C++ 기본값으로 켜져 D435i "Motion Module failure"(`fd925fc`) ③ **TF 스로틀 2단**: jsp 기본 10Hz(`ad4ac36`) + rsp `publish_frequency` 기본 20Hz(`6239903`) → cloud stamp 시각 TF lookup 실측 27% 실패 → 두 값 100 으로 0% (599 프레임 probe). 실기 status 안정 사용자 확인. **M0609 fix 는 반드시 `main`+`jazzy` 양쪽 push** — 배포(clone -b jazzy·[실측] 머신)는 jazzy 기준이라 main 만 밀면 전달 안 됨(이번에 main:jazzy ff 동기, HEAD `6239903`).
- **[실측] ~/corecode 구본 패치 확인(미완)**: DSR jazzy 서비스 경로 = `/dsr01/dsr_controller2/system/…`(노드명 prefix, `dsr_controller2.cpp:317`). 신 corecode.zip([문서] 레포 루트, 재패키징·실사 완료 — rokey_study.ipynb 경로 4곳 + `data_recording.py:13` `DR_init.__dsr__id` 오탈자)으로 재배치하거나 현장 sed 2줄(사용자에게 안내됨). 게이트: `grep -c dsr_controller2/system ~/corecode/DRL_Tutorial/rokey_study.ipynb` → 4.
- **[실측] 미해결 2건**: ① `groups: cannot find name for group ID 992` — 원인 미확정(재로그인 후 재발 여부 + `getent group 992` / `getent group docker render`). ② modbus 실습 import 실패 원인 판별(코드는 pymodbus 3.x 정상 — 후보: 노트북 실행 위치(`from onrobot import RG` 는 로컬 파일) or 커널 환경에 pymodbus 부재. 판별 명령 안내됨). 참고: `'NoneType' object has no attribute 'create_client'` = DSR_ROBOT2 를 `DR_init.__dsr__node` 주입 전 import(노트북 셀 순서) — 코드 결함 아님, Restart & Run All 로 해소.
- **⚠ 원격 접근 변경**: [실측] 머신이 타 장소로 이동, IP `172.18.0.169`(구 `192.168.1.11` 무효) — [문서] 머신에서 직접 SSH 불가(사설망 분리). reverse tunnel(`ssh -N -R 2211:localhost:22 rokey@teamsparkx.iptime.org`)은 이 박스 22 외부 포워드 여부 unknown. SSH key = `~/.ssh/rokey_test_diag`. 원격 ros2 CLI 는 daemon 이 stale 이면 node list 빈값 — `ros2 daemon stop` 후 재시도.
- **[문서] 레포 문서 IMU off 인자 미반영(diverge)**: 수동 카메라 명령의 `-p enable_accel:=false -p enable_gyro:=false` 가 Notion 두 페이지(pick&place·host-container)엔 반영, 레포 문서(LAB.md §8·§9, 강의안, spec 2026-07-22)엔 미반영 — 사용자 승인 대기.

**(2026-07-20 세션 2 — venv LAB 2차 정리 + 배포 zip 마이크 16kHz 선반영, push 완료)**
- **LAB 전면 개편**(`scripts/venv-demo/LAB.md`, §1-10): Notion 설치 매뉴얼 양식·사족 제거. `ppv_` rename 폐기(ADR-032), dsr 2패키지(`dsr_common2`/`dsr_msgs2`)는 **ROKEY-SPARK fork 직접 `git clone --depth 1`**(§2 — 커리큘럼상 venv 가 host 설치보다 선행 가능, fork = 호환 패치 반영본 실사됨), od_msg 는 cobot2 소스에서 복사. 실행 터미널은 `~/cobot_ws/install` source 제거(§8-9 터미널 1 bringup 만 host 필요). OPENAI 키 = `resource/.env` 빌드 내장(셸 export 폐기).
- **코드 수정 단계 폐지 원칙**(ADR-033): 학생이 sed/diff 로 소스를 고치는 절차 금지 — 배포본 선반영. `~/ros2_jazzy_test/cobot2.zip`·`corecode.zip`(미추적) 마이크 코드 **16kHz 하드코딩 + `resolve_input_device()`** + langchain_core import + `audio_device.py` 동봉으로 재패키징(py_compile 전건·`48000` 잔존 0건·zip 실사 완료). LAB §5 = 장치 확인만(`VOICE_MIC_DEVICE` override 안내).
- **⚠ [실측] 머신**: 기배치 `~/cobot_ws/src/cobot2` 는 구본 — **새 cobot2.zip 으로 재배치 필요**(README 3-1 은 mv 만, COLCON_IGNORE 절차 소멸).
- **[실측] 게이트(미완)**: ① LAB §7 `interface imports OK`(dsr 2패키지 단독 빌드 검증) ② live wakeword "Hello Rokey" confidence>0.3(§9, 16kHz 선반영본 첫 실측) ③ 아래 uv setup.sh 3건(불변).

**(2026-07-20 세션 — 데모 venv 학생 배포/복구용 uv 경로 구현 완료, 타깃 실측만 남음)**
- **[실측] 최우선**: `bash ~/ros2_jazzy_test/scripts/venv-demo/uv/setup.sh` 전체 실행 + 배포 게이트 3건 — ① `readlink -f ~/cobot_demo_ws/.venv/bin/python` = system 3.12(uv-managed 경로 아님) + 재실행 멱등 ② torch `2.11.0+cu128` + `cuda.is_available()==True` ③ ROS 소스 후 venv python 에서 `import rclpy`. 절차 상세 = `docs/plans/2026-07-20-venv-uv-student-setup.md` Task 4. **3건 통과 전 학생 배포 금지**(spec 게이트) — 통과 시 spec(`docs/specs/2026-07-20-venv-uv-student-setup-design.md`) 게이트 절에 일자 기록.
- 배경: 2026-07-10 "uv 불가" 기각 근거 3건이 실측으로 무효화(`dependency-metadata` 의존 교체 + `override-dependencies` numpy<2 + explicit index cu128). LAB one-by-one 은 커리큘럼 자산으로 불변, uv 는 복구/배포 병행 경로. 커밋 4건(8e0e9f5~5f0ae3f) 완료.

**(2026-07-16 세션 — Notion `sonmiran.oopy.io` Isaac Sim 강의 백업 = installer 무관 side-task, 사실상 완료) — git repo 코드/문서 무변경. installer forward-looking 항목 전부 불변.**
- **작업**: 소스 `https://sonmiran.oopy.io/`(Isaac Sim 로보틱스 강의, ~20p, 2295 block) → 타깃 `teamsparkx › … › 8기 강의자료 백업`(page `39e563918e598029aa8cea786188cda2`). 요구 = **원본 양식과 완전히 동일**. 첨부는 타깃 재업로드로 소스 링크 절단.
- **완료**: root 본문 + 인라인 DB(19행, 순서보존) + nested 서브페이지 19개 + **이미지 251개 전부 타깃 S3(`4ae7593c…`) 재업로드**. 검증 = 페이지별 write remaining=0 게이트 + spot-check(nested-142 21img·da1 line-14 클린).
- **⚠ 함정(재사용)**: (1) `create-attachment` 업로드는 **1시간 내 미첨부 시 만료** → per-page atomic(업로드↔write 수초내). (2) workflow upload agent 는 StructuredOutput 미호출 ~40% → 최종 5페이지(115img)는 **메인루프 업로드**(100% 안정)로 전환. (3) 세션한도는 subagent spawn 만 차단·메인루프 MCP 는 동작. (4) 이미지 fresh URL 재해석 = `www.notion.so/image` proxy 302(`resolve_r5.py`, curl). (5) 산출물 = `/tmp/claude-1000/…/scratchpad/sonmiran/`(세션 스크래치, 비영구).
- **GIF 삽입(완료·종료)**: 사용자가 페이지 `9c5cf6499f9d44e7bcf1c9f559d1af75`("STA—Pick & Place + ROS 색상 감지") 터미널2 아래에 수동 드래그 완료 — 타깃 S3(`4ae7593c…`) 서빙, "…미포함" 노트 제거. 삽입본 = 14MB 압축 `peek_hi.gif`(700px/10fps). **사용자가 화질 tradeoff 고지 후 "압축본 유지"로 명시 종료**(원본 1776×962/106MB 미교체 = 사용자 선택). 원본은 API 자동삽입 불가(URL-import 50MiB 캡·public repo 금지)라 수동 드래그만 가능했고, 사용자가 압축본으로 확정. `~/peek_original_1776x962_106MB.gif`(홈 복사본) = rm 가능.
- **상태**: **완료·종료. 후속 없음.** GIF 화질 1점만 압축(사용자 수용), 그 외 구조·이미지·DB뷰 전부 원본 정합.
- **DB 뷰 정합(완료)**: 타깃 인라인 DB 뷰(`view://7bfabc6c-51be-44dc-97a0-7f53c17166c6`)를 소스 "강의안" 뷰와 동일하게 = 이름 "강의안", 표시 컬럼 `차시/이름/status` 순, 나머지 4개(주제/순서/환경/키워드) 숨김. 소스 그라운드-트루스 = `collection_views.json`(강의안 view, 차시/이름/status True).
- **상태**: 산출물 = 타깃 Notion 워크스페이스만(git repo·설치 스크립트 무영향).

**(2026-07-14 세션 — Notion 강의자료 마이그레이션 = installer 무관 side-task, 완료) — git repo 코드/문서 무변경. 아래 installer forward-looking 항목 전부 불변.**
- **작업**: 소스 Notion `Doosan-Rokey-5기`(indecisive-freedom) 강의 대시보드 → 타깃 `teamsparkx › 운영 2팀 › 수업별 강의자료 › 지능1 › 지능1 강의자료`(page `39d563918e5980ec9950fb5148606030`) 전면 이관. 스코프 = 강의 콘텐츠 전용(root 본문 + DAY 1~10 강의안 40 서브페이지).
- **첨부 처리**: 176개(이미지/zip/pdf 등)를 타깃 워크스페이스로 다운로드→재업로드 → **소스 링크 절단**(`prod-files-secure … 4ae7593c…` 서빙 확인). `.sh` 확장자 미지원 → `.txt` content 로 우회.
- **DB 재생성**(사용자 추가 요청): 일정 타임라인(**148행**, data_source `7aa9a6b2-3ee6-425e-b4c1-42de9866229e`) + Daily 일정/과제(1행, `a2dc64b2-4fa8-4b04-bb21-4bc406601eef`) = 실제 Notion DB 로 재생성. root 최하단 child DB 로 배치(move-pages 는 parent 만 변경·페이지 내 위치 이동 불가 → "# 일정" 섹션엔 물리 배치 불가, note 로 하단 참조 안내). **148행 = create-pages 응답 배열 카운트(50+50+48) + batch 재구성 정합(order-preserving)으로 확정**. (구 타임라인 DB 는 workflow agent 자가보고 카운트가 검증 불가(145 vs 147)라 trash 후 메인루프로 재삽입.)
- **⚠ 함정 메모(재사용 시)**: (1) Notion 비공식 API 는 urllib 403 → curl. (2) `loadPageChunk` 는 깊은 nested block 을 누락 → container 를 pageId 로 재fetch 해 closure 까지 복구(이번에 269 block·code 370·image 58 복구). (3) `queryCollection` blockIds = `result.reducerResults.collection_group_results.blockIds`. (4) `query-data-sources`/`syncRecordValues` = Business plan/Cloudflare 로 막힘. (5) datetime naive 입력 = 워크스페이스 TZ(KST) 해석 후 UTC 저장. (6) 스크립트·산출물 = `/tmp/claude-1000/…/scratchpad/rokey5/`(세션 스크래치, 비영구).
- **상태**: **완료. 후속 없음.** 산출물 = 타깃 Notion 워크스페이스만(git repo·설치 스크립트 무영향).

**(2026-07-10 [문서] 세션 — 인스톨러 디커플링 + ADR-027 잔재 문서 정리) — 코드 커밋·push 완료(`966a78b`, origin/feat 동기). 문서 정리는 uncommitted(커밋 미요청). main 미머지.**
- **인스톨러 디커플링(`966a78b` = 현 HEAD, ADR-028+029, 이미 push)**: ① OPENAI 키 셋업 단계 **완전 폐기** — `resources/openai-key-setup.sh` 삭제, `.env` 를 레포 밖 **`~/.config/cobot2/.env`**(`COBOT2_ENV` = config.sh 단일소스, XDG 존중)로 이관, 사용자가 수동 생성(인스톨러 자동생성 없음). `bringup.sh` 가 `${COBOT2_ENV}` 로드(없으면 비-fatal 경고). ② corecode **git 제거**(29파일) → 사용자가 corecode.zip 을 `~` 에 풀어 `~/corecode` 배치, `install.sh` step 10 = `corecode-verify.sh`(verify+안내+exit, `obtain_cobot2` 미러). `corecode.zip`(untracked, 재생성본 = fix 반영·39파일) = **배포 산출물, 유지**. setup-app workspace 스텝 +7→+6.
- **[실측] 검증 대기**: 클린설치로 (a) `~/.config/cobot2/.env` 미생성 시 bringup 비-fatal 경고, (b) `~/corecode` 미배치 시 step 10 안내+exit·배치 시 통과(멱등), (c) host voice 노드가 `${COBOT2_ENV}` 에서 키 로드 e2e.
- **ADR-027 잔재 문서 정리(이 세션, uncommitted)**: voice=컨테이너로 서술하던 잔재를 host 실행(ADR-027)으로 정정. 세 축 반영 = voice=host / corecode=`~/corecode` 외부 / OPENAI=`~/.config/cobot2/.env`. **tracked**: `docs/TRAINEE_PRACTICE_PATH.md` Step 4 전면 재작성(존재하지 않는 `voice-processing` 컨테이너 기동 runbook → host `cd ~/corecode/VoiceProcessing` 직접 실행 + 치트시트·smoke 요약). **untracked WIP**: `docs/LECTURE_MIGRATION_humble-to-jazzy.md`(12곳 — Before/After 표·§1~4·§8·부록), `docs/lecture-jazzy/{협동로봇2_강의안,개발환경_설치}_jazzy.md`.
- **의도적 미변경(잔재 아님)**: `docs/decisions/README.md`(불변 ADR), `docs/DEVELOPMENT_ROADMAP.md`(날짜 진행 로그), `docs/specs/*`(날짜 설계 스냅샷), `docs/CONTAINER_VS_HOST.md`(의도적 branch 대비 — voice-as-container = 교육 예시, ADR-027 환원 line 10 에 이미 명기), `docs/COMPATIBILITY.md` §application-shell 변종(branch-variant provenance). `.ipynb_checkpoints/*-checkpoint.md`(gitignored Jupyter 그림자) 미수정.
- **후속(비커밋)**: ① corecode.zip 을 실제 배포 채널에 업로드. ② README 사용자 대면 변경(.env 경로·corecode 수령)을 **main 에도 별도 적용** — README 는 `.main-keep-ours` 라 dev→main 자동 전파 안 됨. ③ 문서 정리 커밋은 사용자 요청 시(merge-to-main 이 `docs/` 자동 스트립 → main 무영향).

**(2026-07-08 [문서] 세션 — 설치 스크립트 주석 전면 리팩토링) — 커밋·push 완료(`72d23bb`, origin/feat 동기). main 미머지.**
- **내용**: 설치 셸 스크립트 25개(`install.sh`·`setup-app.sh`·`resources/*.sh`·`containers/*.sh`+`template/entrypoint.sh`) 주석 4가지 정리 — (1) 영어→한글 (2) Google Shell Style 형식(비자명 함수 `####` 블록 + `Globals`/`Arguments`/`Outputs`/`Returns`, 사소한 헬퍼 한 줄) (3) 초심자 난이도(전문 용어 한글 부연) (4) 개조식 종결(짧은 구·명사형). **코드 0 변경**(주석 only — `git show HEAD` 대비 code-identical 검증).
- **검증**: `bash -n` 25개 PASS + `shellcheck -x install.sh setup-app.sh resources/*.sh containers/*.sh containers/template/*.sh` **exit 0**. 식별자·경로·`# shellcheck` 지시어·`echo` 문자열·저작권 배너 = 영어 byte-exact 보존.
- **가이드 문서**: `docs/SCRIPTING_GUIDELINES.md` §6 함수 주석 예시 + 신규 §8 "주석 스타일" 소절 추가.
- **[실측] 재검증 불요**: 순수 주석 변경 → 기능·동작 무영향. 실기 스모크 반복 불필요.
- **⚠ 브랜치 함정(재발 방지)**: 세션 도중 주 워킹트리가 `main` 체크아웃 상태였음(feat 아님) — 병렬 세션/타 worktree 가 전환한 것으로 추정. **대량 편집 전 `git branch --show-current` 확인 필수**. 이번엔 패치 확보→main 트리 원복→feat 복귀→재적용으로 해결(코드 유실 0).
- **main 반영 대기**: 스크립트 주석 변경은 main 공용 설치 스크립트에도 적용되니 `merge-to-main.sh` 로 승격 가능. `docs/SCRIPTING_GUIDELINES.md`·본 핸드오프·`.claude/` = 제외 매니페스트가 자동 처리(dev 전용, main 미반영).

**(2026-06-30 [문서] 세션 — roboflow) — corecode 실행환경 점검 + roboflow 를 demo venv·핀파일에 반영·push(`6ddd68e`, 현 HEAD `1d74fce` 에 포함).**
- **corecode 실행 가능성**: demo venv `~/.cobot2_venv_demo/venv`(system-site-packages, torch 2.11.0+cu128)에서 corecode 의존성 import — `roboflow` 외 **전부 OK**. DSR 계열(`DR_init`/`DSR_ROBOT2`/`dsr_msgs2`)은 venv 패키지가 아니라 **`source ~/cobot_ws/install/setup.bash` 오버레이**로 해결(이 머신 빌드돼 있음). `onrobot`/`RG`/`realsense` 는 `Calibration_Tutorial/` 로컬 모듈(설치 불요). import 가 풀려도 실제 실행엔 HW(로봇/카메라/마이크)+OPENAI key 별도.
- **roboflow 반영**(`6ddd68e`): `scripts/venv-demo/requirements.txt`(`roboflow<2`, numpy<2 위) + `LAB.md` Part A4 설치 절차 + 검증 import. demo venv 에도 실설치·import 검증 PASS(roboflow 1.3.10).
- **⚠ opencv 충돌 함정(재발 방지)**: roboflow 기본 설치가 `opencv-python-headless` 를 끌어와 기존 `opencv-python`(cv2 GUI, 4.9)와 같은 `cv2/` 를 덮어써 깨짐 → **본체는 `--no-deps`**, `typer filetype pi-heif pillow-avif-plugin` 만 일반 설치(opencv 안 끌어옴). numpy 무변경(1.26.4 → ultralytics 안전). LAB.md/requirements.txt 에 주석 명시.
- **typer 버전 주의**: roboflow 는 `typer>=0.12` 요구하나 venv 엔 0.9.0(기존) — `from roboflow import Roboflow`(data_download.ipynb) 용도엔 무관, roboflow **CLI** 쓰면 깨질 수 있음. 클린 재현은 LAB.md 처럼 typer 일반 설치.
- **컨테이너 미반영(의도)**: roboflow 는 demo venv 전용, yolo-detection Dockerfile 엔 없음(컨테이너엔 데이터셋 다운로드 불요). 컨테이너에서 필요해지면 별도 추가 검토.

**(2026-07-01 [문서] 세션 — ROS_DOMAIN_ID 기능 전면 철회, 기본 0 + 학생 수동 삽입) — 커밋·push·main 머지 완료(2026-07-03).**
- **결정 역전**: 직전(2026-06-30)에 만든 prompt 입력 + XDG 파일 영속 + 기본 42 옵션화를 **통째 철회**. 새 방침: `config.sh` 기본값 `0`, 설치는 도메인을 **prompt/주입/파일 영속 안 함**. 학생이 직접 `~/.bashrc` 에 `export ROS_DOMAIN_ID=<n>` 삽입(학습 과제 = 교육 목적 강화). 미설정 시 host·양 컨테이너 모두 0(ROS2 기본) 으로 매칭.
- **⚠ 트레이드오프**: 기본 0 = 공유 LAN 에서 팀 격리 없음(42+prompt 를 뒀던 원래 이유). 여러 조가 같은 네트워크면 서로 토픽이 보임 → 학생이 각자 도메인을 bashrc 에 넣어야 격리. 의도적 교육 트레이드오프.
- **변경 파일(전부 이 세션, uncommitted)**: `config.sh`(파일 읽기 블록 삭제 → `export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"`, `ROS2_JAZZY_TEST_CONFIG_DIR`/`_domain_file` 제거) / `dds-tuning.sh`(`~/.bashrc` managed block 에서 `export ROS_DOMAIN_ID=...` 줄 삭제, RMW+CYCLONEDDS_URI 만 유지) / `setup-app.sh`(`prompt_domain_id` step 삭제 + 진행률 분모 4→3 버그 수정) / `interaction.sh`(`prompt_domain_id()` 함수 통째 삭제) / `containers/docker-compose.yml`(`${ROS_DOMAIN_ID:-42}`→`:-0` ×3) / 문서(README ×3·`.env.example`·`docs/lecture-jazzy/*` ×2). 두 dated 설계문서(`docs/specs|plans/2026-06-30-ros-domain-id-option*`)엔 SUPERSEDED 배너 추가(본문은 역사 보존).
- **정적 검증 완료**: shellcheck 무경고, dangling `prompt_domain_id`/`ros_domain_id`/`ROS2_JAZZY_TEST_CONFIG_DIR` 참조 0, compose 기본값 3곳 전부 0. **[실측] 검증 대기**: `echo $ROS_DOMAIN_ID`(미설정 시 0) + `grep ROS_DOMAIN_ID ~/.bashrc`(없어야 함) + compose config 세 서비스 0.
- **커밋·머지 완료**: feat `6e37f74`(ROS_DOMAIN_ID 반전)+`f37ece3`(handoff) → origin push. main 머지 `01489c6`(`merge-to-main.sh` → 제외경로 제거 → `check-no-claude-on-main` PASS) → origin/main push(`fe04bd2..01489c6`). **README main 충돌 1건 수동 해결** — main 이 타 머신에서 먼저 재구성(`fe04bd2`)돼 `**통합 실행**` 헤딩 vs 우리 도메인 노트가 충돌 → main 간결 헤딩 유지 + 도메인 노트 반영(feat 은 자체 상세 버전 유지). `docs/checklist.xlsx`(user untracked, `docs/` rm 대상)는 백업→복원 sha256 동일 확인.
- **Notion 동기화**(git 아님): "(협동2) Humble→Jazzy 마이그레이션" 페이지를 현 repo 로 전면 갱신 — 17-step 단일 `install.sh` → `install.sh` 10 + `setup-app.sh` 8 분리, `fetch-images`→`:dev-builder` 소스빌드, `ROS_DOMAIN_ID` 42→0. §1-3 `bringup_all.launch.py`(cobot2 앱 실측 흐름)는 README 의 `containers/bringup.sh` 로 덮지 않고 보존.

**(2026-06-29 [실측] 세션 #3 반영) — sudo_prime 커밋·push + `--build` 'object_detection: not found' 경로 검증(레포 정합 확인, 원인=불완전 소스).**
- **sudo_prime 커밋·push 완료**(`5de10ac`, origin 동기): 직전 세션 #2 가 uncommitted 로 남긴(아래 #2 블록의 sudo refactor 노트) 작업 확정. `setup-app.sh` 가 step 시작 전 비번 선인증을 안 해, 첫 routed step 의 sudo 프롬프트가 콘솔 heartbeat 뒤로 숨고 **비번 입력이 끝나기 전 설치가 진행되는 것처럼 보이던 버그** 수정. install.sh 의 `sudo -v`+keepalive 인라인을 `resources/interaction.sh::sudo_prime [prefix]` 로 추출 → install.sh/setup-app.sh 공유(setup-app 은 do_reset 뒤, 첫 step 전 `sudo_prime setup-app` 호출). shellcheck warning+ clean.
- **`--build` 경로 = 레포 코드 정합(버그 아님)**: busybox probe 로 yolo/voice Dockerfile 의 3 leaf COPY(`yolo_container/od_msg`·`yolo_container/object_detection`·`voice_container/voice_processing`) 가 staged context(REPO_ROOT)에서 전부 해석됨 + `.dockerignore` `!cobot_ws` 재포함 동작 확인. 이 [실측] 머신은 소스 완전 → COPY 통과. c721156 staging 수정 자체는 옳다.
- **install 머신의 `object_detection: not found` = 그 머신 빌드 context 에 소스 부재**: od_msg(COPY line 67) 는 found 인데 object_detection(line 68) 만 missing = **부분/불완전 소스**, 또는 그 머신이 c721156 이전 build-all.sh(staging 없음). 레포 경로 문제 아님.
- **build-all.sh 하드닝(⚠ uncommitted — 커밋 미요청)**: 기존 guard 는 `yolo_container`/`voice_container` **부모만** 검사 → 불완전 소스가 통과해 800MB torch 받은 뒤 BuildKit 이 cryptic 하게 죽음(사용자가 본 그 증상). → Dockerfile 이 실제 COPY 하는 **leaf 경로** 3개로 guard 정밀화(`COBOT2_REQUIRED` 배열, Dockerfile COPY 와 동기 유지) + staging 후 context 재검증 + `cp -a`→`cp -aT`(중첩 방지). 이제 불완전 소스는 즉시 `missing: yolo_container/object_detection` 로 fail-fast(torch 다운로드 전). **실패 머신 복구**: `git pull` 후 `setup-app.sh --build` 재실행 → 정확한 누락 경로가 출력되면 그 머신 `~/cobot_ws/src/cobot2` 에 **전체** cobot2 소스 배치(특히 `yolo_container/object_detection`).

**(2026-06-29 [실측] 세션 #2 반영) — corecode 전 트랙 검증 완료(robot/camera/voice/yolo 스모크 + Calibration verify.py 실모션 픽).**
- **corecode 무모션 스모크 PASS(host-side)**: `ros2 launch cobot2_bringup bringup_all.launch.py mode:=real` 로 로봇+카메라 기동 후 **모션 0회**로 스택 배선 검증. 로봇 m0609 `192.168.1.100:12345` 드라이버 연결(Connected to DRCF / Real Robot Mode / DRFL `GL013303` / RT stream / hw activate), 카메라 color **30Hz**·aligned depth **30Hz**·camera_info 1280×720, corecode `realsense.ImgNode` 로 color`(720,1280,3)`·depth`(720,1280)` 실수신, 로봇 `/dsr01/joint_states` readable(home≈0), corecode `onrobot.RG` 그리퍼 reachable(`width=108.9`·status idle). **Calibration 의존(cv2/rclpy/DR_init/cv_bridge/pymodbus/scipy/numpy)은 전부 host 에 있어 컨테이너 불요** — corecode Calibration 은 host 에서 바로 실행. (`mode` 기본=virtual→127.0.0.1, 실로봇엔 `mode:=real` 필수.)
- **YOLO 트랙 PASS**: `yolo:dev` 컨테이너 `--gpus all` → torch `2.11.0+cu128`·cuda True·RTX4060·ultralytics `8.4.64`, `OD_Tutorial/YOLO_SIMPLE/sample.jpg` GPU 추론 동작(person 0.91/dog 0.85/…). train 은 데이터셋 부재로 불가 — 추론 smoke 까지.
- **Voice 트랙 PASS**: `voice:dev` 컨테이너(`--device /dev/snd`) → wakeword `.tflite` 로드(TFLite XNNPACK) + 마이크 **네이티브 48kHz** 캡처(corecode `MicController.rate=48000` 일치)→16k 리샘플→`openwakeword` predict 동작(무음이라 score≈0·rms 1 = 정상). ⚠ 16kHz **직접** 요청은 PortAudio `Invalid sample rate [-9997]` — 네이티브 48k 캡처 후 `scipy.signal.resample` 가 정답(튜토리얼 `wakeup_word.py` 도 동일).
- **✅ verify.py = 인터랙티브 실모션 픽 검증 완료(사용자 "잘 동작함")**: cv2 `"Webcam"` 창에서 **운영자 좌클릭 → 그 점으로 movel→하강(-20)→그리퍼 close→상승(+20)→movej(JReady)→open** 풀 시퀀스가 실로봇에서 정상. **이로써 다년 OPEN 이던 RG gripper pymodbus 3.x 하드웨어 검증(open/close, ADR-014)도 실픽 시퀀스로 실행 확인** — register write 의미 정상(grip-force 정밀 측정은 별개). 기동: bringup(`mode:=real`) + `python3 corecode/Calibration_Tutorial/verify.py`(GUI·host). 클릭=실모션이라 자율 실행은 부적절 → 사용자 구동. 테스트 후 bringup teardown 완료(잔여 `/get_keyword_node`=무관 voice 컨테이너).
- **~~⚠ working tree 미커밋~~ → 세션 #3 에서 커밋·push 완료(`5de10ac`)**: `install.sh`·`resources/interaction.sh`·`setup-app.sh` 의 sudo 키프라이브 `interaction.sh::sudo_prime` 추출·공유 리팩토링. (당시엔 정체 불명 uncommitted 였으나 세션 #3 에서 "비번 입력 전 진행" 버그 수정으로 확정. 위 #3 블록 참조.)
- **직전 pre-compact 커밋(이미 push, HEAD `c721156`)**: README yolo no-compose `docker run` 블록(`c97810e`), fetch-images 주석 정정(컨테이너 단계는 setup-app 소관, `c891a44`), `build-all.sh` 가 `--build` 시 외부화 cobot2 소스를 빌드 context 로 stage(`c721156`).

**(2026-06-29 [실측] 세션 반영) — venv 실습 가이드 push 완료 + voice docker run 이름 충돌 가드.**
- **push 완료**: `feat/application-containers` 15커밋 origin 동기(0/0, HEAD `1ec6166`). 14커밋 = 직전 [문서] 세션이 남겼던 venv pick&place 교육 실습 가이드(`scripts/venv-demo/LAB.md` 499줄 + `docs/plans/2026-06-26-venv-pickplace-demo.md` + `requirements.txt` + README 진입점 + apt `python3.12-venv` + ros2 명령 Jazzy 호환). +1커밋 = 아래 README 가드. secret 스캔 clean(LAB.md `sk-...` = 플레이스홀더), `.env` 미추적.
- **voice docker run "빌드 안 됨" 진단·해결**: `docker run` 은 빌드 단계 무관 — compose dev(`docker-compose.dev.yml`, `container_name: voice-processing`)가 만든 `:dev-builder` 컨테이너가 **정지 상태로 고정 이름 점유** → 직접 `docker run --name voice-processing` 이 `name is already in use` 로 즉시 실패. README 두 `docker run` 블록 앞에 `docker rm -f voice-processing 2>/dev/null || true` 멱등 가드 + 각주에 충돌 원인/prod↔dev 전환 주의 명시(커밋 `1ec6166`).
- **검증**: 잔재 컨테이너 제거 후 사용자 명령 그대로 PASS — `MicRecorderNode initialized` / `wait for client's request...`(`/get_keyword` 대기).
- **docker 재설치 멱등 버그 수정·push**(`211da6f`): 설치 머신에서 `--reset` 후 install.sh 재실행 시 step 3(`a01_docker`)이 `E: Held packages were changed and -y was used without --allow-change-held-packages` 로 실패. docker-ce/docker-ce-cli/containerd.io 가 `apt-mark hold` 인데 repo 새 버전을 `apt-get install -y` 가 업그레이드하려다 막힌 것(hold 목적과 충돌). `docker-install.sh:41` 엔진 install 에 'docker-ce 이미 설치 → skip' 가드 추가(nvidia step 의 already-installed skip 이식). `--allow-change-held-packages` 는 핀 정책 무력화라 미채택. 클린설치 무영향(재설치 경로 전용). **실패 머신 복구**: 그 머신에서 `git pull` 후 `bash install.sh` 재실행(step 3 이제 skip 통과).
- **realsense 기동 크래시 진단·수정·push**(`0ccf5ac`): 별도 [실측] 머신에서 `realsense2_camera_node` 가 `undefined symbol: diagnostic_updater::Updater::Updater(NodeBaseInterface,...,double,uint8)` 로 즉사(exit -6). 원인 = ROS2 apt **snapshot skew**(realsense2_camera 가 설치된 diagnostic_updater 보다 최신, 느슨한 의존이라 apt 가 구 diagnostic_updater 자동 업그레이드 안 함). RealSense SDK/래퍼 문제 아님(그랬으면 librealsense 심볼). `realsense-install.sh::realsense_ros()` 에 realsense 설치 직전 `ros-${ROS_DISTRO}-*` 설치본을 현재 snapshot 으로 `--only-upgrade` 재정합 추가(docker/nvidia 핀 무영향 — glob 밖+held). **실패 머신 복구**: `sudo apt install --only-upgrade -y ros-jazzy-diagnostic-updater`(또는 `ros-jazzy-*` 전체), 혹은 `git pull` 후 realsense ROS 단계 재실행. 참고: 이 머신(정상)은 둘 다 snapshot 20260412.
- **버전 핀 전수조사·보강·push**(`b561ca4`): 무핀 2건 핀 — (a) torch/torchvision(yolo Dockerfile:46 + venv-demo 무핀 → cu128 인덱스 최신 받아 numpy>=2 torch 시 마지막 numpy<2 재핀과 충돌 위험) → 빌드 이미지 실측 `torch==2.11.0`/`torchvision==0.26.0`(매트릭스 일치) exact 핀. (b) pymodbus(venv-demo 무핀, 2.x→3.x 깸 이력 ADR-014) → `pymodbus<4`. **핀=검증버전이라 재빌드 불요.** MINOR/by-design 미수정: librealsense2 SDK apt latest·미held(vendored 디커플), DSR clone branch-not-SHA(fork 소유 완화), base 이미지 rolling tag(Hard Rule #6 충족·digest 미핀), pyaudio/sounddevice/dotenv(안정).
- **머신 상태(세션 끝)**: voice-processing **프로덕션 컨테이너 가동 중**(`:dev` 이미지 = runtime 스테이지, `--restart unless-stopped`, 마이크 점유). 중지는 `docker rm -f voice-processing`. ⚠ 태그 명명 주의 — `:dev`=프로덕션 runtime(ENTRYPOINT 노드 자동실행, build-all.sh 산출), `:dev-builder`=디버그(compose dev, sleep 후 수동 exec).

**(2026-06-26 [실측] 세션 반영) — wakeword 미응답 = 해결·end-to-end 검증 완료.**
근본원인: 컨테이너 마이크 캡처가 ALSA 기본값(plug)→노이즈 큰 **hw:1,6**(48kHz DMIC, 정적에서도 풀스케일 클리핑) 으로 가 confidence 가 0 부근 고정. 해결: 캡처 코드가 ALSA 기본값에 의존하지 않고 **깨끗한 16kHz 네이티브 DMIC(hw:1,7)** 를 직접 연다 — 신규 `voice_processing/audio_device.py::resolve_input_device()`(`VOICE_MIC_DEVICE` env → 16kHz 자동선택 → None), `wakeup_word.py`/`stt.py` 적용. 레포 `asound.conf` default→hw:1,7.
- **e2e 실측 PASS**: get_keyword 노드 + `ros2 service call /get_keyword` → "Hello Rokey"(confidence **0.92**) → STT "해머를 포즈1에 가져다놔" → gpt-4o `hammer / pos1`. 풀 파이프라인 동작.
- **커밋(이 머신, origin push 완료)**: `asound.conf`(hw:1,7 변경), `README.md`(voice/yolo 컨테이너 docker run 직접 기동 추가). + 사용자 `docs/superpowers/specs/2026-06-26-venv-pickplace-demo-design.md`.
- **cobot2 canonical**: `~/Downloads/cobot2.zip` **재생성**(코드+모델, `__pycache__` 제거, fix 3파일 반영; `cobot2.zip.bak`=직전 원본). ⚠ **cobot2 원본 저장소는 이 머신에 없음 → 원본 보유처([문서]/git)에서 3파일(`audio_device.py` 신규·`wakeup_word.py`·`stt.py`) 반영 또는 새 zip 으로 교체 필요(미완)**.
- **컨테이너 상태**: 디버깅용 `voice-processing` 제거. `yolo-detection` 은 가동 중(사용자).

**(2026-06-25 [문서] 세션 반영) — 교육생 실습 runbook 작성 ⇒ 내일 [실측] 실기**: `docs/TRAINEE_PRACTICE_PATH.md` 신규(실행형 — host venv → docker 4단계 실습 경로). **다음 [실측] 세션은 이 문서를 먼저 열고 단계별 환경설정**. 요지:
- **4단계**: ① Calibration(host, 하드웨어) → `T_gripper2camera.npy` ② YOLO 학습(host venv, GPU) → `best.pt` ③ 모델→yolo 컨테이너 객체인식 ④ voice 컨테이너에 corecode 스크립트 주입(mic_test/wakeup_word/STT/keyword_extraction).
- **확정 결정**: Step 2 = host 학습 dev venv(A안), Python **3.12 는 `uv venv --python 3.12`** 로 공급(system python 무변경). 운영 추론만 컨테이너.
- **⚠ Step 4 선행 수정**: `corecode/VoiceProcessing/keyword_extraction.py:5` `langchain.prompts`→`langchain_core.prompts` (langchain<2 에서 제거됨, host/컨테이너 공통 — import smoke FAIL 실측). 미수정.
- **이번 세션 smoke 실측**(격리 uv venv, host apt 무변경): cobot2 application-shell 의존성 스택 numpy<2 공존 PASS(numpy 2.5.0→1.26.4 재핀 재현), corecode `.py` syntax 전부 PASS, `onrobot`/`ultralytics` import PASS, `keyword_extraction` FAIL(위), voice audio = **PortAudio(system lib) 경계** 발견(host venv 못 넘음 → 컨테이너가 apt+`/dev/snd`로 해결 = 학습 핵심). 배경 비교문서 `docs/CONTAINER_VS_HOST.md` 동반 신규.
- **상태**: 두 신규 문서 + 본 핸드오프 갱신 **uncommitted**(이 [문서] 머신). 실기 노트북에서 내일 열려면 **commit+push 필요**(사용자 확인 대기).

**(2026-06-23 [실측] 세션 반영)** — `feat/application-containers`(`47adcaa`)·`main`(`6d38a1a`) 둘 다 origin 동기. 이번 세션 **main 승격 완료**(`scripts/merge-to-main.sh` → main `6d38a1a`, push): ① **CycloneDDS 경로 단일화**(config.sh — stale `~/.bashrc` URI 가 compose 마운트와 갈라져 host↔container discovery 가 조용히 깨지던 버그 → `CYCLONEDDS_XML` 단일 소스 + URI 강제 파생), ② **virtual 안전 게이트**(bringup_all — `mode:=virtual` 이 host 인자(실기 IP)를 드라이버에 그대로 넘겨 켜져있는 실 로봇에 붙던 버그 → `real 일 때만 실기 IP` 화이트리스트 + `choices=[virtual,real]`), ③ **voice `.env` 빌드 footgun 제거**(setup.py `glob('resource/.env')`), ④ **real/virtual README 분리** + dsr_bringup 디버깅. **머신 상태(세션 끝)**: voice/yolo **dev** 컨테이너 + realsense(host launch PID 18298) 가동, cyclonedds 신경로(`~/.config/cyclonedds/cyclonedds.xml`) 렌더·`~/.bashrc` 갱신 완료, host↔container discovery 정상(`/get_keyword`·`/get_3d_position` introspect OK).

**즉시 OPEN (다음 [실측]):**
- ✅ **wakeword 미응답 = 해결**(2026-06-26, 위 최신 노트 참조) — 원인은 임계/모델/포맷이 아니라 **노이즈 마이크 장치(hw:1,6) 캡처**였음. hw:1,7 직접 캡처로 e2e PASS. 재조사 불필요.
- **virtual 로봇 pick&place e2e 미완** — 카메라+컨테이너+discovery 라이브까지 됐으나 발화로 끝까지 미실행. 그리퍼(192.168.1.1)·로봇(192.168.1.100) 둘 다 도달가능. virtual 기동: `ros2 launch cobot2_bringup bringup_all.launch.py mode:=virtual camera:=false containers:=false`(카메라/컨테이너 이미 가동중) + `ros2 run robot_control robot_control` + 발화.
- **docker `--reset` 재설치 에러 = 폐기**(로그상 원인 특정 불가, docker-install.sh 정적 멱등 확인). 재발 시 정확한 실패 명령/에러줄 캡처 필요.
- **robot_control `--test` 모드 = 폐기(전량 원복)** — real/virtual 은 bringup `mode:=` 로만. **재추가 금지**.

**(2026-06-22 [실측] 세션 반영)** — `feat/application-containers` origin 동기(HEAD `b1887d0`). 이번 [실측] 세션: ① voice 컨테이너 dev 빌드 실패(`scipy<2` 가 1.18 로 drift → 런타임 numpy>=2.0 요구·`np.long` → `numpy<2` 재핀과 충돌) **수정·재빌드 PASS**(`scipy<1.18`), ② 컨테이너 이름 고정 → `docker exec -it voice-processing`/`yolo-detection` 직접 가능(**단 재생성 후 적용**: `docker compose -f …yml -f …dev.yml down && up -d`, 현재 떠있는 건 옛 이름 `containers-<svc>-1`). 워크스페이스는 이 머신에 신 레이아웃(`cobot1`/`cobot2`/{yolo,voice}_container) 적용 상태이고 yolo·voice dev 이미지 재빌드 성공(ADR-025 rename 후 Dockerfile COPY 신 경로 resolve 확인). **남은 [실측] 미검증: host `~/cobot_ws` colcon 풀 재빌드 + robot_control 실행 순서 실동작**(아래 즉시 항목과 동일). 상세 = Last updated 2026-06-22.

**(2026-06-17 [문서] 세션 반영)** — `feat/application-containers` 가 **워크스페이스 통합**(`4c36cc5`) + **DSR clone fork 핀**(`d9d8df0`)으로 진행, origin 동기(0/0, HEAD `d9d8df0`). **ROS2 워크스페이스 레이아웃이 크게 바뀜** — 아래 ⚠ 필독. 직전 [실측] 머신은 origin 과 동기였으나 이 변경으로 **재pull + 재빌드 필요**.

⚠ **[실측/fleet] 워크스페이스 grouping 디렉토리 rename (2026-06-21, ADR-025)** — `cobot_ws/src` 의 grouping·서브디렉토리 4개 rename(**아래 ADR-024 노트의 옛 이름을 대체**): `cobot1_ws`→`cobot1`, `cobot2_ws`→`cobot2`, `cobot2/yolo_ws`→`cobot2/yolo_container`, `cobot2/voice_ws`→`cobot2/voice_container`. 순수 디렉토리 rename(패키지명·colcon 빌드 무영향). 신규 진입점 `reinstall-workspace.sh`(repo 루트, 워크스페이스만 재설치) 추가. 다음 행동:
- **[실측] 검증 대기**: `bash reinstall-workspace.sh` 로 `~/cobot_ws` 재미러+빌드(소스 재미러가 delete-then-copy 라 옛 이름 디렉토리 자동 정리) → `colcon build` 성공 + `ros2 launch cobot2_bringup bringup_all.launch.py` resolve 확인. 컨테이너는 Dockerfile `COPY` 경로 변경분 **재빌드** 필요(`containers/build-all.sh` 또는 dev compose build).
- 이 머신([문서])은 ~/cobot_ws·ROS2 부재라 정적 검증(shellcheck + grep 감사)만 완료 + **커밋·push 완료**(아래 Last updated 2026-06-21, HEAD `9475497`) — 실빌드는 fleet 머신 몫.
- **[실측] 검증 시 README 의 "robot_control 전체 실행 순서" 단계별 따라가면 됨**(dev 모드 컨테이너 exec → 노드 수동 실행 → robot_control). `reinstall-workspace.sh` 로 ~/cobot_ws 빌드가 선행.

⚠ **[실측/fleet] 워크스페이스 재배치 (2026-06-17, ADR-024)** — 런타임 ws `~/cobot2_ws` → **`~/cobot_ws`** (통합 `src/` grouped 레이아웃: `cobot1_ws`+`cobot2_ws` → **현재는 ADR-025 로 `cobot1`+`cobot2`**). 다음 행동:
- `git pull` 후 `bash resources/dsr-project-install.sh` 재실행 → repo grouped src 미러 + doosan-robot2 clone 으로 `~/cobot_ws` 생성, 이어 `colcon build`(host 는 `object_detection`/`voice_processing` `--packages-skip`, `pick_and_place_*` COLCON_IGNORE).
- 기존 `~/cobot2_ws`·`~/yolo_ws`·`~/voice_ws` 는 **고아로 남음**(installer 자동삭제 안 함 — 파괴적). 수동 `rm -rf ~/cobot2_ws ~/yolo_ws ~/voice_ws` 권장.
- 설치 step **17→16** (dev-ws 생성 step 폐기 — 통합 ws 가 dev bind-mount 서브디렉토리 `cobot2_ws/{yolo_ws,voice_ws}` 를 포함, network 고정IP 가 step16).
- DSR clone 소스 = **`ROKEY-SPARK/doosan-robot2_jazzy`** fork default 브랜치 main(= 검증 jazzy 스냅샷 816ecb5d). upstream drift/force-push/삭제 위험 차단.

**즉시(다음 세션) — 실물 로봇 검증 예정(2026-06-17~, 미완):**
- **[실측] robot_control Ctrl+C 셧다운 패치 실기 검증** — `dd9c660` 코드 push 됨. 로봇 연결 + `git pull` 후 **통합 `~/cobot_ws` 재빌드**(레이아웃 바뀜 — `bash resources/dsr-project-install.sh` 로 미러 후 `colcon build`; 빠른 반복은 `--packages-select robot_control`) → Ctrl+C 깔끔 종료 실측 → OK 면 `scripts/merge-to-main.sh feat/application-containers` 로 main 승격.
- **[실측] Calibration RG gripper pymodbus 3.x 하드웨어 검증** — open/close/move register write 의미는 실 RG 로만 검증(ADR-014, 검증 전 실로봇 운용 금지).
- **[실측] yolo 실물 도구 검출** — 컨테이너 dev 모드·viz·`/get_3d_position` 파이프라인은 **2026-06-16 검증 완료**(아래 Last updated). 남은 건 학습 도구(hammer/screwdriver/wrench)를 실제 비춰 박스/좌표 확인(이번엔 도구 부재로 미검출 `[0,0,0]` 까지만).
- **[기설치 머신] dds-tuning.sh 재실행** — stale cyclonedds.xml(`lo` 없는 옛 렌더)이 로봇망 NIC down 시 노드 전멸. `bash resources/dds-tuning.sh`(이 머신엔 이번 적용). 클린설치 머신은 자동이라 무관.

**(2026-06-10 의 "YOLO 재빌드 + 드라이브 재업로드" 지시는 2026-06-11 완료 — 아래 Last updated ① 참조. 더 이상 선행 작업 아님.)**

현재 최우선 = Next Actions #1 = **다른 노트북(fleet)에서 전체 클린설치 검증.** 새 yolo 이미지(KeyError 수정본)가 드라이브에 올라가 있어 그 머신 step15 fetch 가 수정본을 받는다. 드라이브 도달성/크기 검증은 [문서] 머신에서 통과(무인증 curl, Content-Length 일치) — 단 동일 네트워크라 타 네트워크/무계정 실측은 fleet 머신에서 최종 확인.

**연계(후속3 리팩토링)**: `refactor/installer-shell`(셸 리팩토링)은 `feat/application-containers` 에 머지 완료(`68f452d`). fleet 클린설치를 그 브랜치로 돌리면 리팩토링의 실 머신 검증(키 다운로드·`apt update` 인증·reboot 경계)이 함께 끝난다. 리팩토링은 behavior-preserving 정적 검증 통과 — Last updated 후속3 참조.

**신규(2026-06-15 후속5) [실측] 검증 대기**: ① Calibration `onrobot.py` 가 pymodbus 3.x 로 바뀜 → **RG gripper open/close/move 하드웨어 재검증 전 실로봇 운용 금지**(register write 의미는 import smoke 로 검증 불가, ADR-014). ② 컨테이너 dev 모드 — 이제 install.sh step16(`container_dev_ws`)이 `~/yolo_ws`·`~/voice_ws` 를 클린설치 시 자동 생성(후속6, 기설치 머신은 `bash containers/dev-ws-setup.sh`). **[실측] 검증: voice PASS(2026-06-16) — 단 그 과정에 dev-mode 결함 2건(dev `colcon build` `--merge-install` 누락 → baked 코드 silent fallback / builder 이미지 cyclonedds RMW 누락 → 노드 기동 불가) 발견·수정·push(`1f59df9`/`be74716`). yolo 도 2026-06-16 재빌드·검증 완료(RealSense D435i 연결·`/get_3d_position` round-trip·viz 화면).** **(2026-06-17 경로 변경: `~/yolo_ws`·`~/voice_ws` 별도 ws + `dev-ws-setup.sh` + install.sh dev-ws step **폐기** — dev bind-mount 는 이제 통합 `~/cobot_ws/src/cobot2_ws/{yolo_ws,voice_ws}` 서브디렉토리. 위 dev-mode 검증 결과 자체는 유효, 경로만 바뀜.)**

## Last updated
2026-07-24 ([문서]→[실측] 원격 진단·수정) — **[실측 원격]** RViz pointcloud flicker 3원인 해결(M0609 4커밋 `2dec7d2`~`6239903`, main+jazzy push, 원격 pull·재빌드·실기 검증): stream_filter 2 / IMU off / jsp rate 100 + rsp publish_frequency 100(RViz 동일 lookup probe 로 27%→0% 실측). **[문서]** ros2_jazzy_test 카메라 명령 문서 4곳 stream_filter 반영 커밋 `59ebe24` push(feat 브랜치). Notion 2페이지 카메라 블록 갱신(stream_filter+IMU off). corecode.zip 재패키징(DSR 서비스 경로 4곳 `dsr_controller2/system` + `__dsr__id` 오탈자, 31파일 정합·py_compile 15·ipynb JSON 3 검증). 실측 머신 타 장소 이동(172.18.0.169, 직접 SSH 불가). 미결: 현장 ~/corecode 패치 확인·GID 992·modbus import 판별·레포 문서 IMU 인자.
2026-07-10 ([문서] 디커플링+잔재정리) — **[문서]** 인스톨러 디커플링 커밋 `966a78b` push(ADR-028 OPENAI 키 셋업 폐기·.env→`~/.config/cobot2/.env`, ADR-029 corecode git 제거→`~/corecode` 수동배치+`corecode-verify.sh` 스텁). `corecode.zip` 재생성(배포 산출물, untracked). ADR-027 잔재 문서 정리(uncommitted): `TRAINEE_PRACTICE_PATH.md` Step 4 host 재작성 + untracked lecture WIP 3파일(LECTURE_MIGRATION·lecture-jazzy ×2). 불변 히스토리(ADR/roadmap/specs)·branch 대비문서(CONTAINER_VS_HOST/COMPATIBILITY §shell)는 의도적 유지. [실측] 검증 대기 = .env/corecode/host-voice 클린설치 e2e. 커밋은 사용자 미요청이라 미실행.
2026-07-08 ([문서] 주석 리팩토링) — **[문서]** 설치 셸 스크립트 25개 주석 전면 리팩토링(영어→한글 + Google Shell Style `####` 함수 블록 + 초심자 난이도 + 개조식 종결) + `docs/SCRIPTING_GUIDELINES.md` §6/§8 갱신. **코드 0 변경**(comment-only, `git show HEAD` 대비 code-identical), `bash -n`·`shellcheck -x` 전 파일 PASS. 커밋 `72d23bb` → origin/feat push(tip `d760657` = 사용자 메모리 커밋 동승). 세션 중 주 트리가 `main` 체크아웃이던 것을 feat 로 복귀시켜 안착. main 미머지(`merge-to-main.sh` 대기). 교훈 = 대량 편집 전 `git branch --show-current` 확인.
2026-06-30 ([문서] roboflow) — **[문서]** corecode 실행환경 점검 + roboflow 를 venv-demo 핀(`requirements.txt` `roboflow<2` + `LAB.md` Part A4)·demo venv 에 반영·push(`6ddd68e`, 현 HEAD `1d74fce`). 기본 설치가 `opencv-python-headless` 를 끌어와 기존 cv2 와 충돌 → 본체 `--no-deps` + typer/filetype/pi-heif/pillow-avif-plugin 별도(numpy 무변경, 1.26.4 유지). corecode 의존성 demo venv 에서 roboflow 외 전부 import OK, DSR 계열은 `source ~/cobot_ws/install/setup.bash` 오버레이. roboflow=demo venv 전용(컨테이너 미반영, 의도). 세션 중 ROS_DOMAIN_ID 작업이 동시 진행되어 같은 브랜치 SHA 가 재배치됨(conflict 0).

2026-06-30 ([문서]) — **[문서]** ROS_DOMAIN_ID 설치 시 대화형 입력 옵션화(Subagent-Driven: 5 task + fix 2 + opus whole-branch review = Ready to merge). `feat/application-containers` HEAD `1d74fce` origin 동기. brainstorm→spec(`docs/specs/2026-06-30-ros-domain-id-option-design.md`)→plan(`docs/plans/2026-06-30-ros-domain-id-option.md`)→구현→리뷰→push 풀 사이클. 단일 소스: `config.sh` 가 `~/.config/ros2_jazzy_test/ros_domain_id`(XDG) 를 디폴트로 읽음(env>파일>42), `prompt_domain_id`(interaction.sh) 가 write(0-232 검증), `dds-tuning.sh` 가 `~/.bashrc` managed block 에 export, compose 는 무변경(export env 수신). end-to-end 체인을 전 소비처(activate/dds-tuning/bringup/setup-app/build-all/fetch-images)까지 추적해 갈라짐 없음 확인. read-time 검증 = defer(사용자 결정). **[실측] e2e(install.sh 도메인 입력 → bashrc/compose 일치 → --reset 보존)는 reboot 동반이라 미실행** — 상단 "다음 세션" 2026-06-30 블록. 세션 중 사용자가 다른 터미널에서 roboflow 커밋+rebase+push → task SHA 변경(conflict 0).

2026-06-29 ([실측] #2) — **[실측]** corecode 전 트랙 스모크 검증(상세 = 상단 "다음 세션" 블록). 무모션: 로봇 m0609 실연결+카메라 30Hz+그리퍼 readable(모션 0회), `realsense.ImgNode`/`onrobot.RG` 튜토리얼 코드 경로 실수신. 컨테이너: YOLO GPU 추론(sample.jpg)·Voice wakeword+mic 48kHz. verify.py = 인터랙티브 실모션이라 사용자 클릭 구동(hand-off). 핸드오프만 커밋 — 무관한 working-tree 수정 3건(`install.sh`/`interaction.sh`/`setup-app.sh`, sudo_prime 리팩토링)은 사용자 측이라 미터치. 코드 변경 없음(스모크는 임시 스크립트로 수행 후 제거), HEAD `c721156` 유지.

2026-06-29 ([실측]) — **[실측]** venv 실습 가이드 push + voice docker run 이름 충돌 가드 + docker 재설치 멱등 수정 + realsense ROS snapshot 정합 + 버전 핀 보강. `feat/application-containers` origin 동기(HEAD `b561ca4`).
① **실습 가이드 push** — 직전 [문서] 세션이 남긴 미푸시 14커밋(venv pick&place 교육 — `scripts/venv-demo/LAB.md`+계획문서+`requirements.txt`+README 진입점+`python3.12-venv` apt 의존성+ros2 명령 Jazzy 호환+ledger scratch gitignore)을 origin 반영. push 전 secret 스캔 clean(LAB.md `sk-...` 2건 = 플레이스홀더), `.env` 미추적 확인.
② **voice docker run 이름 충돌**(`1ec6166`) — 사용자 보고 "compose 없이 직접 docker run 했더니 안 됨"의 정체 = compose dev 가 만든 `voice-processing`(`:dev-builder`, Exited 255) 정지 컨테이너가 고정 이름을 점유 → 직접 `docker run --name voice-processing` 이 `Conflict. The container name "/voice-processing" is already in use` 로 즉시 실패(빌드 단계와 무관). README 의 prod/dev 두 `docker run` 블록 앞에 `docker rm -f voice-processing 2>/dev/null || true` 선제거 가드 추가 + 각주에 충돌 원인 명시. README 는 같은 고정 이름을 4가지 기동 방식 전부에서 써서 방식 전환 시 항상 충돌하던 구조적 footgun.
③ **docker 재설치 멱등 버그**(`211da6f`) — 설치 머신에서 `--reset` 후 install.sh 재실행 시 step 3(`a01_docker`)이 `E: Held packages were changed and -y was used without --allow-change-held-packages` 로 실패. docker-ce/docker-ce-cli/containerd.io 가 `apt-mark hold` 상태인데 repo 새 버전을 `apt-get install -y` 가 업그레이드하려다 막힌 것 — hold 의 목적(업그레이드 차단)과 정면 충돌. `docker-install.sh:41` 엔진 install 에 'docker-ce 이미 설치 → skip' 가드 추가(nvidia step 의 already-installed skip 패턴 이식, `shellcheck -x` clean). `--allow-change-held-packages` 는 매 재실행 docker 업그레이드라 핀 정책 무력화 → 미채택. 클린설치(docker 부재)는 무영향, **재설치 경로 전용**. 복구 = 실패 머신에서 `git pull`+`install.sh` 재실행.
④ **realsense 기동 크래시 = ROS apt snapshot skew**(`0ccf5ac`) — 별도 [실측] 머신 `realsense2_camera_node` 가 `undefined symbol: diagnostic_updater::Updater::Updater(...,double,uint8)`(새 node-interfaces ctor)로 dlopen 실패(exit -6). realsense2_camera 가 설치된 diagnostic_updater 보다 최신 snapshot 인데 ROS2 바이너리는 느슨한 inter-package 의존+SONAME 미증가라 apt 가 구 diagnostic_updater 를 자동 업그레이드 안 해 ABI 가 깨짐. `/opt/ros/jazzy` apt 패키지끼리 skew(SDK·overlay 무관). `realsense_ros()` 에 설치 직전 `ros-${ROS_DISTRO}-*` 설치본을 현재 snapshot `--only-upgrade` 재정합 추가 — 전역 apt upgrade(held drift)는 피하고 ROS 네임스페이스로만 스코프. `shellcheck -x` clean, 이 머신 dpkg-query 453개 추출 검증. 구조적 배경: `ros2-packages.sh:20` 이 의도적으로 `apt upgrade` 제거(pin-drift 방지)라 ROS snapshot 정합 단계가 부재했음.
⑤ **버전 핀 전수조사 + 무핀 2건 핀**(`b561ca4`) — COMPATIBILITY.md 가 버전을 기록해두고 빌드가 강제 안 하던 Hard Rule #8 틈. (a) **torch/torchvision** 이 yolo Dockerfile:46 + venv-demo(`requirements.txt`/`LAB.md`)에서 무핀(`torch torchvision`)이라 cu128 인덱스 최신을 받음 → numpy>=2 요구 torch 가 뜨면 마지막 numpy<2 재핀과 충돌(과거 scipy<1.18 사건과 동일 클래스). 빌드 이미지 실측 `torch==2.11.0+cu128`/`torchvision==0.26.0+cu128`(매트릭스 135-136 일치)으로 exact 핀. (b) **pymodbus** venv-demo 무핀 → `pymodbus<4`(2.x→3.x API 깸이 그리퍼 onrobot.py 를 물었던 이력, ADR-014). 핀=검증버전이라 재빌드 불요. **MINOR/by-design 미수정**(트레이드오프 有): librealsense2 SDK apt latest·미held(ROS 래퍼가 vendored lib 써서 디커플), DSR clone branch-not-SHA(ROKEY-SPARK fork 소유로 완화), base 이미지 `ros:jazzy-ros-base-noble`/`ubuntu:24.04` rolling tag(Hard Rule #6 충족·digest 미핀), pyaudio/sounddevice/python-dotenv(API 안정).
**검증**: 잔재 제거 후 사용자 명령 그대로 재실행 PASS(`MicRecorderNode initialized`·`/get_keyword` 대기). voice 프로덕션 컨테이너(`:dev`=runtime 이미지) 가동 상태로 종료. 태그 명명 — `:dev`=프로덕션 runtime / `:dev-builder`=디버그 builder 확인. `refactor/installer-shell` 은 ahead 1(핸드오프 갱신 커밋만, stale).

2026-06-23 ([실측]) — **[실측]** voice→yolo 통신 진단 + DDS/안전 버그 수정 + main 승격. `feat`(`47adcaa`)·`main`(`6d38a1a`) origin 동기.
① **진단** — voice(`get_keyword`)·yolo(`object_detection`)는 서로 직접 통신 안 함: 둘 다 수동 service 서버, host `robot_control` 이 client 로 orchestrate. "voice 결과가 yolo 로 안 감" = robot_control 미기동 + DDS discovery 깨짐(아래 ②).
② **CycloneDDS 경로 단일화**(config.sh) — `CYCLONEDDS_XML` 단일 소스 export + `CYCLONEDDS_URI=file://$XML` 강제 파생. 기존 `:-` 가 stale `~/.bashrc` URI(구 `~/.ros2_jazzy_test/` 경로)를 유지 → compose 는 `~/.config/cyclonedds/` 마운트 → host/container 가 **다른 파일** → discovery silent fail. **머신 remediation**: bogus dir 제거(root 소유 — 사용자 `! sudo rm`) + `dds-tuning.sh` 재실행(신경로 렌더+`~/.bashrc` 갱신) + 컨테이너 재기동 → discovery 복구 확인.
③ **virtual 안전 게이트**(bringup_all) — `dsr_hardware2.cpp:177` 가 mode 무관하게 받은 host 로 `open_connection`(mode 분기는 전부 연결 이후). bringup_all 이 host 기본=실기 IP(192.168.1.100)를 virtual 에도 넘겨 `mode:=virtual` 이 켜져있는 실 로봇 접속. → `robot_host = host if mode=='real' else '127.0.0.1'`(fail-safe — real 만 실기, 그 외 전부 loopback) + `DeclareLaunchArgument mode choices=[virtual,real]`. launch-context resolve 로 virtual/Virtual/공백/오타/빈값 전부 loopback 확인.
④ **voice .env footgun**(pick_and_place_voice/setup.py) — `glob.glob('resource/.env')` 줄 제거. `.env` 깨진 링크 시 colcon `can't copy resource/.env` 실패하던 원인. 이 패키지는 COLCON_IGNORE 라 host build 영향은 본래 0(근본 줄 제거).
⑤ **README** — real/virtual 실행 분리 + dsr_bringup 컴포넌트 디버깅 경로(virtual 은 host 인자 생략 경고 — raw launch 엔 안전 게이트 없음). 컨테이너 옵션은 bringup bash 주석 인라인.
⑥ **robot_control `--test` 원복** — perception 검증용 `--test`/`--with-motion`/`NullGripper` 추가했다가 사용자 결정으로 **전량 HEAD 원복**(net diff 0). real/virtual 은 bringup `mode:=` 로만.
⑦ **코드리뷰(Workflow, 다차원+adversarial)** — virtual 게이트 fail-dangerous(`mode=='virtual' else host` → 오타/대문자가 실기 IP) **IMPORTANT** 지적 → ③ 강화로 반영(머지 전 수정).
⑧ **main 승격**(`scripts/merge-to-main.sh feat/application-containers` → main `6d38a1a`, push) — ②③④⑤ 전파. 충돌 2건(`.claude/memory/session-handoff`·`.main-keep-ours` modify/delete) 스크립트 자동 해소, README auto-merge. 가드: dev 전용 경로(CLAUDE.md/.claude/docs/scripts/backup) main 부재, 작업4파일(config.sh/bringup_all/setup.py/README) **main==feat**, secret 0·AI attribution 0.
**검증**: shellcheck(config.sh) / py_compile(bringup_all) / launch-context resolve(게이트 fail-safe + choices reject) / setup.py AST / 머지 가드. **[실측] 미완(상단 OPEN)**: wakeword 감지·virtual pick&place e2e.

2026-06-22 ([실측]) — **[실측]** origin 동기화 + voice 컨테이너 dev 빌드 실패 수정 + 컨테이너 이름 고정. 전부 `feat/application-containers` push(HEAD `b1887d0`, origin 동기 — 원격 [문서] README 2커밋 `542a4aa`/`78bf46a` 위로 rebase, README 충돌은 원격 새 구조 채택 + 테스트 줄 재배치로 해소) + **main 머지 승격 + README 단일소스 전환**(③④):
① **voice 컨테이너 빌드 실패 수정**(`0d6cf84`) — `scipy<2` 핀이 1.18.0 으로 drift. scipy 1.18+ 은 런타임 numpy>=2.0 요구 + `np.long`(numpy 1.x 없는 alias) 사용 → 마지막 `numpy<2` 재핀과 충돌 → import 검증서 `AttributeError: module 'numpy' has no attribute 'long'` 로 dev build 실패. 검증된 1.17.1 로 상한(`scipy<1.18`) + COMPATIBILITY.md voice 행 동기화. **재빌드·이미지 내부 실측 PASS: numpy 1.26.4 / scipy 1.17.1 / openwakeword import OK.** application-shell 변종(COMPATIBILITY.md:180)은 `host-python-deps.sh` 이 브랜치 부재라 핀 미수정 — ⚠ Notes 로 동일 drift 위험만 명시(그 브랜치 차기 작업).
② **컨테이너 이름 고정**(`b1887d0`) — `docker-compose.yml` yolo-detection/voice-processing 에 `container_name` 지정 → dev override 상속 → `docker exec -it voice-processing`/`yolo-detection` 짧은 이름 동작(미설정 시 `containers-<svc>-1`). 트레이드오프: 같은 데몬 prod/dev 동시 기동·scale 불가(단일 인스턴스 전제). README voice 블록에 단독 테스트용 서비스 호출 한 줄 추가(`docker exec -it voice-processing bash -ic 'ros2 service call /get_keyword …'` — `docker exec` 는 entrypoint 우회라 `bash -ic` 로 마운트 `/root/.bashrc` source 필요, `bash -c` 단독은 ros2 not found). 참고: `docker compose` 작업의 `-f` 반복은 `COMPOSE_FILE`(콜론구분) env 로 생략 가능.
③ **main 머지 승격**(`scripts/merge-to-main.sh feat/application-containers` → main `3064b3c`, push) — feat 누적분(워크스페이스 rename 전체 + Phase 4 컨테이너 + 위 ①②)을 main 으로 승격. 충돌 4건(`.claude/`·`docs/` modify-delete + README content)은 스크립트가 전부 자동 해소(제외경로 재삭제 + README keep-ours). 검증: dev 전용 경로(CLAUDE.md/.claude/docs/scripts/backup/tasks/containers-template) main 트리 부재, scipy·container_name 코드 반영, 워크스페이스 신경로 존재·구경로 부재. ⚠ **main 이 이제 robot_control Ctrl+C 패치(`dd9c660`)를 포함** — 이 패치는 여전히 [실측] 실기 미검증이다(merge 가 실기검증보다 먼저 일어남 — 사용자 결정). 즉 "실기 OK 후 main 승격" 종전 게이트는 이번에 우회됨, 검증은 사후 과제.
④ **README 단일소스 전환** — README.md 를 `.main-keep-ours` 에서 **제거**(`2289c42`). 이제 머지 시 main 이 자기 README 를 keep 하지 않고 **dev(feat) README 가 main 으로 전파**된다. feat README 에 `# ROS2_Jazzy_Test` H1 타이틀 추가(`f227ec9`) — 종전 main 만 갖던 타이틀 보존 + main==feat 내용 동일화(향후 머지 무충돌 조건). main README 를 feat 버전으로 동기화(main `94b220d`, push) — `~/cobot_ws` 경로·`reinstall-workspace`·컨테이너 디버깅 안내 최신화, stale `cobot2_ws` 참조 0. ⚠ **앞으로 README 는 feat(dev)에서만 수정** — main 직접 편집 금지(분기 시 머지 충돌 재발). 종전엔 main README 가 직접 관리(`164dea1`/`d431d31`/`c04e688` = main 직접 커밋)됐는데 그 흐름 폐지. `.main-keep-ours` 는 현재 목록 비어있음(파일은 유지 — 추후 keep-ours 대상 생기면 재등록).
**검증**: voice 재빌드 + 이미지 내부 버전 실측, `docker compose config`(dev/prod) 통과, code-reviewer(DONE_WITH_CONCERNS — 유효 지적 반영·무효는 entrypoint 우회 근거로 반려) + verification(DONE), rebase 후 선형 히스토리·충돌마커 0·secret 0·AI attribution 0. **[실측] 미확인(이번 세션 범위 밖)**: host `~/cobot_ws` colcon 풀 재빌드, robot_control 실행 순서 실동작, 컨테이너 재생성(`down`/`up`) 후 새 이름 적용.

2026-06-21 ([문서]) — **[문서]** cyclonedds 경로 XDG 이동 + 워크스페이스 디렉토리 rename + 워크스페이스 전용 재설치 스크립트 + README 컨테이너 실행법 재정비. 전부 `feat/application-containers` push 완료(HEAD `9475497`, origin 0/0, 4커밋):
① **cyclonedds.xml XDG 경로 이동**(`f06c676`) — 설치 상태 디렉토리(`~/.ros2_jazzy_test`)에서 런타임 설정 위치(`~/.config/cyclonedds`)로 분리. `config.sh::CYCLONEDDS_XML` 기본값·두 compose mount fallback·README/viz 문서 경로 동반. 설치 부기 디렉토리를 지워도 DDS 설정 보존. **[기설치 머신] `dds-tuning.sh` 재실행 시 새 경로 렌더 + `~/.bashrc` managed block 자동 재작성** — 옛 `~/.ros2_jazzy_test/cyclonedds.xml` 은 orphan(무해).
② **워크스페이스 grouping 디렉토리 rename**(`88e3ad8`, ADR-025) — `cobot1_ws`→`cobot1`, `cobot2_ws`→`cobot2`, `cobot2/yolo_ws`→`cobot2/yolo_container`, `cobot2/voice_ws`→`cobot2/voice_container`. git 이 105파일 rename 추적, **패키지명·colcon 빌드 무영향**(순수 디렉토리). `WS_GROUPS`·`config.sh::YOLO_WS/VOICE_WS`·두 Dockerfile `COPY`·dev compose fallback·`.dockerignore`·문서 동반. ADR-024 의 `_ws` 접미사 정리 Reopen 조건 해소.
③ **`reinstall-workspace.sh` 추가**(`e66194a`) — 전체 `install.sh` 없이 `~/cobot_ws` 만 재빌드. 기본 증분(소스 재미러 + colcon 증분), `--clean` 으로 doosan-robot2 재클론 + build/install/log 삭제 후 풀 빌드(삭제 전 confirm·`--yes`). 기존 `dsr-project-install.sh`+`colcon-build.sh` 위임 호출.
④ **README 컨테이너 실행법 재정비**(`9475497`, 사용자 요청) — yolo/voice 두 컨테이너를 **dev 모드**(`docker-compose.dev.yml`)로 띄워 `docker exec` 진입 후 워크스페이스에서 노드 직접 실행(`ros2 run object_detection object_detection` / `ros2 run voice_processing get_keyword`)하는 방법을 개별 정리. **robot_control 전체 실행 순서**(DSR 드라이버→RealSense→yolo→voice→robot_control 단계별 + 통합 launch 한 줄 대안) 추가. `reinstall-workspace.sh` 사용법 추가. 상세 로그 경로 표기 `~/.ros2_jazzy_test/install.log`→레포 루트 `install_log` 정정.
**검증**: shellcheck pass(`reinstall-workspace.sh` 포함), `--help`/unknown-arg exit code, git 105 rename 추적, Dockerfile `COPY` 소스 디스크 존재, compose YAML 유효, 기능영역 rename 토큰 0, secret 0·AI attribution 0. **정적만** — ⚠ `~/cobot_ws` 실 재빌드·컨테이너 dev mount·robot_control 실행 순서 실동작은 **[실측] 미검증**(상단 ⚠ 블록 = fleet 머신 몫). Notion 마이그레이션 페이지 §2/§3/§4-1 도 새 이름 동기화(git 무관).

2026-06-17 ([문서]) — **[문서]** 원격 동기화: 미커밋 working tree 정리 + DSR fork 핀. 전부 `feat/application-containers` push 완료(HEAD `d9d8df0`, origin 0/0):
① **워크스페이스 통합**(`4c36cc5`, ADR-024) — 흩어진 ROS2 소스를 단일 `cobot_ws/src` colcon 레이아웃으로 재배치. `src/` 를 grouping 디렉토리로: `cobot1_ws`(rokey_cobot1 — 학습용 DoosanBootcamInt1 **신규 편입**) + `cobot2_ws`(robot_control / cobot2_bringup / rokey_cobot2 / yolo_ws{od_msg,object_detection} / voice_ws{voice_processing} / pick_and_place_*). 이름충돌로 기존 `rokey`→`rokey_cobot2`. 런타임 ws `~/cobot2_ws`→**`~/cobot_ws`**. 컨테이너 dev bind-mount = 통합 ws 서브디렉토리(`cobot2_ws/{yolo_ws,voice_ws}`)로 변경 — 별도 `~/yolo_ws`·`~/voice_ws` + `dev-ws-setup.sh` + install.sh dev-ws step **폐기**(전체 **17→16** step, network 고정IP=step16). host build `--packages-skip object_detection voice_processing`(컨테이너 전용 — torch/openwakeword 이미지에만), `pick_and_place_*` COLCON_IGNORE. Dockerfile COPY 경로·colcon log gitignore 동반. 124 files, +1292/−136.
② **DSR clone 소스 fork 핀**(`d9d8df0`) — `doosan-robotics/doosan-robot2 -b jazzy`→**`ROKEY-SPARK/doosan-robot2_jazzy`** fork default 브랜치 main(= 검증 jazzy 스냅샷 816ecb5d). fork 엔 jazzy 브랜치 없어 `git clone -b` 제거. upstream push drift/force-push/삭제 위험 차단. (구 `dsr-rokey-fork` 워크트리·브랜치 = 재구조화 tip 위로 rebase→conflict 2건 해소→ff 머지 후 정리·삭제.)
**검증**: secret 0·AI attribution 0·`shellcheck -x` pass(install.sh+resources)·staged 빌드산출물 0·rebased diff 는 fork 핀만(재구조화 끌려옴 없음). **정적만** — ⚠ `~/cobot_ws` 실 재빌드·컨테이너 dev mount·fleet 클린설치는 **미검증**(실 머신 필요 — 상단 ⚠ 블록 참조).

2026-06-16 (실측) — **[실측]** 원격 동기화 + 컨테이너 dev(bind-mount) 모드 voice 검증 + clean-머신 결함 2건 수정. 전부 `feat/application-containers` push 완료(HEAD `be74716`):
① **원격 동기화** — 이 머신을 origin 최신으로: `main` ff(`164dea1`). `feat/application-containers` 는 로컬이 갈라져(셧다운 패치+옛 핸드오프 2커밋 ahead, 원격 16 ahead) origin 채택 reset 후 셧다운 패치만 재적용. **robot_control Ctrl+C 셧다운 패치 `dd9c660` 커밋·push 완료**(원본 byte-identical 재적용). ⚠ **실기 Ctrl+C 종료 실측은 로봇 미연결로 미완** — 로봇 연결 세션에서 `colcon build --packages-select robot_control` 후 검증, main 승격은 그 뒤.
② **dev 모드 voice·yolo 검증 PASS** — bind-mount(`~/{voice,yolo}_ws/src`→`/ws/src`)로 두 컨테이너 모두 host 소스 live 실행(import 모듈 inode 가 host 와 동일), host↔container DDS, 노드 기동·서비스 등록 확인. **voice**: 마이크→웨이크워드 0.358→Whisper STT→GPT 추출 `해머`(target "pos1" 미추출은 음성 전사 어휘 디테일·결함 아님). **yolo**: RealSense D435i 연결→카메라 15Hz→`/get_3d_position {target:hammer}` round-trip(도구 부재로 `[0,0,0]`·`No detection`, 추론 파이프라인 실동작)→viz(camera→yolo-viz→host viewer cv2 창) 화면 표시까지 확인.
③ **clean-머신 dev-mode 결함 2건 발견·수정** — (a) `1f59df9` dev `colcon build` 에 `--merge-install` 추가: builder 이미지의 merged `/ws/install` 이 named volume 에 복사돼 `--symlink-install` 단독은 layout 충돌로 빌드 실패 → `|| true` 에 묻혀 baked 코드가 돌던 silent fallback(bind-mount 무력화). (b) `be74716` 두 Dockerfile builder 에 `rmw-cyclonedds-cpp`(torch/pip 레이어 뒤 별도 레이어 = 캐시 보존): builder 에 cyclonedds RMW 없어 강제 RMW 로드 실패로 노드 기동 불가. **voice·yolo dev 이미지 둘 다 재빌드(각 ~30s·48s, 캐시 재사용)·검증 완료.**
④ **머신 상태 수정(repo 무관)** — `~/.ros2_jazzy_test/cyclonedds.xml` 이 stale(`enp4s0` 단일·`lo` 없음, Jun5 렌더)이라 로봇망 NIC(enp4s0) down 시 모든 ROS2 노드가 DDS 도메인 생성 실패(컨테이너 crash-loop·host `ros2` 도 영향). `bash resources/dds-tuning.sh` 재실행으로 `lo`-first 재렌더 → host↔container loopback 통신 복구. **기설치 머신은 dds-tuning.sh 재실행 필요**(렌더 정책 갱신분 반영).
**검증**: voice·yolo e2e(②), 시크릿 0·AI attribution 0. **미검증(실 머신·내일 2026-06-17 예정)**: 실기 Ctrl+C 종료, Calibration RG gripper 하드웨어, yolo 실물 도구 검출(이번엔 도구 부재로 `[0,0,0]` 까지만). plan: `/home/rokey/.claude/plans/melodic-cooking-kahan.md`.

2026-06-15 (후속7) — **[문서]** 활성 셸 스크립트 26개 영어 통일 + ROKEY bootcamp 저작권 배너(사용자 요청). 모든 파일 shebang 다음에 동일 4줄 블록(`Copyright (c) 2026 ROKEY bootcamp. All rights reserved.`) 삽입. 대상: `install.sh` + `resources/*.sh`(18) + `containers/*.sh`(5) + `scripts/*.sh`(2). 제외: `backup/*.sh`(humble 원본), `.github/workflows/*.yml`(비 `.sh` — 한글 잔존, 별도 요청 시). 코드 주석 + 런타임 출력(`echo`/`printf`/progress/warn/error/prompt) + heredoc(`.desktop` `Comment=`·`install.sh` usage) 전부 한→영. **behavior-preserving** — bash 제어흐름·변수·명령 무변경, 문자열/주석만(전체 비-주석 diff 감사로 확인). **검증**: full-set `shellcheck` RC=0(baseline 동일), 잔여 한글 0, 배너 26개 전부, `set -` 무결성(source-lib 5개 없음·`install-resume-launcher.sh` `set -uo`·나머지 `set -euo`), `install.sh --help`/`--status` 영어 출력+exit0. **사소 behavior 1건**: `dds-tuning.sh` 의 레거시 `~/.bashrc` 정리용 `sed` 삭제 패턴이 한글(`모든 새 셸 기본 RMW = CycloneDDS`)이라 영어로 변경 → 아주 옛 버전을 돌렸던 머신에서만 그 stale **주석 한 줄**이 자동 정리 안 됨(해롭지 않음, managed export 블록은 정상, 클린설치 무관). **미커밋**(상단 ⚠ 참조). plan: `/home/rokey/.claude/plans/install-sh-refactored-lamport.md`.

2026-06-15 (후속6) — **[문서]** dev 워크스페이스 생성을 install.sh 에 편입(사용자 요청). `~/yolo_ws`·`~/voice_ws` 를 수동 `dev-ws-setup.sh` 에서 install.sh **step16**(`container_dev_ws`)으로 올려 클린설치 시 자동 생성 — 어느 머신이나 dev-ready(소스 복사뿐, host pip 없음). 전체 step **16→17**(network 고정IP 16→17). 카운트 단일소스 `orchestrate.sh::INSTALL_EXTRA_COUNT` 4→5(`install_steps_total`=17), `config.sh::TOTAL_STEPS` fallback 17. 동기화: CLAUDE.md `[n/17]`, `network-static-ip.sh`·ADR-021 의 step 번호 17, ADR-023 Consequences(install.sh 자동 생성 반영), `containers/README.md`. dev **컨테이너** 자체(`-f docker-compose.dev.yml`)는 여전히 opt-in. 멱등(이미 있으면 skip)·resume 안전(state key `container_dev_ws`).

2026-06-15 (후속5) — **[문서]** Calibration pymodbus 3.x 수정 + corecode 저장소 편입 + 컨테이너 dev 모드. 전부 `feat/application-containers` push 완료(HEAD `ee72e39`, 4커밋):
① **Calibration onrobot.py pymodbus 2.x→3.x**(`06f036a`) — 사용자 보고로 발견. 실제 2.x 코드는 `corecode/Calibration_Tutorial/onrobot.py`(gitignored `corecode.zip` 안, 디스크엔 `.pyc` 만 풀려 있어 Explore 가 처음 못 찾음). `cobot2_ws` 의 onrobot.py 3개는 이미 3.x — 차이는 import(`pymodbus.client.sync`→`pymodbus.client`) + `unit=`→`slave=`(12곳) + 호출 뒤 `isError()` 가드뿐. 추적되는 3.x 본과 byte-identical 로 교체. **⚠️ [실측] RG gripper open/close/move 하드웨어 검증 미완**(ADR-014 — 검증 전 실로봇 운용 금지).
② **corecode 저장소 편입**(`b6e92a1`) — `.gitignore` 에서 `corecode/` 해제, dev/연구 튜토리얼(Calibration/DRL/OD/VoiceProcessing) 소스 추적. **하드코딩 Roboflow 키**(`OD_Tutorial/YOLO/data_download.ipynb`) → `os.getenv("ROBOFLOW_API_KEY")` redact + 노트북 출력 제거. 제외: `__pycache__`/`*.pyc`(전역 규칙)+중복 `hello_rokey_8332_32.tflite`(cobot2_ws/containers 에 이미 있음)+대용량 `class_embeddings.json`. **corecode 는 dev 전용 아님**(사용자 결정) → `.claude-main-exclude` 미등록 → 다음 `merge-to-main` 시 공개 main 으로 정상 승격.
③ **컨테이너 dev 모드 override**(`34b1492`, ADR-023) — `containers/docker-compose.dev.yml`: host `~/yolo_ws/src`·`~/voice_ws/src` 를 `/ws/src` 에 bind-mount(코드 수정 즉시 반영), `build.target=builder`+별도 dev 이미지 태그(프로덕션 clobber 방지), 노드 auto-run 끔(sleep) → `docker exec` 진입해 수동 `ros2 run`(디버깅 용이). `containers/dev/bashrc`(컨테이너 `/root/.bashrc` 로 mount)로 exec 셸에 ROS overlay+venv PYTHONPATH 자동 source(entrypoint 는 PID1 전용이라 exec 셸엔 미반영). `containers/dev-ws-setup.sh` 가 `cobot2_ws` 에서 ~/*_ws 복사 생성(별도 WS — 레포 공유는 수동 커밋, symlink 은 bind-mount 와 충돌해 복사 채택). `config.sh` YOLO_WS/VOICE_WS, `containers/README.md` 사용법.
④ **Roboflow placeholder**(`ee72e39`) — `.env.example` 에 `ROBOFLOW_API_KEY`(튜토리얼 전용, 설치/런타임 무관). **키 rotate 는 [실측/문서] 사용자 외부 작업**(평문 노출됐던 `VdSAW…` — git history 미유입, 추적 시작 커밋이 이미 redact 본. 단 로컬 `corecode.zip` 원본엔 평문 잔존, gitignored).
**검증(이 박스)**: shellcheck(dev-ws-setup/bashrc/config) 통과, `docker-compose.dev.yml` YAML 유효, staged 시크릿 0건, AI attribution 0건. **미검증(실 머신)**: compose 머지(이 박스 compose v2 부재)·pymodbus 3.x import·gripper 하드웨어 → [실측].

2026-06-12 (후속4) — **[문서]** 공개 main 트리 위생 마무리 + `a01-a04` 스테이지 스크립트 폐기. (`refactor/installer-shell` 은 이미 `feat/application-containers` 에 머지됨 `68f452d` — 후속3 의 "push/머지 결정"은 해소.)
① **main 제외 확장 + 가드 self-contained**(`1268db2`, main `6de576f`) — `backup/`(humble 보존)·`scripts/`(승격 툴링)을 `.claude-main-exclude` 등록 후 공개 main 에서 제거. 내부경로 가드 워크플로가 `scripts/check-no-claude-on-main.sh` 의존을 버리고 `.claude-main-exclude` 를 직접 읽어 `git ls-tree` 인라인 검사(스크립트가 main 트리에 없어도 동작).
② **`.main-keep-ours` 제외**(`bb469a1`, main `e3440cd`) — keep-ours 메타데이터도 main 제외. `merge-to-main.sh` 가 이 목록을 checkout·제외 **이전**(상단, dev 버전)에 미리 읽도록 reorder — 안 하면 제거 루프가 파일을 지운 뒤 읽혀 README 보존(keep-ours)이 깨지는 순서 버그.
③ **`a01-a04` 폐기**(`915cdd8`) — install.sh resumable + `run_step` 의 state-skip 으로 standalone 이 강제 재실행을 본래 못 해 잔재. 4개 삭제, 서브커맨드로도 대체 안 함. 강제 재실행은 `--reset`/`resources/<step>.sh` 직접. `orchestrate.sh` 의 `run_stage_a0N`·분모 상수는 install.sh 전체 시퀀스가 계속 써 유지. ADR-022 기록 + a0N·run-step.sh·steps.sh 참조 정리.
**✅ promotion 완료 (2026-06-15)**: `bash scripts/merge-to-main.sh feat/application-containers` 로 a0N 삭제·install.sh 갱신이 main 에 반영(merge `a73fdfa` — modify/delete 충돌은 제외경로 제거로 해소, README 충돌은 keep-ours 로 main 보존). keep-ours 로 남은 main README 를 install.sh 단독 안내로 갱신(`f6cbac1` — 단계 구성 테이블의 스크립트열·단독 실행 블록 제거, 역할 기준 재정리). main `e3440cd → f6cbac1` push. 가드(제외경로 0)·shellcheck·`--help` 통과. main 트리 = 설치 스크립트+컨테이너+공개 README 만. **dev README 는 working notes 라 a01-a04 내부 단계라벨 잔존 — 의도(keep-ours 로 main 미전파).**

2026-06-11 (후속3) — **[문서]** 셸 스크립트 Comprehensive 리팩토링, 신규 브랜치 `refactor/installer-shell`(base `feat/application-containers`, 8커밋). 전부 behavior-preserving. **(2026-06-12 기준 `feat/application-containers` 에 머지 완료 — 아래 "미push" 표기는 과거 시점.)**:
① **일관성**(`abe3cf6`) — source 전용 lib(config/state/run-step/steps/confirm/env-load/unattended/activate)에 "set -euo 안 둠(호출 진입점이 셸옵션 소유)" 예외 명시, 메시지 prefix 통일, stale "STEPS_TOTAL=15" 주석 제거, `docs/SCRIPTING_GUIDELINES.md` 신규, CLAUDE.md Hard Rule #5 를 "실행 진입점만"으로 정제.
② **apt-repo 헬퍼**(`e9557f2`~`8796c1e`, vendor별 5커밋) — `resources/apt-repo.sh::add_apt_repo` 추출, docker/ros2/realsense/vscode/nvidia 전환. vendor별 키 처리(다운로더 플래그·dearmor write·list 비교)는 인자로 보존. **nvidia list 는 multi-line `cat`-compare 보존**(grep 단일행이면 멱등 깨짐). docker/nvidia 는 `--no-update`(뒤에 별도 update 존재).
③ **step 단일소스화**(`4cf13d6`) — `resources/steps.sh`(run_stage_aNN(offset)+STAGE_*_COUNT+install_steps_total) 로 install.sh↔a0N step 목록 중복·이중 STEPS_TOTAL 제거. **단계 추가 시 steps.sh STAGE 상수 1곳만**(기존 4곳). reboot(step6)은 install.sh/a01 wrapper(메시지·무인분기·exit) 차이로 인라인 유지. **state key(name) 불변 → resume 호환.**
④ **리뷰**(`576c9b5`) — code-reviewer adversarial(CRITICAL 0): 가이드 인자명 `--key-mode`→`--mode` 정정, nvidia 주석 번호 연속화.
**검증(실 설치 없이)**: full-set shellcheck exit 0; 격리 STATE_DIR all-DONE 실행으로 install+a0N **skip-시퀀스(번호+name) 베이스라인과 byte 동일**; stub trace 로 5 vendor 키 fetch 명령 before/after 동일. **미검증(실 머신 필요)**: 실제 키 다운로드+`apt update` 인증, reboot 경계+복귀 재개 → fleet/VM end-to-end 가 머지 전 게이트. plan: `/home/rokey/.claude/plans/noble-fluttering-cray.md`.
**남은 결정**: push 여부, 머지 대상(feat/application-containers vs main).

2026-06-11 (후속2) — **[문서]** docker login 잔재 제거 + Notion 가이드 보강:
① **docker login 잔재 제거**(`0b48886`) — app 이미지(yolo/voice)는 공개 드라이브 tar→`docker load` 라 레지스트리 로그인 불요인데, `voice-env-check.sh` 가 "pull 전 docker login 필요할 수 있음" 안내 블록을 들고 있었음(옛 Docker Hub pull 설계 잔재). 블록 + `a04-voice-precheck.sh`/`install.sh` step12 주석 정리. **ADR-007/publish 경로(docker login+push)는 history 로 보존** — ADR-019 가 "Docker Hub 또는 Drive" 중 Drive 채택으로 amend, 결정 흐름 추적 위해 미삭제(사용자 결정).
② **Notion 마이그레이션 페이지 §3-1**(git 무관·원격 반영) — `fetch-images.sh`(step 15)를 line-by-line 으로 풀어씀(config 좌표 로드→멱등 skip→2-step confirm 다운로드→SHA256 검증→docker load). 같은 블록 step 12 + 폴더트리의 docker login 잔재도 동시 제거.

2026-06-11 (후속) — **[실측+문서]** YOLO 이미지 재빌드 + 드라이브 재배포 완료(2커밋 push, `f874261`+`12c6fb1`):
① **YOLO Dockerfile 레이어 재정렬**(`f874261`) — torch 설치를 노드 소스 COPY 앞으로 이동. 노드 코드만 고쳐도 torch(최중량 레이어)가 재다운로드되던 문제 제거. venv 는 전역 PATH 미등록·`/opt/venv/bin` 명시 호출 → colcon build 는 시스템 python 유지(콘솔스크립트 shebang 동작 보존, `entrypoint.sh` PYTHONPATH 우회 그대로).
② **재빌드 + 검증** — `build-all.sh` 게이트 PASS(secret 없음, yolo/voice import smoke, voice tflite predict). 이미지 내부 `object_detection/yolo.py` 에 `.get(target)`+미검출 처리 반영 확인 → KeyError 수정이 드디어 배포 이미지에 포함.
③ **드라이브 재배포 + SHA 갱신**(`12c6fb1`) — `docker save` tar(4.62GB = 4620719104B) → 드라이브 기존 file ID 버전 교체(ID/공유 유지) → `config.sh YOLO_IMAGE_SHA256` = `4b292639…` 갱신. 무인증 curl 도달성 + Content-Length 일치 검증 통과. **VOICE 미변경(재업로드 불요).**

2026-06-11 — **[문서]** 전부 origin push 완료(branch `feat/application-containers`, 4커밋):
① **DDS 도메인 단일값 일치**(`43fa06c`) — `.env.example` 의 `ROS_DOMAIN_ID` 예시가 `0` 이라 살려 쓰면 host(기본 42)와 컨테이너가 다른 도메인에 떠 노드가 조용히 서로 못 찾던 풋건. 예시를 `42`(단일 진실 소스 = `resources/config.sh`)에 맞추고 "바꾸면 host·양 컨테이너 동일 값 유지" 경고 주석 추가.
② **문서 정정** — README 실기 기동 예시 placeholder `<controller-ip>`→실제 `192.168.1.100`(`ad562cd`); 결정기록(`docs/decisions`) 검증 명령 `docker exec rokey-yolo`→`docker compose exec yolo-detection`(`9d01749`).
③ **gitignore 위생**(`3907af1`) — 로컬 도구 산출물/캐시(`.agents/`, `.understand-anything/`, `.claude/skills/`+`skills-lock.json`, `backup/llm_wiki/`) 추적 제외. `.claude/memory`·`backup/` 보존 스크립트는 서브경로만 타깃이라 추적 유지.
④ **Notion 문서 동기화**(git 무관·원격 반영) — 마이그레이션 페이지 §2-1 아키텍처/§3-1 host 순차설치/§4 폴더구조를 16-step + 그리퍼(.1)/ALSA 마이크/wakeword 토픽/loopback 용어로 갱신; Docker 페이지를 실제 코드(멀티스테이지 Dockerfile·compose·`cobot2_ws` 구조)로 전면 교체 + "기동 순서 견고성"(DDS 비동기 discovery·RMW 통일·`wait_for_service` 블로킹으로 서순 무관, 단 카메라/생산자 영영 부재 시 조용한 hang) 분석 섹션 추가; 서비스 메시지 페이지에 wakeword 설명 삽입.
직전 2026-06-10: DDS 인터페이스=loopback+물리 NIC(ADR-020), ethernet 고정 IP 자동화(install.sh step16·STEPS_TOTAL 15→16), 무인 설치 `--unattended`, OPENAI_API_KEY 처리 버그 수정, fetch 진행바 제거, YOLO KeyError 수정(소스만 — 이미지 재빌드 미반영, 상단 ⚠). 직전 2026-06-09: voice 컨테이너 e2e + cobot2_bringup 분리 + 드라이브 이미지 fetch 전환.

---

## Next Actions (priority order)

1. **[실측] 전체 클린설치 검증 — 다른 노트북(fleet 머신)에서 진행** — 최신 origin `git clone` → `bash install.sh`. 새 머신엔 이미지가 없어 **step15 가 드라이브에서 실제 다운로드**(yolo 4.62GB 첫 실측 자연 발생 — `docker rmi` 불요). nvidia-container-toolkit 은 step14(reboot 이후)에서 자동 설치(SKIP_IF_NO_GPU=1 — GPU 없으면 정상 skip). a01(step1~6) NVIDIA+reboot destructive, step12 `.env` OPENAI_API_KEY interactive. **점검: 드라이브 파일 2개가 "링크 있는 사람 보기" 공유여야 다른 네트워크/무계정에서 무인 curl 가능**(이 머신 fetch 성공은 동일 계정/네트워크 영향 배제 못 함). **(2026-06-17 갱신)** 이제 **전체 16 step**(step 15 fetch, **step 16 ethernet 고정 IP** `192.168.1.30/24` — dev-ws 생성 step 폐기, 통합 `~/cobot_ws` 가 dev bind-mount 서브디렉토리 포함). DSR clone 은 `ROKEY-SPARK/doosan-robot2_jazzy` fork. `bash install.sh --unattended` 로 reboot·재개 무인 가능(GUI 세션, 복귀 후 sudo 비번 1회). **OPENAI_API_KEY 처리 버그 수정됨** — 쉘 env 에 키가 있든 `.env.example` 에 잘못 넣든 자동 처리 → 지난번 voice crash-loop 재발 안 함. yolo KeyError 도 미검출 처리(단 이미지 재빌드 전엔 옛 이미지 — 상단 배너 참조).

2. **[실측/문서] cobot2_bringup 클린설치 자동 빌드 검증** — `dsr-project-install.sh` 가 이제 repo grouped src(`WS_GROUPS=(cobot1_ws cobot2_ws)`)를 통째로 `cp -a` 미러(HOST_PKGS 개별 복사 폐기, 2026-06-17). clone → 빌드 시 `ros2 launch cobot2_bringup bringup_all.launch.py` resolve 확인. host build 는 `object_detection`/`voice_processing` `--packages-skip`, `pick_and_place_*` COLCON_IGNORE 로 제외됨을 함께 확인.

3. **[DONE 2026-06-11] Dockerfile 레이어 재정렬** — `containers/yolo-detection/Dockerfile` 의 torch pip 레이어를 소스 COPY 앞으로 이동 완료(`f874261`) + 재빌드·드라이브 tar/SHA256 갱신 동반 완료(`12c6fb1`). 잔여(소): voice Dockerfile 동일 안티패턴 점검 — voice 는 torch 미사용이라 재다운로드 비용이 작아 우선순위 낮음.

4. **[문서] pick_and_place_text/voice spin 버그** — `{detection.py,yolo.py}` 의 `rclpy.spin_once` 재진입 버그 잔존(object_detection 만 spin 수정). **KeyError(`reversed_class_dict[target]`)는 2026-06-10 에 3 copies 전부 `.get()`+미검출로 수정 완료.** 레거시 spin 버그: 동일 패치 vs 레거시화 결정.

5. **[문서] 모델 가중치 중복** — `object_detection/resource/yolov8n_tools_0122.pt`(6.3MB) + `pick_and_place_text/resource/` 동일본. dedup vs pick_and_place_text 레거시화.

6. **[실측] fleet 기존(DONE) 머신 deps 전파** — toolkit 은 이제 install.sh 자동이나 **step3 가 이미 DONE 인 머신엔 미반영** → 수동 `bash resources/nvidia-container-toolkit-install.sh`. 동일 패턴: DSR 패치(`~/dsr_patch_command.txt`), python3-pymodbus. (새 노트북 처음부터 설치면 모두 자동.)

7. **[문서] 미정리 git** — backup 브랜치 `backup/pre-github-sync-2026-05-29`(origin 미push), 태그 `v0.1.0`(미push).

8. **[문서] RealSense udev rule 명시화 패치**(보류) — `realsense-sdk-install.sh` 에 `librealsense2-udev-rules` 명시 + 검증 게이트.

9. **[공통] 브랜치 canonical** — `feat/application-containers` vs `feat/application-shell` → main 병합 시점.

---

## Open Decisions

- nvidia-container-toolkit: 편입 완료(2026-06-09 — install.sh step14, **reboot 이후**; reboot 전 설치가 드라이버 모듈 미로드로 실패해 이동). 잔여: main(host 전용) 병합 시 포함 여부.
- 모델 중복(object_detection vs pick_and_place_text) dedup vs 레거시화.
- pick_and_place_text detection/yolo spin 버그: 동일 패치 vs 레거시화.
- 브랜치 canonical (containers vs shell) — main 병합 대상.
- 미push git 객체(backup 브랜치 / `v0.1.0` 태그).
- RealSense udev 명시화.

---

## Remaining Issues

- pick_and_place_text spin 버그 미수정(robot_control 이 컨테이너 detection 호출로 우회 중).
- fleet 타 머신: DSR 패치 + python3-pymodbus + nvidia-container-toolkit 미반영.
- yolo 이미지 드라이브 **전체** 다운로드 미실측(4.62GB) — 2026-06-11 무인증 curl 로 첫 1MB+Content-Length 일치까지 검증(타입=POSIX tar, 크기 정확 일치, 권한 페이지 없음). 전체 SHA 왕복은 fleet 클린설치서 최종.
- ~~yolo KeyError 수정 소스만 반영~~ → **2026-06-11 재빌드 + 드라이브 재배포 완료** — fetch 시 수정본 수신(Last updated ①). 배포 이미지 내부 yolo.py 에 `.get(target)` 반영 확인.
- **노출됐던 OPENAI API 키 rotate 권장**(진단 중 터미널 노출). 현재 `.env`(gitignore)에 있고 추적 파일엔 없음(유출 안 됨).
- **노출됐던 Roboflow API 키 rotate 권장**(2026-06-15) — `OD_Tutorial/YOLO/data_download.ipynb` 평문 `VdSAW…`, redact→`os.getenv`. git history 미유입(추적 시작 커밋이 redact 본)이나 로컬 `corecode.zip` 원본엔 평문 잔존. rotate 는 사용자 외부 작업(Roboflow 콘솔).
- **[실측] Calibration pymodbus 3.x gripper 하드웨어 검증 미완**(2026-06-15) — `corecode/Calibration_Tutorial/onrobot.py` register write 의미(open/close/move)는 실 RG gripper 로만 검증 가능. 검증 전 실로봇 운용 금지(ADR-014).

---

## Context Notes

### 이미지 드라이브 배포 (2026-06-09)
- install.sh step15 = `containers/fetch-images.sh`: 공개 구글 드라이브 file ID 로 tar 다운로드 → SHA256 검증 → gz/zip 해제 분기 → `docker load`. 이미지 존재 시 skip(멱등). (step14=toolkit, step15=fetch, step16=고정 IP — dev-ws 생성 step 폐기 2026-06-17, 통합 ws 가 dev bind-mount 서브디렉토리 포함.)
- **docker login 불요** — app 이미지는 registry pull 이 아니라 Drive tar→`docker load`. 외부 registry 에서 pull 하는 건 DSR emulator(`doosanrobot/dsr_emulator:3.0.1`, public Docker Hub anonymous) 뿐. (publish 경로 docker login+push 는 ADR-007 history 로 보존 — 현재 미사용.)
- 대용량(>100MB) 다운로드: `drive.usercontent.google.com/download?id=..&export=download` 1차 응답이 virus-scan confirm form(HTML) → `confirm`/`uuid` 토큰 뽑아 2차 요청. 순수 bash curl(host pip 미설치 정책 — gdown 안 씀).
- file ID/SHA256 = `resources/config.sh`(`YOLO/VOICE_IMAGE_GDRIVE_ID`, `_SHA256`). 공개 링크 ID 는 secret 아님. **해시는 레포(신뢰 출처)에, tar 만 드라이브** — 같은 출처면 동시 변조 시 검증 무의미.
- 이미지 제작/검증은 별도 `containers/build-all.sh`(빌드+secret scan+import/tflite smoke). `docker save` tar = yolo 4.3GB / voice 0.42GB(buildkit 레이어 이미 압축 → gzip 무의미). 드라이브 폴더 `1csD1JhZz9xkpBqWR3ZC2udEPeVcndjiI`.
- **클린설치 fetch 실측 주의**: Docker 이미지는 `--reset` 무관 잔존 → 기존 이미지 있으면 step15 skip. 다운로드 경로 타려면 사전 `docker rmi`.

### bringup = cobot2_bringup 패키지 (2026-06-09)
- `ros2 launch cobot2_bringup bringup_all.launch.py mode:=real` — dsr_bringup2 + RealSense(align_depth) + `docker compose up -d` 한 번에. robot_control(실모션·무한루프)은 **미포함** — `ros2 run robot_control robot_control` 분리 실행(인프라/작업 분리). host 기본 `192.168.1.100`(실기 고정), Ctrl+C 시 compose down.
- 레포 경로(compose/config.sh) = config.sh export `ROS2_JAZZY_TEST_REPO`(자기 위치서 계산 — 패키지 설치 후 `__file__` 이 레포 못 가리키는 문제 대응).
- 컨테이너 노드 자동기동: Dockerfile CMD(yolo=`object_detection`, voice=`get_keyword`), compose `command` override 없음 → `up` 만으로 노드 기동(별도 `ros2 run` 불요).
- robot_control voice pick: `DEPTH_OFFSET=-35`, `PLACE_POSITIONS`(pos1/2/3 티칭 posx), `PLACE_LIFT=250`, `PLACE_Z_OFFSET=50`. `/wakeword_detected`(Bool) 토픽으로 wakeword 감지 로깅. `T_gripper2camera.npy` 는 robot_control/resource 에 보유.

### voice 컨테이너 (2026-06-09 검증)
- openwakeword feature 모델(melspectrogram/embedding/silero_vad)을 레포 vendoring(`containers/voice-processing/oww_models/`) + Dockerfile COPY + TFL3 매직 검증 → 빌드 중 다운로드 504 손상본 차단. build-all.sh tflite predict smoke 통과.
- 마이크: host net 은 네트워크만 공유 → `/dev/snd` ALSA 직결(devices) + `group_add: audio`. asound.conf 로 기본 캡처를 실마이크 DMIC `hw:1,6` 고정(컨테이너 기본 `hw:1,0` 은 무음). wakeword/STT 둘 다 sounddevice 16kHz 직접 캡처(scipy resample·PyAudio 폐기).
- 운영 취약: get_keyword 단일스레드 long-blocking → wakeword 대기 중 Ctrl+C 면 좀비 핸들러/백로그. `WAKEWORD_TIMEOUT=30` + 클린 재시작(`docker compose ... down/up voice-processing`)으로 완화.

### 컨테이너 e2e — 검증된 구성 / 함정 (2026-06-08)
- **컨테이너에 cyclonedds RMW 명시 설치 필수** — base 기본 RMW=fastrtps. 없으면 같은 도메인이어도 host 토픽 미발견. yolo/voice Dockerfile runtime 에 `ros-${ROS_DISTRO}-rmw-cyclonedds-cpp`.
- **venv shebang 함정** — colcon build 가 venv 생성 전이라 콘솔스크립트 shebang 이 시스템 python → ultralytics 미발견. `entrypoint.sh` 가 venv site-packages 를 PYTHONPATH 주입해 우회.
- **모델 bake** — `.dockerignore` `**/*.pt` 제외 + `!.../yolov8n_tools_0122.pt` 예외로 이미지 포함.
- **spin 재진입 버그** — 서비스 콜백 내 글로벌 `spin_once` 가 메인 `spin` 과 충돌. ImgNode 전용 `SingleThreadedExecutor`+`spin_once()` 로 해결. import smoke 못 잡음 — service 왕복 e2e 가 잡음.
- nvidia-container-toolkit = host 컴포넌트. passthrough 확인 = `docker run --rm --gpus all ubuntu nvidia-smi`.
- compose voice `env_file: ../.env` → repo 루트 `.env` 존재 필요(빈 파일이라도, gitignore).

### DSR_ROBOT2 jazzy 패치 2종 (origin 반영 완료 — 타 머신/재clone 시 필수)
`dsr_common2/imp/DSR_ROBOT2.py`: ① import NameError `SetSingularityHandlingForce`→`SetSingularHandlingForce`. ② 서비스 무한대기 `_srv_name_prefix=''`→`'dsr_controller2/'`. `dsr-project-install.sh` 가 clone 직후 멱등 sed. DONE 머신은 `~/dsr_patch_command.txt` 직접 sed.

### 실기 로봇 환경 (검증된 값)
- 모델 `m0609`, ns `dsr01`. 컨트롤러 `192.168.1.100:12345`, 그리퍼 toolchanger `192.168.1.1:502`. host `enp4s0 192.168.1.30/24`. 실서버 `/dsr01/dsr_controller2/...`, joint_states `/dsr01/joint_states`.

### RealSense / DDS
- 토픽 `/camera/camera/{color/image_raw, aligned_depth_to_color/image_raw, color/camera_info}`. `align_depth.enable:=true` 필수.
- raw 0Hz → `net.core.rmem_max`(커널)+`SocketReceiveBufferSize`(XML) 둘 다 상향(dds-tuning.sh). `RMW_IMPLEMENTATION`·`CYCLONEDDS_URI` 쉘별 환경변수 — host/컨테이너 일치 필요(`network_mode: host` 상속).

### 함정 (다음 세션 피하기)
- 같은 패턴 버그가 여러 파일에 퍼짐 → 재빌드 전 패키지 전체 grep 전수 수정.
- python stdout block-buffered → hang 오인. `python3 -u` / `flush=True` / `PYTHONUNBUFFERED=1`.
- DSR 서비스 "있는데 응답 없음" → short name(클라) vs `dsr_controller2/` prefix(실서버) 갈림.
- 서비스 `wait_for_service` 무한대기(timeout/break 없음) = 서순엔 강건하나 생산자 영영 부재 시 크래시 아닌 **조용한 hang**. 특히 카메라 미연결/`camera:=false` → object_detection 이 intrinsics 무한 대기 후에야 `/get_3d_position` advertise → robot_control 영영 hang. "멈춤" 디버깅 시 생산자(카메라·실기 컨트롤러) 기동 여부부터 확인.

---

## Current Focus
- **[실측] Top priority**: **다른 노트북(fleet)에서 전체 클린설치 검증** — 새 머신이라 step15 가 드라이브에서 실제 다운로드(yolo 4.62GB 첫 전체 실측), toolkit step3 자동. 드라이브 공유("링크 있는 사람")는 [문서] 머신서 무인증 도달성+크기 검증 통과 — 타 네트워크/무계정 최종 확인은 fleet 머신. **이제 16-step + 통합 `~/cobot_ws`(grouped src) + DSR fork clone 을 함께 검증**(2026-06-17 변경분 첫 실 머신 검증).
- **[문서]**: pick_and_place_text spin 버그 + 모델/패키지 중복(object_detection vs pick_and_place_text) 정리 결정. (Dockerfile 레이어 재정렬은 2026-06-11 완료.)
- **Friction**: 미push git 객체 + 브랜치 canonical + 모델/패키지 중복 정리 결정 대기.
