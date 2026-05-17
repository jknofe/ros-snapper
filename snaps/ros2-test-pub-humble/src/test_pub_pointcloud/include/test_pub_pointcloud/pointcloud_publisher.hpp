#pragma once

#include <cstdint>

#include <rclcpp/rclcpp.hpp>
#include <sensor_msgs/msg/point_cloud2.hpp>

namespace test_pub_pointcloud {

class PointCloudPublisher : public rclcpp::Node {
public:
  static constexpr uint32_t WIDTH = 2048;
  static constexpr uint32_t HEIGHT = 2048;
  static constexpr uint32_t POINT_STEP = 12;  // XYZ float32

  PointCloudPublisher();

private:
  void build_template();
  void publish();

  rclcpp::Publisher<sensor_msgs::msg::PointCloud2>::SharedPtr pub_;
  rclcpp::TimerBase::SharedPtr timer_;
  sensor_msgs::msg::PointCloud2 msg_;
  uint64_t count_ = 0;
};

}  // namespace test_pub_pointcloud
