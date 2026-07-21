# 협동2 vision Foundation Model 도입 feasibility (RTX 4060 Laptop, 8GB)

작성일 2026-07-06 · 대상 = 강사·운영진 내부 의사결정(go/no-go) · 산출물 = 본 문서 + docx + Notion

증거 태그 규약: **(Fact)** 제3자 검증 가능(공식 문서·논문·릴리스) · **(Claim)** 출처 일부·저자 주장 · **(Disclosure)** 추정, fact 아님. 이 환경(RTX 4060 Laptop)에서 실측하지 않은 지연·VRAM 수치는 전부 (Disclosure) 로 두고 "온디바이스 측정 필요"를 명시한다.

---

## 1. 결론 (Executive Summary)

- **조건부 GO** — 단계적 파일럿으로 도입 검토 권장. 단, 커리큘럼 확정 전 **학생 4060 Laptop 실기 벤치마크 1회**가 선행 조건(아래 수치 다수가 미측정 추정).
- **핵심 근거**: 현재 YOLOv8n 은 closed-set(3-class 공구) → 새 물체마다 Roboflow 데이터셋 수집 + 재학습이 필요. open-vocab foundation model 은 **텍스트 프롬프트만으로 임의 물체 검출** → 시간이 제한된 수업에서 데이터셋·학습 부담 제거 + "foundation model vs task-specific model" 개념을 실물로 교육.
- **추천 우선순위**:
  - **Phase A (권장 1순위): open-vocab 검출 drop-in** — **YOLOE** 또는 **YOLO-World**. ultralytics-native → 기존 `yolo-detection` 컨테이너·numpy<2·cu128 스택 그대로, real-time, 8GB 여유. 현재 `/get_3d_position` 파이프라인에 최소 수정으로 삽입.
  - **Phase B: grasp segmentation** — **FastSAM**(ultralytics-native) 또는 **MobileSAM**. bbox 대신 mask → 집기 지점·자세 정밀도 향상.
  - **Phase C (demo/선택): VLM 장면 추론** — **Florence-2-base**. 음성 명령(GPT-4o)과 language grounding 연계. on-demand(비실시간).
- **NO-GO(실시간 파이프라인 기준)**: Grounding DINO 실시간, 대형 VLM(Qwen2.5-VL-7B 이상)을 8GB Laptop 라이브 파이프라인에 상시 투입 — on-demand/오프라인 용도로만.

---

## 2. 배경 & 현재 상태

- **현재 vision**: YOLOv8n (ultralytics 8.4.56), Roboflow "Mechanical-tools" 3-class 커스텀 학습(best.pt). `object_detection` 노드가 `/get_3d_position` 서비스로 RealSense depth 를 결합해 3D 좌표 산출 → `robot_control` 이 pick&place. (Fact — repo `containers/yolo-detection/Dockerfile`, `docs/COMPATIBILITY.md`)
- **한계**: closed-set. 새 공구/물체를 추가하려면 라벨링 → 데이터셋 → 재학습 → weight 교체. 수업 한 차시에 새 물체를 넣기 어렵다.
- **컨테이너 스택**: torch 2.11.0+cu128 / CUDA 12.8(컨테이너 내부, host CUDA 없음) / numpy<2(ultralytics 호환 재핀) / Python 3.12 / ROS2 jazzy / RMW=cyclonedds. (Fact)
- **음성**: GPT-4o via LangChain(별도 `voice-processing` 컨테이너). 현재 vision 과 language 는 분리 — foundation model 도입 시 연결 여지. vision FM 은 repo 전체에 아직 없음(green field). (Fact)
- **배포 제약**: 학생기 = **RTX 4060 Laptop, 8GB VRAM**. 노트북이라 디스플레이·배터리 공유. (Fact — `docs/COMPATIBILITY.md`, MEMORY)

---

## 3. 평가 기준

