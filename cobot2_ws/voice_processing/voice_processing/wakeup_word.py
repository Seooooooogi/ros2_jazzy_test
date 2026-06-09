import os
import numpy as np
import sounddevice as sd
from openwakeword.model import Model
from ament_index_python.packages import get_package_share_directory

PACKAGE_NAME = "voice_processing"
PACKAGE_PATH = get_package_share_directory(PACKAGE_NAME)

MODEL_NAME = "hello_rokey_8332_32.tflite"
MODEL_PATH = os.path.join(PACKAGE_PATH, f"resource/{MODEL_NAME}")

# openwakeword 는 16kHz int16 / 80ms(=1280 샘플) 프레임 단위로 streaming inference 한다.
SAMPLE_RATE = 16000
FRAME = 1280


class WakeupWord:
    # sounddevice 로 16kHz 를 직접 캡처한다. 과거엔 PyAudio 로 48kHz 를 받아 scipy.signal.resample
    # 로 16kHz 변환했는데, (1) 이 하드웨어의 디지털 마이크(DMIC)는 PyAudio 로 캡처되지 않고(무음),
    # (2) 입력이 풀스케일 근처면 resample 의 anti-aliasing 필터가 int16 범위를 넘겨 오버플로 →
    # openwakeword feature 가 왜곡돼 탐지가 실패했다. 16kHz 직접 캡처로 두 문제를 모두 제거한다.
    def __init__(self):
        self.model = None
        self.model_name = MODEL_NAME.split(".", maxsplit=1)[0]
        self.stream = None

    def is_wakeup(self):
        audio_chunk, _ = self.stream.read(FRAME)  # (FRAME, 1) int16
        audio_chunk = audio_chunk.flatten()
        confidence = self.model.predict(audio_chunk)[self.model_name]
        print("confidence: ", confidence)
        if confidence > 0.3:
            print("Wakeword detected!")
            return True
        return False

    def open(self):
        self.model = Model(wakeword_models=[MODEL_PATH])
        self.stream = sd.InputStream(
            samplerate=SAMPLE_RATE, channels=1, dtype="int16", blocksize=FRAME
        )
        self.stream.start()

    def close(self):
        if self.stream is not None:
            self.stream.stop()
            self.stream.close()
            self.stream = None
