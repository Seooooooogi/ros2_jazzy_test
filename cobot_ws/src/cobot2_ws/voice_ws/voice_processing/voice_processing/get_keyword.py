# ros2 service call /get_keyword std_srvs/srv/Trigger "{}"

import os
import time
import rclpy
from rclpy.node import Node

# wakeword 대기 상한(초). robot_control 이 wakeword 대기 중 종료(Ctrl+C)되면 서버 핸들러는
# 계속 돌아 좀비로 큐에 남고, 다음 요청이 그 뒤로 밀려 응답이 어긋난다. 상한을 둬 버려진
# 요청이 스스로 해제되게 한다 — 미감지 시 success=False 로 반환하면 client 가 재호출한다.
WAKEWORD_TIMEOUT = 30.0

from ament_index_python.packages import get_package_share_directory
from dotenv import load_dotenv
from langchain_openai import ChatOpenAI
from langchain_core.prompts import PromptTemplate  # langchain 0.3+ 에서 langchain.prompts 제거됨
# from langchain.chains import LLMChain

from std_srvs.srv import Trigger
from std_msgs.msg import Bool

from voice_processing.wakeup_word import WakeupWord
from voice_processing.stt import STT

############ Package Path & Environment Setting ############

#----------------------------------------------------------------
# current_dir = os.getcwd()
# package_path = get_package_share_directory("pick_and_place_voice")

# env_path = "/home/rokey/cobot_ws/src/cobot2_ws/pick_and_place_voice/resource/.env"
# load_dotenv(dotenv_path=env_path)
# is_load = load_dotenv(dotenv_path=os.path.join(f"{package_path}/resource/.env"))
# openai_api_key = os.getenv("OPENAI_API_KEY")
#-----------------------------------------------------------------

PACKAGE_NAME = "voice_processing"
PACKAGE_PATH = get_package_share_directory(PACKAGE_NAME)
RESOURCE_PATH = os.path.join(PACKAGE_PATH, "resource")
ENV_PATH = os.path.join(RESOURCE_PATH, ".env")
load_dotenv(dotenv_path=ENV_PATH)
openai_api_key = os.getenv("OPENAI_API_KEY")

############ AI Processor ############
# class AIProcessor:
#     def __init__(self):



############ GetKeyword Node ############
class GetKeyword(Node):
    def __init__(self):

        print(PACKAGE_PATH, RESOURCE_PATH, ENV_PATH)

        self.llm = ChatOpenAI(
            model="gpt-4o", temperature=0.5, openai_api_key=openai_api_key
        )

        prompt_content = """
            당신은 사용자의 문장에서 특정 도구와 목적지를 추출해야 합니다.

            <목표>
            - 문장에서 다음 리스트에 포함된 도구를 최대한 정확히 추출하세요.
            - 문장에 등장하는 도구의 목적지(어디로 옮기라고 했는지)도 함께 추출하세요.

            <도구 리스트>
            - hammer, screwdriver, wrench, pos1, pos2, pos3

            <출력 형식>
            - 다음 형식을 반드시 따르세요: [도구1 도구2 ... / pos1 pos2 ...]
            - 도구와 위치는 각각 공백으로 구분
            - 도구가 없으면 앞쪽은 공백 없이 비우고, 목적지가 없으면 '/' 뒤는 공백 없이 비웁니다.
            - 도구와 목적지의 순서는 등장 순서를 따릅니다.

            <특수 규칙>
            - 명확한 도구 명칭이 없지만 문맥상 유추 가능한 경우(예: "못 박는 것" → hammer)는 리스트 내 항목으로 최대한 추론해 반환하세요.
            - 다수의 도구와 목적지가 동시에 등장할 경우 각각에 대해 정확히 매칭하여 순서대로 출력하세요.

            <예시>
            - 입력: "hammer를 pos1에 가져다 놔"  
            출력: hammer / pos1

            - 입력: "왼쪽에 있는 해머와 wrench를 pos1에 넣어줘"  
            출력: hammer wrench / pos1

            - 입력: "왼쪽에 있는 hammer를줘"  
            출력: hammer /

            - 입력: "왼쪽에 있는 못 박을 수 있는것을 줘"  
            출력: hammer /

            - 입력: "hammer는 pos2에 두고 screwdriver는 pos1에 둬"  
            출력: hammer screwdriver / pos2 pos1

            <사용자 입력>
            "{user_input}"                
        """

        self.prompt_template = PromptTemplate(
            input_variables=["user_input"], template=prompt_content
        )
        self.lang_chain = self.prompt_template | self.llm
        # self.lang_chain = LLMChain(llm=self.llm, prompt=self.prompt_template)
        self.stt = STT(openai_api_key=openai_api_key)


        super().__init__("get_keyword_node")

        self.get_logger().info("MicRecorderNode initialized.")
        self.get_logger().info("wait for client's request...")
        self.get_keyword_srv = self.create_service(
            Trigger, "get_keyword", self.get_keyword
        )
        # 서비스는 최종 키워드만 반환한다. wakeword 감지 순간을 외부(robot_control)에서
        # 확인할 수 있도록 별도 토픽으로 그 이벤트를 알린다.
        self.wakeword_pub = self.create_publisher(Bool, "/wakeword_detected", 10)
        self.wakeup_word = WakeupWord()

    def extract_keyword(self, output_message):  # d2 이 함수 일부 수정함
        response = self.lang_chain.invoke({"user_input": output_message})
        result = response.content

        object, target = result.strip().split("/")

        object = object.split()
        target = target.split()

        print(f"object: {object}")
        print(f"target: {target}")
        # 도구와 목적지를 함께 반환한다. robot_control 이 "도구... / 목적지..." 로 파싱해
        # 각 도구를 집어 같은 순서의 목적지(pos1/2/3)에 놓는다. 목적지를 버리면 놓기 불가.
        return " ".join(object) + " / " + " ".join(target)
    
    def get_keyword(self, request, response):  # 요청과 응답 객체를 받아야 함    # d2 이 함수 일부 수정함
        try:
            print("open stream")
            self.wakeup_word.open()
        except Exception as e:
            self.get_logger().error(f"Error: Failed to open audio stream: {e}")
            return None

        detected = False
        try:
            t0 = time.monotonic()
            while time.monotonic() - t0 < WAKEWORD_TIMEOUT:
                if self.wakeup_word.is_wakeup():
                    detected = True
                    break
        finally:
            # wakeword 스트림과 STT(sd.rec) 가 같은 입력장치를 쓰므로, STT 전에 반드시 닫는다.
            self.wakeup_word.close()

        if not detected:
            self.get_logger().warn("wakeword timeout — no detection, returning failure")
            response.success = False
            response.message = ""
            return response

        # wakeword 감지를 외부에 알린다 (robot_control 이 대기 중 수신해 로깅).
        self.wakeword_pub.publish(Bool(data=True))

        # STT --> Keword Extract --> Embedding
        output_message = self.stt.speech2text()
        keyword = self.extract_keyword(output_message)

        self.get_logger().warn(f"Detected tools/targets: {keyword}")

        # 응답 객체 설정
        response.success = True
        response.message = keyword  # "도구... / 목적지..." 문자열 그대로 전달
        return response


def main():  # d2 메인문 일부 수정
    rclpy.init()
    node = GetKeyword()
    rclpy.spin(node)
    node.destroy_node()
    rclpy.shutdown()


if __name__ == "__main__":
    main()