- **8GB VRAM 적합** — 모델 weight + 활성값이 디스플레이 공유 후 실질 가용(대략 6–7GB (Disclosure)) 안에 드는가. 검출·seg·VLM 동시 상주 여부.
- **속도** — 라이브 카메라 파이프라인용 real-time(≥~15 FPS) 인가, 아니면 on-demand(호출당 수백 ms~수 초) 인가.
- **통합 friction** — 기존 컨테이너·의존성(numpy<2, torch cu128) 재사용 정도. ultralytics-native = 최저, transformers+HF weight = 중간.
- **license** — 수업/재배포 관점. 현재 이미 ultralytics(AGPL-3.0) 상속 중이라 AGPL 계열은 추가 부담 없음.
- **offline weight** — 교실 환경에서 HF Hub 다운로드 로지스틱스(사전 캐시 필요 여부).
- **ROS2 파이프라인 fit** — `/get_3d_position` 서비스·depth 결합·grasp pose 로의 자연스러운 접속.
- **교육 가치** — foundation model 개념 시연력, 재학습 제거 효과.

---

## 4. 후보 landscape

### 4-1. Open-vocab 검출 (현재 YOLO 대체/보강)

| 모델 | params | 8GB VRAM | 속도 | license | 통합 friction |
|---|---|---|---|---|---|
| YOLOE (THU-MIG, ICCV2025) | ~26M (Fact) | 여유 (Disclosure) | real-time (Claim) | AGPL-3.0 (Fact) | 최저 — ultralytics-native |
| YOLO-World (AILab-CVC, CVPR2024) | S=13M (Fact) | 여유 (Disclosure) | real-time (Claim) | GPL-3.0 원본 / AGPL via ultralytics (Fact) | 최저 — ultralytics-native |
| Grounding DINO (IDEA, 2023) | ~172M (Claim) | 적합하나 무거움 (Disclosure) | non-realtime, 수 FPS (Disclosure) | Apache-2.0 원본 (Claim) | 중간 — transformers+HF |
| OWLv2 (Google) | 상당 (Claim) | 빠듯 (Disclosure) | non-realtime (Disclosure) | Apache-2.0 (Claim) | 중간 — transformers+HF |

- **YOLOE** = 텍스트/비주얼/prompt-free 3모드, 검출 + instance segmentation 동시(YOLO11급 속도·파라미터). 현재 파이프라인에 가장 이상적. (Fact — ultralytics docs, THU-MIG/yoloe)
- **YOLO-World** = prompt-then-detect, 어휘를 파라미터로 재-매개화해 속도 유지. 더 성숙·레퍼런스 풍부. (Fact)
- **Grounding DINO** = open-set 정확도 높으나 laptop 실시간 부적. 오프라인 auto-labeling(데이터셋 자동 라벨) 용도로는 유용.

### 4-2. Grasp segmentation (bbox → 픽셀 mask)

| 모델 | params | 8GB VRAM | 속도 | license | 통합 friction |
|---|---|---|---|---|---|
| FastSAM | 68M (Fact) | 여유 (Disclosure) | real-time (Claim) | AGPL-3.0 (Fact) | 최저 — ultralytics-native |
| MobileSAM | ~9.7M, encoder 5.78M (Fact) | 여유 (Disclosure) | 매우 빠름 (Claim) | Apache-2.0 (Claim) | 중간 — 별도 패키지 |
| SAM2 (Meta) | t / S=46M / B+=80.8M / L=224.4M (Fact) | tiny/small 여유 (Disclosure) | 이미지 near-realtime (Disclosure) | Apache-2.0 (Claim) | 중간 — 별도 패키지·weight |

- **FastSAM** = YOLOv8-seg 기반 → 기존 스택 그대로. grasp mask 최소 friction 경로. (Fact)
- **MobileSAM** = distilled TinyViT, FastSAM 대비 ~7배 작고 5배 빠름. promptable(point/box) — 검출 박스를 프롬프트로 넘겨 정밀 mask. (Fact)
- **SAM2** = tiny/small 이면 8GB 적합, 비디오 트래킹까지. box→mask 로 grasp point·주축(orientation) 추정에 최적. (Fact)

### 4-3. VLM 장면 추론 (음성 명령 연계)

