#!/usr/bin/env python3
"""Minimal publisher for /test/string, /test/int32, /test/twist at 1 Hz."""
import rclpy
from rclpy.node import Node
from std_msgs.msg import String, Int32
from geometry_msgs.msg import Twist


class SimplePublisher(Node):
    def __init__(self):
        super().__init__('test_pub_simple')
        self.pub_str   = self.create_publisher(String, '/test/string', 10)
        self.pub_int   = self.create_publisher(Int32,  '/test/int32',  10)
        self.pub_twist = self.create_publisher(Twist,  '/test/twist',  10)
        self.create_timer(1.0, self.tick)
        self.count = 0
        self.get_logger().info(
            'test_pub_simple started: publishing /test/string, /test/int32, /test/twist at 1 Hz'
        )

    def tick(self):
        self.count += 1

        msg = String()
        msg.data = f'hello from test snap #{self.count}'
        self.pub_str.publish(msg)

        msg2 = Int32()
        msg2.data = self.count
        self.pub_int.publish(msg2)

        msg3 = Twist()
        msg3.linear.x  = self.count * 0.1
        msg3.angular.z = 0.5
        self.pub_twist.publish(msg3)

        self.get_logger().info(f'published #{self.count}')


def main():
    rclpy.init()
    node = SimplePublisher()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
