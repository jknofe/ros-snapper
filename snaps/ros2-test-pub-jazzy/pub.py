#!/usr/bin/env python3
import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, HistoryPolicy
from std_msgs.msg import String, Int32
from geometry_msgs.msg import Twist
from sensor_msgs.msg import PointCloud2, PointField
import numpy as np


POINT_CLOUD_WIDTH = 2048
POINT_CLOUD_HEIGHT = 2048


def build_point_cloud_template():
    # 2048*2048 = 4_194_304 points * 12 bytes (XYZ float32) = 48 MiB.
    # Built once at startup so the publisher only pays serialisation per tick.
    xs, ys = np.meshgrid(
        np.linspace(-1.0, 1.0, POINT_CLOUD_WIDTH, dtype=np.float32),
        np.linspace(-1.0, 1.0, POINT_CLOUD_HEIGHT, dtype=np.float32),
        indexing='xy',
    )
    points = np.empty((POINT_CLOUD_WIDTH * POINT_CLOUD_HEIGHT, 3), dtype=np.float32)
    points[:, 0] = xs.ravel()
    points[:, 1] = ys.ravel()
    points[:, 2] = 0.0
    return points


def make_point_cloud_msg(points, frame_id):
    msg = PointCloud2()
    msg.header.frame_id = frame_id
    msg.height = POINT_CLOUD_HEIGHT
    msg.width = POINT_CLOUD_WIDTH
    msg.fields = [
        PointField(name='x', offset=0, datatype=PointField.FLOAT32, count=1),
        PointField(name='y', offset=4, datatype=PointField.FLOAT32, count=1),
        PointField(name='z', offset=8, datatype=PointField.FLOAT32, count=1),
    ]
    msg.is_bigendian = False
    msg.point_step = 12
    msg.row_step = POINT_CLOUD_WIDTH * 12
    msg.is_dense = True
    msg.data = points.tobytes()
    return msg


class TestPublisher(Node):
    def __init__(self):
        super().__init__('ros2_test_pub')

        self.pub_str   = self.create_publisher(String, '/test/string', 10)
        self.pub_int   = self.create_publisher(Int32,  '/test/int32',  10)
        self.pub_twist = self.create_publisher(Twist,  '/test/twist',  10)

        # ~480 MB/s on /test/pointcloud. Reliable QoS would saturate
        # retransmits; subscribers must use the same QoS to receive.
        pc_qos = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=1,
        )
        self.pub_pc = self.create_publisher(PointCloud2, '/test/pointcloud', pc_qos)

        self.points = build_point_cloud_template()
        self.pc_msg = make_point_cloud_msg(self.points, 'test_pointcloud')

        self.create_timer(1.0, self.publish_low_rate)
        self.create_timer(0.1, self.publish_point_cloud)

        self.count = 0
        self.pc_count = 0

        mib = len(self.pc_msg.data) // (1024 * 1024)
        self.get_logger().info(
            f'ros2-test-pub started: /test/string|int32|twist @ 1 Hz, '
            f'/test/pointcloud {POINT_CLOUD_WIDTH}x{POINT_CLOUD_HEIGHT} '
            f'({mib} MiB) @ 10 Hz'
        )

    def publish_low_rate(self):
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

    def publish_point_cloud(self):
        self.pc_count += 1
        self.pc_msg.header.stamp = self.get_clock().now().to_msg()
        self.pub_pc.publish(self.pc_msg)
        if self.pc_count % 10 == 0:
            self.get_logger().info(f'pointcloud #{self.pc_count}')


def main():
    rclpy.init()
    node = TestPublisher()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