| 모델 | params | 8GB VRAM | 속도 | license | 통합 friction |
|---|---|---|---|---|---|
| Florence-2-base (Microsoft) | 0.23B (Fact) | 여유, fp16 ~0.5GB (Disclosure) | on-demand (Disclosure) | MIT (Fact) | 중간 — transformers+HF |
| Florence-2-large | 0.77B (Fact) | 적합, fp16 ~1.5GB (Disclosure) | on-demand (Disclosure) | MIT (Fact) | 중간 — transformers+HF |
| Qwen2.5-VL-3B (Alibaba) | 3B (Fact) | Q4 양자화 시 8GB 적합 (Fact) | on-demand, 느림 (Disclosure) | Qwen license (Fact) | 중간~높음 — transformers+양자화 |
| Moondream2 | ~1.9B (Claim) | fp16 8GB 적합 (Disclosure) | on-demand (Disclosure) | Apache-2.0 (Claim) | 중간 — transformers+HF |

- **Florence-2** = 단일 모델로 caption·detection·segmentation·OCR·grounding 을 task 프롬프트로 전환. 8GB 에 base/large 모두 적합. "one model, many tasks" 교육 시연력 최고. (Fact)
- **Qwen2.5-VL-3B** = bbox+point grounding, JSON 출력, edge 지향. Q4_K_M 양자화로 8GB 적합. 자연어→객체 grounding 을 GPT-4o 음성과 연결 가능하나 laptop 실시간 아님. (Fact)
- **Moondream2** = 초소형 VLM(VQA/caption/pointing). 가장 가벼운 VLM 데모 옵션. (Claim)

---

## 5. RTX 4060 8GB 적합성 분석

- **가용 VRAM**: 8GB 물리 - 디스플레이/컴포지터 공유 → 라이브 파이프라인 실질 **~6–7GB (Disclosure, 측정 필요)**.
- **단일 상주(권장)**: 검출 모델 1개(YOLOE/YOLO-World, <~2GB (Disclosure)) 는 여유. grasp seg(FastSAM/MobileSAM) 추가해도 합산 안전권 (Disclosure).
- **동시 상주 위험**: 검출 + SAM2 + VLM 을 동시에 상주시키면 8GB 초과 위험 → **순차 실행 또는 on-demand 로딩**으로 회피. VLM 은 라이브 상주 대신 서비스 호출 시 로드/언로드.
- **양자화**: 3B급 VLM 은 fp16 로는 빠듯 → 4-bit(Q4) 필요. 검출/seg 계열은 양자화 불요.
- **real-time vs on-demand 구분**:
  - real-time(카메라 스트림): YOLOE, YOLO-World, FastSAM, MobileSAM.
  - on-demand(서비스 호출/데모): Florence-2, Qwen2.5-VL, Grounding DINO, SAM2(이미지).
- **모든 지연·VRAM 수치는 이 4060 Laptop 에서 미측정** — 파일럿 1단계 = `nvidia-smi` VRAM + FPS 실측(현재 YOLOv8n baseline 대비). baseline 비교 없는 도입 결정 금지.

---

## 6. 기존 파이프라인 통합 경로

- **검출 교체(가장 깔끔)**: `object_detection` 노드의 YOLOv8 추론부를 YOLOE/YOLO-World 로 교체, 텍스트 프롬프트 리스트(예: 공구명)를 입력. `/get_3d_position` 서비스·depth 결합·`robot_control` 인터페이스 **불변**. 컨테이너 의존성은 ultralytics 그대로(+YOLO-World 는 `clip`/`ftfy`/`regex` 소량 추가).
- **grasp 향상**: 검출 박스를 FastSAM/MobileSAM 프롬프트로 넘겨 mask 획득 → mask centroid·주축으로 grasp pose 계산 → `robot_control` grasp 정밀도 향상. FastSAM 은 동일 컨테이너, MobileSAM/SAM2 는 별도 패키지+weight.
- **voice 연계(Phase C)**: 현재 GPT-4o 가 음성→명령 파싱. 이를 확장해 **객체 설명 텍스트를 open-vocab 검출 프롬프트로 전달**(예: "못 박는 도구" → "hammer" grounding). 또는 Florence-2 로 이미지+언어 직접 grounding. 별도 서비스 또는 `voice-processing` 컨테이너 확장.
- **호환 주의**: transformers 계열(Grounding DINO/Florence-2/Qwen-VL) 도입 시 **numpy<2 핀 유지 검증** 필수(ultralytics 와 공존). HF weight 는 이미지 빌드 시 캐시 또는 최초 실행 다운로드 — 교실 오프라인이면 사전 캐시.

