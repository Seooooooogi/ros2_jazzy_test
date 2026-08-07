#!/usr/bin/env python3
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# scripts/dds_probe_nodes.py — DDS 구성별 대용량 토픽 손실률을 재는 발행/수신 노드.
#
# RealSense 실기 없이 같은 크기의 이미지를 합성한다. QoS 는 카메라와 같은
# best-effort 로 둔다 — reliable 로 두면 재전송이 손실을 가려 측정이 무의미해진다.
# 시퀀스 번호는 header.frame_id 에 문자열로 싣는다(ROS 2 의 Header 에는 seq 필드가 없다).

import argparse
import sys

SEQ_PREFIX = "seq:"


def drop_stats(seqs):
    """수신한 시퀀스 목록에서 (수신 수, 기대 수, 손실률 %) 를 낸다.

    기대 수는 관측된 최소~최대 구간의 길이다. 발행 시작 전/종료 후 구간은
    측정 대상이 아니므로 제외된다.
    """
    if not seqs:
        return 0, 0, 100.0
    received = len(set(seqs))
    expected = max(seqs) - min(seqs) + 1
    drop_pct = 0.0 if expected <= 0 else (1.0 - received / expected) * 100.0
    return received, expected, round(drop_pct, 3)


def _self_test():
    assert drop_stats([]) == (0, 0, 100.0)
    assert drop_stats([0, 1, 2]) == (3, 3, 0.0)
    assert drop_stats([0, 2]) == (2, 3, 33.333)
    assert drop_stats([5]) == (1, 1, 0.0)
    assert drop_stats([10, 11, 12, 12]) == (3, 3, 0.0)   # 중복 수신은 손실이 아니다
    print("self-test OK")


def _make_image(width, height, seq):
    from sensor_msgs.msg import Image
    msg = Image()
    msg.header.frame_id = f"{SEQ_PREFIX}{seq}"
    msg.height = height
    msg.width = width
    msg.encoding = "bgr8"
    msg.is_bigendian = 0
    msg.step = width * 3
    msg.data = bytes(width * height * 3)
    return msg


def _talk(args):
    import rclpy
    from rclpy.qos import qos_profile_sensor_data
    from sensor_msgs.msg import Image

    rclpy.init()
    node = rclpy.create_node("dds_probe_talker")
    pub = node.create_publisher(Image, args.topic, qos_profile_sensor_data)
    state = {"seq": 0}

    def tick():
        pub.publish(_make_image(args.width, args.height, state["seq"]))
        state["seq"] += 1

    node.create_timer(1.0 / args.hz, tick)
    print(f"talking on {args.topic} at {args.hz}Hz "
          f"({args.width}x{args.height} bgr8, {args.width * args.height * 3} bytes/frame)",
          flush=True)
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        rclpy.shutdown()


def _listen(args):
    import time
    import rclpy
    from rclpy.qos import qos_profile_sensor_data
    from sensor_msgs.msg import Image

    rclpy.init()
    node = rclpy.create_node("dds_probe_listener")
    seqs = []

    def cb(msg):
        fid = msg.header.frame_id
        if fid.startswith(SEQ_PREFIX):
            seqs.append(int(fid[len(SEQ_PREFIX):]))

    node.create_subscription(Image, args.topic, cb, qos_profile_sensor_data)

    deadline = time.monotonic() + args.sec
    while rclpy.ok() and time.monotonic() < deadline:
        rclpy.spin_once(node, timeout_sec=0.1)
    rclpy.shutdown()

    received, expected, drop_pct = drop_stats(seqs)
    hz = round(received / args.sec, 2) if args.sec > 0 else 0.0
    print(f"RESULT received={received} expected={expected} drop_pct={drop_pct} hz={hz}", flush=True)
    return 0


def main():
    parser = argparse.ArgumentParser(description="DDS 구성별 대용량 토픽 손실률 측정")
    parser.add_argument("--self-test", action="store_true", help="ROS 없이 계산 로직만 검증")
    sub = parser.add_subparsers(dest="mode")

    p_talk = sub.add_parser("talk")
    p_talk.add_argument("--hz", type=float, default=30.0)
    p_talk.add_argument("--width", type=int, default=1920)
    p_talk.add_argument("--height", type=int, default=1080)
    p_talk.add_argument("--topic", default="/dds_probe/image")

    p_listen = sub.add_parser("listen")
    p_listen.add_argument("--sec", type=float, default=30.0)
    p_listen.add_argument("--topic", default="/dds_probe/image")

    args = parser.parse_args()
    if args.self_test:
        _self_test()
        return 0
    if args.mode == "talk":
        return _talk(args)
    if args.mode == "listen":
        return _listen(args)
    parser.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
