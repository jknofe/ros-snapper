#pragma once

#include <cstdint>

#include <rclcpp/rclcpp.hpp>
#include <sensor_msgs/msg/point_cloud2.hpp>

namespace test_sub_pointcloud {

class PointCloudSubscriber : public rclcpp::Node {
public:
  PointCloudSubscriber();

private:
  void on_message(const sensor_msgs::msg::PointCloud2 & msg);

  rclcpp::Subscription<sensor_msgs::msg::PointCloud2>::SharedPtr sub_;
  uint64_t count_ = 0;
};

}  // namespace test_sub_pointcloud
