#!/usr/bin/env python3
"""Minimal subscriber for /test/string, /test/int32, /test/twist. Logs each message."""
import rclpy
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from std_msgs.msg import String, Int32
from geometry_msgs.msg import Twist


class SimpleSubscriber(Node):
    def __init__(self):
        super().__init__('test_sub_simple')
        self.create_subscription(String, '/test/string', self.on_string, 10)
        self.create_subscription(Int32,  '/test/int32',  self.on_int,    10)
        self.create_subscription(Twist,  '/test/twist',  self.on_twist,  10)
        self.get_logger().info(
            'test_sub_simple started, listening on /test/string, /test/int32, /test/twist'
        )

    def on_string(self, msg):
        self.get_logger().info(f'/test/string: {msg.data!r}')

    def on_int(self, msg):
        self.get_logger().info(f'/test/int32: {msg.data}')

    def on_twist(self, msg):
        self.get_logger().info(
            f'/test/twist: linear.x={msg.linear.x:.3f}, angular.z={msg.angular.z:.3f}'
        )


def main():
    rclpy.init()
    node = SimpleSubscriber()
    try:
        rclpy.spin(node)
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    node.destroy_node()
    rclpy.try_shutdown()


if __name__ == '__main__':
    main()
