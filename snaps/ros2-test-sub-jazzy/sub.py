#!/usr/bin/env python3
import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, HistoryPolicy
from std_msgs.msg import String, Int32
from geometry_msgs.msg import Twist
from sensor_msgs.msg import PointCloud2


class TestSubscriber(Node):
    def __init__(self):
        super().__init__('ros2_test_sub')

        self.create_subscription(String, '/test/string', self.on_string, 10)
        self.create_subscription(Int32,  '/test/int32',  self.on_int,    10)
        self.create_subscription(Twist,  '/test/twist',  self.on_twist,  10)

        # Must match the publisher's QoS or no messages will be delivered.
        pc_qos = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=1,
        )
        self.create_subscription(PointCloud2, '/test/pointcloud', self.on_pointcloud, pc_qos)

        self.pc_count = 0
        self.get_logger().info(
            'ros2-test-sub started, listening on /test/string, /test/int32, /test/twist, /test/pointcloud'
        )

    def on_string(self, msg):
        self.get_logger().info(f'/test/string: {msg.data!r}')

    def on_int(self, msg):
        self.get_logger().info(f'/test/int32: {msg.data}')

    def on_twist(self, msg):
        self.get_logger().info(
            f'/test/twist: linear.x={msg.linear.x:.3f}, angular.z={msg.angular.z:.3f}'
        )

    def on_pointcloud(self, msg):
        # 10 Hz * ~48 MiB would flood the log if printed per message. Log
        # the first arrival and then every 10th (~1 line/sec).
        self.pc_count += 1
        if self.pc_count == 1 or self.pc_count % 10 == 0:
            mib = len(msg.data) // (1024 * 1024)
            self.get_logger().info(
                f'/test/pointcloud #{self.pc_count}: {msg.width}x{msg.height} '
                f'({msg.width * msg.height} points, {mib} MiB)'
            )


def main():
    rclpy.init()
    node = TestSubscriber()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
