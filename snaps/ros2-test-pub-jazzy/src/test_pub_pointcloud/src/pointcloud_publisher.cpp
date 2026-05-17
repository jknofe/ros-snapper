// 2048x2048 sensor_msgs/PointCloud2 at 10 Hz (~480 MB/s).
// Best-effort QoS - reliable would saturate retransmits; subscribers must
// match this QoS to receive.
#include "test_pub_pointcloud/pointcloud_publisher.hpp"

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <memory>

#include <rclcpp/rclcpp.hpp>
#include <sensor_msgs/msg/point_cloud2.hpp>
#include <sensor_msgs/msg/point_field.hpp>

using std::chrono::operator""ms;

namespace test_pub_pointcloud {

PointCloudPublisher::PointCloudPublisher()
    : rclcpp::Node("test_pub_pointcloud") {
  rclcpp::QoS qos(1);
  qos.best_effort().keep_last(1);
  pub_ = create_publisher<sensor_msgs::msg::PointCloud2>("/test/pointcloud", qos);

  build_template();
  timer_ = create_wall_timer(100ms, [this] { publish(); });

  const std::size_t mib = msg_.data.size() / (1024 * 1024);
  RCLCPP_INFO(get_logger(),
      "test_pub_pointcloud started: /test/pointcloud %ux%u (%zu MiB) @ 10 Hz",
      WIDTH, HEIGHT, mib);
}

void PointCloudPublisher::build_template() {
  msg_.header.frame_id = "test_pointcloud";
  msg_.height = HEIGHT;
  msg_.width = WIDTH;
  msg_.is_bigendian = false;
  msg_.point_step = POINT_STEP;
  msg_.row_step = WIDTH * POINT_STEP;
  msg_.is_dense = true;

  sensor_msgs::msg::PointField fx, fy, fz;
  fx.name = "x"; fx.offset = 0; fx.datatype = sensor_msgs::msg::PointField::FLOAT32; fx.count = 1;
  fy.name = "y"; fy.offset = 4; fy.datatype = sensor_msgs::msg::PointField::FLOAT32; fy.count = 1;
  fz.name = "z"; fz.offset = 8; fz.datatype = sensor_msgs::msg::PointField::FLOAT32; fz.count = 1;
  msg_.fields = {fx, fy, fz};

  const std::size_t total_bytes = static_cast<std::size_t>(HEIGHT) * msg_.row_step;
  msg_.data.assign(total_bytes, 0);

  float * p = reinterpret_cast<float *>(msg_.data.data());
  for (uint32_t row = 0; row < HEIGHT; ++row) {
    const float y = -1.0f + 2.0f * static_cast<float>(row) / static_cast<float>(HEIGHT - 1);
    for (uint32_t col = 0; col < WIDTH; ++col) {
      const float x = -1.0f + 2.0f * static_cast<float>(col) / static_cast<float>(WIDTH - 1);
      *p++ = x;
      *p++ = y;
      *p++ = 0.0f;
    }
  }
}

void PointCloudPublisher::publish() {
  ++count_;
  msg_.header.stamp = now();
  pub_->publish(msg_);
  if (count_ % 10 == 0) {
    RCLCPP_INFO(get_logger(), "pointcloud #%lu", static_cast<unsigned long>(count_));
  }
}

}  // namespace test_pub_pointcloud


int main(int argc, char ** argv) {
  rclcpp::init(argc, argv);
  rclcpp::spin(std::make_shared<test_pub_pointcloud::PointCloudPublisher>());
  rclcpp::shutdown();
  return 0;
}
