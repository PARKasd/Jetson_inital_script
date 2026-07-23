#!/usr/bin/env bash
#
# zsh -> bash 전환 + f1tenth_system 교체 스크립트
#   1) oh-my-zsh / zsh 제거, 기본 셸 bash 복귀
#   2) ~/.bashrc 에 ROS2 Humble 소싱 + alias
#   3) 기존 f1tenth_system 삭제 후 2026-AI-Boot-Camp 레포로 재구성
#
# 실행: bash switch_to_bash.sh     <- sudo 붙이지 말 것
#
set -euo pipefail

### 0. sudo keep-alive ###########################################
sudo -v
( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT

WS="$HOME/f1tenth_ws"
REPO="https://github.com/2026-AI-Boot-Camp/f1tenth_system.git"

### 1. 기본 셸 bash 로 복귀 ######################################
BASH_BIN="$(command -v bash)"
grep -qxF "$BASH_BIN" /etc/shells || echo "$BASH_BIN" | sudo tee -a /etc/shells > /dev/null
sudo chsh -s "$BASH_BIN" "$USER" || sudo usermod -s "$BASH_BIN" "$USER"
echo "default shell -> $BASH_BIN"

### 2. oh-my-zsh / zsh 제거 ######################################
# oh-my-zsh 공식 언인스톨러가 있으면 사용 (uninstall_oh_my_zsh)
if [ -f "$HOME/.oh-my-zsh/tools/uninstall.sh" ]; then
  # 언인스톨러가 chsh 되돌리기를 시도하며 interactive 프롬프트를 띄울 수 있어
  # 여기서는 디렉토리 직접 제거로 처리 (위에서 이미 셸은 bash 로 바꿈)
  echo "oh-my-zsh 제거 중..."
fi
rm -rf "$HOME/.oh-my-zsh"

# zshrc 백업 후 제거 (혹시 참고할 내용 있을 수 있으니 백업만 남김)
for f in "$HOME/.zshrc" "$HOME/.zshrc.pre-oh-my-zsh" "$HOME/.zsh_history" "$HOME/.zcompdump"*; do
  [ -e "$f" ] && mv "$f" "$f.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
done

# zsh 패키지 제거 (terminator 등이 의존하지 않으므로 안전)
sudo apt purge -y zsh zsh-common || echo "WARN: zsh purge 실패 (무시 가능)"
sudo apt autoremove -y

### 3. ~/.bashrc 에 ROS2 Humble 소싱 + alias #####################
# 중복 append 방지 가드
add_bashrc() {
  grep -qF "$1" "$HOME/.bashrc" || echo "$1" >> "$HOME/.bashrc"
}

add_bashrc "source /opt/ros/humble/setup.bash"
add_bashrc "alias cb='colcon build --symlink-install'"
add_bashrc "alias sc='source install/setup.bash'"
add_bashrc "alias f110='cd \$HOME/f1tenth_ws && source install/setup.bash && ros2 launch f1tenth_stack bringup_launch.py'"

echo ".bashrc 설정 완료"

### 4. 기존 f1tenth_system 제거 ##################################
if [ -d "$WS/src/f1tenth_system" ]; then
  echo "기존 f1tenth_system 삭제..."
  rm -rf "$WS/src/f1tenth_system"
fi

# 이전 빌드 산출물도 정리 (구 패키지 잔재가 남으면 충돌)
rm -rf "$WS/build" "$WS/install" "$WS/log"

### 5. 새 레포 clone + submodule #################################
mkdir -p "$WS/src"
cd "$WS/src"
git clone "$REPO" f1tenth_system
cd f1tenth_system
git submodule update --init --recursive --remote

### 6. rosdep + build ############################################
# ROS setup 스크립트는 set -u 안전하지 않음 -> source 동안만 nounset 끔
set +u
# shellcheck disable=SC1091
source /opt/ros/humble/setup.bash
set -u

cd "$WS"
sudo rosdep init 2>/dev/null || true
rosdep update --include-eol --rosdistro=humble
rosdep install --include-eol --from-paths src -i -y --rosdistro=humble
sudo apt install -y ros-humble-asio-cmake-module
colcon build

echo ""
echo "==== 완료 ===="
echo "새 터미널을 열거나 'exec bash -l' 로 bash 환경 적용"
echo "확인: getent passwd \$USER | cut -d: -f7   ->  $BASH_BIN 이어야 함"
