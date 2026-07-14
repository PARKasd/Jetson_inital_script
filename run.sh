#!/usr/bin/env bash
#
# F1TENTH 환경 셋업 (Ubuntu 22.04 / ROS2 Humble)
# 실행: bash setup.sh      <- sudo 붙이지 말 것 (workspace root 소유 방지)
#
set -euo pipefail

### 0. sudo keep-alive ###########################################
# 앞에서 한 번 인증, 백그라운드로 timestamp 갱신 -> 뒤쪽 apt purge 등에서 재입력 방지
sudo -v
( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT

PLUGINS_DIR="$HOME/.oh-my-zsh/plugins"

### 0.5 Jetson 파워 프로파일 최대 ################################
# nvpmodel -m 2 = MAXN(이 보드 기준), jetson_clocks = 클럭 최대 고정
# 빌드도 최대 성능으로 -> colcon build 시간 단축. Jetson 아니면 스킵.
if command -v nvpmodel >/dev/null 2>&1; then
  sudo nvpmodel -m 2 || echo "WARN: nvpmodel -m 2 실패 (보드별 최대 모드 번호 확인: sudo nvpmodel -q)"
  sudo jetson_clocks || echo "WARN: jetson_clocks 실패"
  echo "Jetson power profile -> MAXN + jetson_clocks"
else
  echo "nvpmodel 없음 -> Jetson 파워 프로파일 스킵"
fi

### 1. base packages #############################################
sudo apt update && sudo apt upgrade -y
sudo apt install -y \
  zsh curl nano git dkms python-is-python3 terminator \
  locales software-properties-common

# kernel headers (Jetson/Tegra 대응)
# Tegra 커널 헤더는 일반 ubuntu 저장소에 없음(=linux-headers-*-tegra). 보통 L4T에 이미 있음.
# 있으면 스킵, 없으면 L4T 헤더 시도, 그래도 없으면 경고만 (xpad DKMS optional)
if [ ! -d "/lib/modules/$(uname -r)/build" ]; then
  sudo apt install -y nvidia-l4t-kernel-headers 2>/dev/null \
    || sudo apt install -y "linux-headers-$(uname -r)" 2>/dev/null \
    || echo "WARN: 커널 헤더 못 찾음 -> xpad DKMS 스킵될 수 있음"
fi

### 2. oh-my-zsh (unattended) ####################################
# RUNZSH=no  -> 설치 끝에 exec zsh 안 함 (스크립트 안 멈춤)
# CHSH=no    -> 여기서 default shell 안 바꿈 (아래서 non-interactive로 처리)
RUNZSH=no CHSH=no sh -c \
  "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
  "" --unattended

### 3. zsh plugins ###############################################
# 재실행 대비: 이미 있으면 clone 스킵 (git clone은 디렉토리 있으면 실패 -> set -e로 죽음)
[ -d "$PLUGINS_DIR/zsh-syntax-highlighting" ] || \
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$PLUGINS_DIR/zsh-syntax-highlighting"
[ -d "$PLUGINS_DIR/zsh-autosuggestions" ] || \
  git clone https://github.com/zsh-users/zsh-autosuggestions.git "$PLUGINS_DIR/zsh-autosuggestions"

# 절대경로로 source (bash에서 실행되므로 ${(q-)PWD} 같은 zsh 확장 금지)
# grep 가드로 중복 append 방지 (재실행 안전)
grep -qF "zsh-syntax-highlighting.zsh" "$HOME/.zshrc" || \
  echo "source $PLUGINS_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" >> "$HOME/.zshrc"
grep -qF "zsh-autosuggestions.zsh" "$HOME/.zshrc" || \
  echo "source $PLUGINS_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh" >> "$HOME/.zshrc"

### 3.5 default shell -> zsh #####################################
# 이 시점에 zsh/oh-my-zsh/plugins/.zshrc 다 준비됨.
# 뒤쪽 colcon build/외부 다운로드가 실패해도 zsh 환경은 확정되도록 여기서 처리.
ZSH_BIN="$(command -v zsh)"
# chsh는 대상 셸이 /etc/shells 에 있어야 동작 -> 없으면 추가
grep -qxF "$ZSH_BIN" /etc/shells || echo "$ZSH_BIN" | sudo tee -a /etc/shells > /dev/null
# 기본 로그인 셸 변경 (chsh 실패 시 usermod 폴백)
sudo chsh -s "$ZSH_BIN" "$USER" || sudo usermod -s "$ZSH_BIN" "$USER"
echo "default shell -> $ZSH_BIN (다음 로그인부터 적용)"

### 4. locale ####################################################
sudo locale-gen en_US en_US.UTF-8
sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export LANG=en_US.UTF-8

### 5. ROS2 Humble ###############################################
sudo add-apt-repository universe -y
sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
  -o /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo "$UBUNTU_CODENAME") main" \
  | sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null