---

## 7. 추천 & 단계적 파일럿

- **Phase A — open-vocab 검출 drop-in (권장 1순위, 최소 friction)**
  - 대상: YOLOE(검출+seg 통합 선호) 또는 YOLO-World(성숙·레퍼런스 선호).
  - 작업: 실기 벤치마크(FPS/VRAM, YOLOv8n 대비) → `object_detection` 추론부 교체 → 텍스트 프롬프트 검출 시연.
  - go 조건: 4060 에서 real-time(≥~15 FPS (Disclosure)) + VRAM 여유 확인.
- **Phase B — grasp segmentation**
  - 대상: FastSAM(동일 스택) 우선, 정밀도 필요 시 MobileSAM/SAM2-tiny.
  - 작업: 검출 박스→mask→grasp pose. 실물 집기 정확도 A/B.
- **Phase C — VLM 데모(선택)**
  - 대상: Florence-2-base.
  - 작업: on-demand grounding/caption 데모, 음성 명령과 연계 PoC. 라이브 상주 아님.
- **각 phase 독립 go/no-go** — Phase A 실측이 real-time 미달이면 커리큘럼 도입 보류하고 on-demand 데모로 격하.

---

## 8. 리스크 & 미검증 항목

- **VRAM/지연 실측 부재 (Disclosure)** — 본 문서의 4060 수치는 전부 추정. 동시 상주(검출+seg+VLM) VRAM 초과 위험. → 파일럿 1단계 실측이 전제.
- **HF weight offline** — 교실 다수 학생기 동시 다운로드 = 대역폭·시간. 사전 캐시/미러 필요.
- **transformers 계열 laptop 지연** — Grounding DINO/VLM 은 4060 Laptop 실시간 불가 가능성 높음(Disclosure). on-demand 로 한정.
- **numpy<2 핀 충돌** — 신규 라이브러리가 numpy≥2 를 끌어오면 ultralytics 런타임 실패(기존 함정 재현). 도입마다 import 검증.
- **license** — YOLOE/YOLO-World/FastSAM = AGPL(이미 상속). Qwen2.5-VL-3B = Qwen license(재배포 조건 확인). 상업 배포 아닌 교육 용도면 대체로 무난하나 명시 필요.
- **범위 관리** — VLM 까지 한 번에 넣으면 수업 복잡도 급증. Phase A 단독으로도 도입 가치 충분 — 단계 분리 권장.

---

## 9. 부록

### 9-1. 현재 스택 요약 (Fact — repo)

| 항목 | 값 |
|---|---|
| ROS2 / Ubuntu | jazzy / 24.04 (noble) |
| 검출 | YOLOv8n, ultralytics 8.4.56 |
| torch / CUDA | 2.11.0+cu128 / 12.8 (컨테이너) |
| numpy | <2 (재핀) |
| 배포기 | RTX 4060 Laptop, 8GB VRAM |
| 음성 | GPT-4o (LangChain) |

### 9-2. 참고

- YOLO-World: https://docs.ultralytics.com/models/yolo-world · https://github.com/AILab-CVC/YOLO-World (CVPR 2024)
- YOLOE: https://docs.ultralytics.com/models/yoloe · https://github.com/THU-MIG/yoloe (ICCV 2025)
- Grounding DINO: https://huggingface.co/docs/transformers/model_doc/grounding-dino
- SAM2: https://github.com/facebookresearch/sam2 · MobileSAM: https://github.com/ChaoningZhang/MobileSAM · FastSAM: https://docs.ultralytics.com/models/fast-sam
- Florence-2: https://huggingface.co/microsoft/Florence-2-large (MIT)
- Qwen2.5-VL-3B: https://huggingface.co/Qwen/Qwen2.5-VL-3B-Instruct · Moondream2: https://huggingface.co/vikhyatk/moondream2
