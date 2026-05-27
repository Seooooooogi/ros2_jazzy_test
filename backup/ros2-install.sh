sudo apt update && sudo apt upgrade -y
sudo apt install git

# 권한부여 
chmod +x ./resources/ros2-humble-desktop-main.sh

# ros-2 설치 
./resources/ros2-humble-desktop-main.sh

export CMAKE_PREFIX_PATH=/opt/ros/humble:${CMAKE_PREFIX_PATH}

### Prerequisite installation elements before package installation
sudo apt update && sudo apt upgrade -y

sudo apt-get install -y libpoco-dev libyaml-cpp-dev
sudo apt-get install -y ros-humble-control-msgs ros-humble-realtime-tools ros-humble-xacro ros-humble-joint-state-publisher-gui ros-humble-ros2-control ros-humble-ros2-controllers ros-humble-gazebo-msgs ros-humble-moveit-msgs dbus-x11

sudo apt install -y \
  ros-humble-ament-lint-common \
  ros-humble-yaml-cpp-vendor \
  ros-humble-ros2launch \
  ros-humble-ament-pep257

### install gazebo sim
sudo sh -c 'echo "deb http://packages.osrfoundation.org/gazebo/ubuntu-stable `lsb_release -cs` main" > /etc/apt/sources.list.d/gazebo-stable.list'
wget http://packages.osrfoundation.org/gazebo.key -O - | sudo apt-key add -
sudo apt update && sudo apt upgrade -y
sudo apt-get install -y libignition-gazebo6-dev
sudo apt-get install -y ros-humble-gazebo-ros-pkgs ros-humble-moveit-msgs ros-humble-ros-gz-sim

