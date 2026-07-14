sudo apt update && sudo apt upgrade
sudo apt install zsh curl nano git dkms python-is-python3 terminator locales software-properties-common -y
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
cd ~/.oh-my-zsh/plugins
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git
git clone https://github.com/zsh-users/zsh-autosuggestions.git
echo "source ${(q-)PWD}/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" >> ${ZDOTDIR:-$HOME}/.zshrc
echo "source ${(q-)PWD}/zsh-autosuggestions/zsh-autosuggestions.zsh" >> ${ZDOTDIR:-$HOME}/.zshrc
sudo locale-gen en_US en_US.UTF-8
sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export LANG=en_US.UTF-8
sudo add-apt-repository universe -y
sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" | sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null
sudo apt install ros-humble-desktop ros-humble-ros-base ros-dev-tools -y
echo "source /opt/ros/humble/setup.zsh" >> ~/.zshrc
echo "alias cb='colcon build --symlink-install'" >> ~/.zshrc
echo "alias sc='source install/setup.zsh'" >> ~/.zshrc
source ~/.zshrc
sudo apt update && sudo apt install -y \
  python3-pip \
  python3-pytest-cov \
  ros-dev-tools
python3 -m pip install -U \
  flake8-blind-except \
  flake8-builtins \
  flake8-class-newline \
  flake8-comprehensions \
  flake8-deprecated \
  flake8-docstrings \
  flake8-import-order \
  flake8-quotes \
  pytest-repeat \
  pytest-rerunfailures \
  pytest \
  setuptools
sudo apt install python3-colcon-common-extensions -y
sudo git clone https://github.com/paroj/xpad.git /usr/src/xpad-0.4
sudo dkms install -m xpad -v 0.4
sudo echo 'KERNEL=="ttyACM[0-9]*", ACTION=="add", ATTRS{idVendor}=="15d1", MODE="0666", GROUP="dialout", SYMLINK+="sensors/hokuyo"' | sudo tee /etc/udev/rules.d/99-hokuyo.rules
sudo echo 'KERNEL=="ttyACM[0-9]*", ACTION=="add", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="5740", MODE="0666", GROUP="dialout", SYMLINK+="sensors/vesc"' | sudo tee /etc/udev/rules.d/99-vesc.rules
sudo echo 'KERNEL=="js[0-9]*", ACTION=="add", ATTRS{idVendor}=="046d", ATTRS{idProduct}=="c219", SYMLINK+="input/joypad-f710"' | sudo tee /etc/udev/rules.d/99-joypad-f710.rules
sudo udevadm control --reload-rules && sudo udevadm trigger
cd $HOME && mkdir -p f1tenth_ws/src
cd f1tenth_ws/src
git clone --branch humble-devel https://github.com/f1tenth/f1tenth_system.git
cd f1tenth_system
git submodule update --init --recursive --remote
cd $HOME/f1tenth_ws
rosdep update --include-eol --rosdistro=humble
rosdep install --include-eol --from-paths src -i -y --rosdistro=humble
sudo apt install ros-humble-asio-cmake-module
colcon build
echo "alias f110='cd \$HOME/f1tenth_ws && source install/setup.zsh && ros2 launch f1tenth_stack bringup_launch.py'" >> ~/.zshrc
sudo reboot