sudo apt update
sudo apt install -y ros-humble-desktop ros-humble-ros-base ros-dev-tools

{
  echo "source /opt/ros/humble/setup.zsh"
  echo "alias cb='colcon build --symlink-install'"
  echo "alias sc='source install/setup.zsh'"
} >> "$HOME/.zshrc"

# 이 bash 세션에서 이후 colcon/rosdep 쓰려면 bash용 setup 을 source
# ROS setup 스크립트는 set -u 안전하지 않음(AMENT_TRACE_SETUP_FILES 등 unbound 참조)
# -> source 동안만 nounset 끔
set +u
# shellcheck disable=SC1091
source /opt/ros/humble/setup.bash
set -u

### 6. dev / lint deps ###########################################
sudo apt install -y python3-pip python3-pytest-cov ros-dev-tools
python3 -m pip install -U \
  flake8-blind-except flake8-builtins flake8-class-newline \
  flake8-comprehensions flake8-deprecated flake8-docstrings \
  flake8-import-order flake8-quotes \
  pytest-repeat pytest-rerunfailures pytest setuptools
sudo apt install -y python3-colcon-common-extensions

### 7. xpad (F710 XInput / Xbox 패드) DKMS #######################
# 헤더 없으면 빌드 실패하므로 non-fatal 처리 (|| true)
if [ -d "/lib/modules/$(uname -r)/build" ]; then
  if [ ! -d /usr/src/xpad-0.4 ]; then
    sudo git clone https://github.com/paroj/xpad.git /usr/src/xpad-0.4
  fi
  sudo dkms install -m xpad -v 0.4 || echo "WARN: xpad DKMS 실패 -> 헤더/커널 확인 필요"
else
  echo "WARN: 커널 헤더 없음 -> xpad DKMS 스킵"
fi

### 8. udev rules (Hokuyo / VESC / F710) #########################
# 'sudo echo' 은 무의미(리다이렉트는 유저 셸에서 실행) -> tee 만 sudo
echo 'KERNEL=="ttyACM[0-9]*", ACTION=="add", ATTRS{idVendor}=="15d1", MODE="0666", GROUP="dialout", SYMLINK+="sensors/hokuyo"' \
  | sudo tee /etc/udev/rules.d/99-hokuyo.rules > /dev/null
echo 'KERNEL=="ttyACM[0-9]*", ACTION=="add", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="5740", MODE="0666", GROUP="dialout", SYMLINK+="sensors/vesc"' \
  | sudo tee /etc/udev/rules.d/99-vesc.rules > /dev/null
echo 'KERNEL=="js[0-9]*", ACTION=="add", ATTRS{idVendor}=="046d", ATTRS{idProduct}=="c219", SYMLINK+="input/joypad-f710"' \
  | sudo tee /etc/udev/rules.d/99-joypad-f710.rules > /dev/null
sudo udevadm control --reload-rules && sudo udevadm trigger

### 9. f1tenth_system workspace ##################################
mkdir -p "$HOME/f1tenth_ws/src"
cd "$HOME/f1tenth_ws/src"
if [ ! -d f1tenth_system ]; then
  git clone --branch humble-devel https://github.com/f1tenth/f1tenth_system.git
fi
cd f1tenth_system
git submodule update --init --recursive --remote

cd "$HOME/f1tenth_ws"
# rosdep init 최초 1회 (이미 되어있으면 무시)
sudo rosdep init 2>/dev/null || true
rosdep update --include-eol --rosdistro=humble
rosdep install --include-eol --from-paths src -i -y --rosdistro=humble
sudo apt install -y ros-humble-asio-cmake-module
colcon build

echo "alias f110='cd \$HOME/f1tenth_ws && source install/setup.zsh && ros2 launch f1tenth_stack bringup_launch.py'" >> "$HOME/.zshrc"

### 10. vesc_tool ################################################
# 주의: file.garden 외부 호스팅. 죽으면 여기서 실패하니 신뢰성 필요하면 미러 권장.
curl -fsSL https://file.garden/acKoL5EeCA54DUAN/vesc_tool_7.00 -o "$HOME/vesctool"
chmod +x "$HOME/vesctool"

### 11. bloat 제거 ###############################################
sudo apt purge -y 'libreoffice*'
sudo apt purge -y thunderbird rhythmbox cheese transmission-gtk \
  aisleriot gnome-mahjongg gnome-mines gnome-sudoku gnome-todo \
  shotwell remmina
sudo snap remove firefox           # snap remove 엔 -y 없음
sudo apt install -y chromium-browser
sudo apt autoremove -y

### 12. reboot ##################################################
echo "==== 셋업 완료. 5초 후 리부트 ===="
sleep 5
sudo reboot
