// Subscribes to /test/pointcloud and logs metadata of every 10th message.
// QoS must match the publisher (best-effort + depth 1) or DDS silently drops
// the subscription as incompatible.
#include "test_sub_pointcloud/pointcloud_subscriber.hpp"

#include <cstddef>
#include <cstdint>
#include <memory>

#include <rclcpp/rclcpp.hpp>
#include <sensor_msgs/msg/point_cloud2.hpp>

namespace test_sub_pointcloud {

PointCloudSubscriber::PointCloudSubscriber()
    : rclcpp::Node("test_sub_pointcloud") {
  rclcpp::QoS qos(1);
  qos.best_effort().keep_last(1);
  sub_ = create_subscription<sensor_msgs::msg::PointCloud2>(
      "/test/pointcloud", qos,
      [this](const sensor_msgs::msg::PointCloud2 & msg) { on_message(msg); });

  RCLCPP_INFO(get_logger(), "test_sub_pointcloud started, listening on /test/pointcloud");
}

void PointCloudSubscriber::on_message(const sensor_msgs::msg::PointCloud2 & msg) {
  ++count_;
  if (count_ == 1 || count_ % 10 == 0) {
    const std::size_t mib = msg.data.size() / (1024 * 1024);
    const std::size_t points = static_cast<std::size_t>(msg.width) * msg.height;
    RCLCPP_INFO(get_logger(),
        "/test/pointcloud #%lu: %ux%u (%zu points, %zu MiB)",
        static_cast<unsigned long>(count_),
        msg.width, msg.height, points, mib);
  }
}

}  // namespace test_sub_pointcloud


int main(int argc, char ** argv) {
  rclcpp::init(argc, argv);
  rclcpp::spin(std::make_shared<test_sub_pointcloud::PointCloudSubscriber>());
  rclcpp::shutdown();
  return 0;
}
