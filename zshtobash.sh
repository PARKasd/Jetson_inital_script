#!/usr/bin/env bash
#
# zsh -> bash 전환 + f1tenth_system 교체 스크립트
#   0) WiFi(MIRU_5G) 접속 + autoconnect/절전off
#   1) oh-my-zsh / zsh 제거, 기본 셸 bash 복귀
#   2) ~/.bashrc 에 ROS2 Humble 소싱 + alias
#   3) 기존 f1tenth_system 삭제 후 2026-AI-Boot-Camp 레포로 재구성
#
# 실행: bash switch_to_bash.sh     <- sudo 붙이지 말 것
#       WIFI_PSK='비번' bash switch_to_bash.sh   (무인 실행)
#
set -euo pipefail

### 0. sudo keep-alive ###########################################
sudo -v
( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT

WS="$HOME/f1tenth_ws"
REPO="https://github.com/2026-AI-Boot-Camp/f1tenth_system.git"
WIFI_SSID="${WIFI_SSID:-MIRU_5G}"

### 0.2 WiFi 비번 입력 (맨 앞에서 한 번만) #######################
# 스크립트에 비번 하드코딩 금지.
# 프로파일이 이미 있거나 WIFI_PSK 환경변수로 넘기면 프롬프트 생략.
#   완전 무인 실행:  WIFI_PSK='비번' bash switch_to_bash.sh
WIFI_PSK="${WIFI_PSK:-}"
if ! nmcli -g NAME connection show 2>/dev/null | grep -qxF "$WIFI_SSID"; then
  if [ -z "$WIFI_PSK" ]; then
    read -rsp "WiFi '$WIFI_SSID' 비밀번호 (없으면 Enter로 스킵): " WIFI_PSK
    echo
  fi
fi

### 0.5 WiFi 접속 + 자동 연결 설정 ###############################
sudo nmcli radio wifi on 2>/dev/null || true
sudo rfkill unblock wifi 2>/dev/null || true

if sudo nmcli -g NAME connection show | grep -qxF "$WIFI_SSID"; then
  echo "WiFi 프로파일 '$WIFI_SSID' 존재 -> 활성화"
  sudo nmcli connection up "$WIFI_SSID" || echo "WARN: '$WIFI_SSID' 활성화 실패"
elif [ -n "$WIFI_PSK" ]; then
  echo "WiFi '$WIFI_SSID' 접속 시도..."
  sudo nmcli device wifi rescan 2>/dev/null || true
  sleep 3
  sudo nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PSK" \
    || echo "WARN: '$WIFI_SSID' 접속 실패 (비번/신호 확인)"
else
  echo "WARN: '$WIFI_SSID' 프로파일 없고 비번도 없음 -> WiFi 설정 스킵"
fi
unset WIFI_PSK

if sudo nmcli -g NAME connection show | grep -qxF "$WIFI_SSID"; then
  sudo nmcli connection modify "$WIFI_SSID" connection.autoconnect yes
  sudo nmcli connection modify "$WIFI_SSID" connection.autoconnect-priority 100
  # wifi.powersave 2 = disable (주행 중 지연 튐 방지, 리부트 후에도 유지)
  sudo nmcli connection modify "$WIFI_SSID" wifi.powersave 2
  echo "WiFi '$WIFI_SSID' autoconnect + powersave off 설정 완료"
  nmcli -f NAME,DEVICE,STATE connection show --active | grep -F "$WIFI_SSID" || true
fi

### 0.7 유선 static IP (Hokuyo LiDAR, eno1) ######################
# point-to-point 라 gateway 불필요.
# never-default yes  -> 이 인터페이스가 기본 경로를 뺏지 않음 (WiFi 인터넷 유지)
LIDAR_IF="${LIDAR_IF:-eno1}"
LIDAR_IP="${LIDAR_IP:-10.110.1.3/24}"
LIDAR_CON="hokuyo-static"

if ip link show "$LIDAR_IF" >/dev/null 2>&1; then
  # 프로파일 없으면 생성
  sudo nmcli -g NAME connection show | grep -qxF "$LIDAR_CON" \
    || sudo nmcli connection add type ethernet ifname "$LIDAR_IF" con-name "$LIDAR_CON"

  sudo nmcli connection modify "$LIDAR_CON" \
    connection.interface-name "$LIDAR_IF" \
    connection.autoconnect yes \
    connection.autoconnect-priority 50 \
    ipv4.method manual \
    ipv4.addresses "$LIDAR_IP" \
    ipv4.gateway "" \
    ipv4.dns "" \
    ipv4.never-default yes \
    ipv6.method ignore

  # eno0 을 물고 있는 다른 자동 프로파일이 있으면 autoconnect 해제 (충돌 방지)
  while read -r n; do
    [ -n "$n" ] && [ "$n" != "$LIDAR_CON" ] && \
      sudo nmcli connection modify "$n" connection.autoconnect no 2>/dev/null || true
  done < <(sudo nmcli -g NAME,DEVICE connection show | awk -F: -v d="$LIDAR_IF" '$2==d {print $1}')

  sudo nmcli connection up "$LIDAR_CON" || echo "WARN: '$LIDAR_CON' 활성화 실패 (케이블 확인)"
  echo "유선 static IP 설정 완료: $LIDAR_IF -> $LIDAR_IP (재부팅 후에도 유지)"
  ip -4 addr show "$LIDAR_IF" | grep inet || true
else
  echo "WARN: 인터페이스 '$LIDAR_IF' 없음 -> static IP 스킵 (ip link 로 이름 확인)"
fi

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
