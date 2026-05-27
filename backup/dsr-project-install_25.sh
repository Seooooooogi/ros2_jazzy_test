# mkdir -p ~/ros2_ws/src   => 변경: 주석처리

# cd ~/ros2_ws/src   => 변경: 주석처리
# git clone https://github.com/ROKEY-SPARK/DoosanBootcampCol2#    => 변경: 주석처리
# git clone -b humble https://github.com/ros-controls/gz_ros2_control
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
#   => 위에 줄 추가함

chmod +x ./install_emulator.sh
./install_emulator.sh
cd ~/cobot_ws
source /opt/ros/humble/setup.bash
export ROS_DISTRO=humble
colcon build

# 만약 colcon build에서 warning(*error 발생은 안됨) 발생 시, 다시 colcon build

. install/setup.bash
echo 'export PYTHONPATH=$PYTHONPATH:~/cobot_ws/install/dsr_common2/lib/dsr_common2/imp' >> ~/.bashrc
source ~/.bashrc