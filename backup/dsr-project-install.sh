mkdir -p ~/cobot_ws/src

cd ~/cobot_ws/src
git clone -b humble https://github.com/doosan-robotics/doosan-robot2.git
cd ~/cobot_ws/src

sudo apt update
sudo apt install -y \
    ros-humble-xacro \
    ros-humble-rclpy \
    ros-humble-std-msgs \
    ros-humble-joint-state-publisher-gui \
    ros-humble-launch-ros \
    ros-humble-rosgraph-msgs \
    ros-humble-ament-cmake \
    ros-humble-ament-pep257 \
    ros-humble-ament-index-cpp \
    ros-humble-ament-lint-common \
    ros-humble-moveit-msgs \
    ros-humble-velocity-controllers \
    ros-humble-yaml-cpp-vendor \
    ros-humble-eigen3-cmake-module \
    ros-humble-ros2launch


if [ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]; then
    sudo rosdep init
fi
rosdep update

rosdep install -r --from-paths . --ignore-src --rosdistro $ROS_DISTRO -y

cd ~/cobot_ws/src/doosan-robot2
chmod +x ./install_emulator.sh
sudo ./install_emulator.sh

cd ~/cobot_ws
source /opt/ros/humble/setup.bash
export ROS_DISTRO=humble
rm -rf build install log
colcon build

. install/setup.bash

# 만약 colcon build에서 warning(*error 발생은 안됨) 발생 시, 다시 colcon build

#echo 'export PYTHONPATH=$PYTHONPATH:~/cobot_ws/install/dsr_common2/lib/dsr_common2/imp' >> ~/.bashrc
#source ~/.bashrc
