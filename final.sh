#!/usr/bin/env bash
#
# 1) 키보드 레이아웃 롤백: kr104(101/104 호환) -> 기본 kr / pc104
#    - evdev 키코드 패치했다면 원본 복구
# 2) Chromium 을 GNOME 즐겨찾기(dash)에 등록
# 3) f1tenth_system 통째로 지우고 재clone + 클린 빌드
#
# 실행: bash kbd_rollback_and_chromium.sh   <- sudo 붙이지 말 것
#       WS=~/다른워크스페이스 bash ...
#
set -euo pipefail

### sudo keep-alive ##############################################
sudo -v
( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
KEEPALIVE_PID=$!
trap 'kill "$KEEPALIVE_PID" 2>/dev/null || true' EXIT

WS="${WS:-$HOME/f1tenth_ws}"
PKG_DIR="$WS/src/f1tenth_system"
REPO="${REPO:-https://github.com/2026-AI-Boot-Camp/f1tenth_system.git}"
BRANCH="${BRANCH:-hyu}"

XKB_FILE="/usr/share/X11/xkb/keycodes/evdev"
XKB_MODEL="${XKB_MODEL:-pc104}"
XKB_LAYOUT="kr"
XKB_VARIANT=""          # kr104 안 씀 -> 빈 값

echo "=== 1. 키보드 레이아웃 롤백 ==="

### 1.1 evdev 패치 원본 복구 #####################################
if [ -f "$XKB_FILE.orig" ]; then
  if ! cmp -s "$XKB_FILE.orig" "$XKB_FILE"; then
    sudo cp "$XKB_FILE.orig" "$XKB_FILE"
    echo "evdev 원본 복구 완료"
  else
    echo "evdev 이미 원본 상태 -> 스킵"
  fi
else
  echo "evdev 백업 없음 -> 패치 안 했던 것으로 간주"
fi

# xkb 컴파일 캐시 삭제 (안 지우면 옛 키맵 계속 사용됨)
sudo rm -rf /var/lib/xkb/* 2>/dev/null || true

### 1.2 시스템 전역 X11 키맵 -> kr / pc104 / (variant 없음) ######
if command -v localectl >/dev/null 2>&1; then
  sudo localectl set-x11-keymap "$XKB_LAYOUT" "$XKB_MODEL" "$XKB_VARIANT" \
    || echo "WARN: set-x11-keymap 실패"
  echo "X11 keymap -> $XKB_LAYOUT / $XKB_MODEL / (variant 없음)"
  localectl status 2>/dev/null | grep -i -E "X11|VC" || true
else
  sudo sed -i \
    -e "s|^XKBLAYOUT=.*|XKBLAYOUT=\"$XKB_LAYOUT\"|" \
    -e "s|^XKBMODEL=.*|XKBMODEL=\"$XKB_MODEL\"|" \
    -e "s|^XKBVARIANT=.*|XKBVARIANT=\"\"|" \
    /etc/default/keyboard || echo "WARN: /etc/default/keyboard 수정 실패"
  echo "/etc/default/keyboard 직접 수정 완료"
fi

### 1.3 GUI 세션 설정 (input-sources / 즐겨찾기) #################
if [ -S "/run/user/$(id -u)/bus" ]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
  GUI_OK=1
else
  GUI_OK=0
  echo "WARN: GUI 세션 아님(SSH?) -> gsettings 항목은 데스크톱 로그인 후 재실행 필요"
fi

if [ "$GUI_OK" = "1" ]; then
  # kr+kr104 -> kr 로 롤백
  gsettings set org.gnome.desktop.input-sources sources \
    "[('xkb','kr'),('ibus','hangul')]" 2>/dev/null \
    || echo "WARN: input-sources 설정 실패"
  gsettings set org.freedesktop.ibus.engine.hangul switch-keys 'Hangul' 2>/dev/null \
    || echo "WARN: switch-keys 설정 실패"
  echo "input-sources -> [('xkb','kr'),('ibus','hangul')]"
fi

echo ""
echo "=== 2. Chromium 즐겨찾기 등록 ==="

### 2.1 chromium 설치 확인 (없으면 설치) #########################
if ! command -v chromium >/dev/null 2>&1 && ! command -v chromium-browser >/dev/null 2>&1; then
  echo "chromium 없음 -> 설치 시도"
  sudo apt install -y chromium-browser || sudo apt install -y chromium \
    || echo "WARN: chromium 설치 실패 (수동 설치 필요)"
fi

### 2.2 .desktop 파일 탐색 (snap/apt 이름이 다름) ################
DESKTOP_ID=""
for cand in chromium_chromium.desktop chromium-browser.desktop chromium.desktop; do
  for dir in /var/lib/snapd/desktop/applications /usr/share/applications "$HOME/.local/share/applications"; do
    if [ -f "$dir/$cand" ]; then
      DESKTOP_ID="$cand"
      break 2
    fi
  done
done

if [ -z "$DESKTOP_ID" ]; then
  echo "WARN: chromium .desktop 파일을 못 찾음 -> 즐겨찾기 등록 스킵"
  echo "      확인: ls /usr/share/applications | grep -i chrom"
elif [ "$GUI_OK" != "1" ]; then
  echo "WARN: GUI 세션 아님 -> 즐겨찾기 등록 스킵 ($DESKTOP_ID)"
else
  ### 2.3 favorite-apps 배열에 append (중복 방지) ################
  CUR="$(gsettings get org.gnome.shell favorite-apps 2>/dev/null || echo "@as []")"
  NEW="$(python3 - "$CUR" "$DESKTOP_ID" <<'PYEOF'
import ast, sys
cur, item = sys.argv[1].strip(), sys.argv[2]
if cur.startswith('@as'):
    cur = cur[3:].strip()
try:
    lst = ast.literal_eval(cur)
except Exception:
    lst = []
if not isinstance(lst, list):
    lst = []
if item not in lst:
    lst.append(item)
print("[" + ", ".join("'%s'" % x for x in lst) + "]")
PYEOF
)"
  gsettings set org.gnome.shell favorite-apps "$NEW" \
    && echo "즐겨찾기 등록 완료: $DESKTOP_ID" \
    || echo "WARN: favorite-apps 설정 실패"
  gsettings get org.gnome.shell favorite-apps
fi

echo ""
echo "=== 3. f1tenth_system 재설치 + 클린 빌드 ==="

### 3.1 기존 소스/빌드 산출물 제거 ###############################
# WS 가 빈 문자열/루트면 rm -rf 가 엉뚱한 곳을 지우므로 여기서만 막음
case "$WS" in
  /|"") echo "ERROR: WS='$WS' 비정상 -> 중단"; exit 1 ;;
esac

echo "삭제: $PKG_DIR (.git 포함), $WS/{build,install,log}"
rm -rf "$PKG_DIR" "$WS/build" "$WS/install" "$WS/log"

# root 소유 파일이 섞여 있으면 위 rm 이 조용히 실패할 수 있음 -> sudo 로 재시도
if [ -e "$PKG_DIR" ]; then
  echo "WARN: $PKG_DIR 잔존 -> sudo 로 재삭제"
  sudo rm -rf "$PKG_DIR"
fi
[ -e "$PKG_DIR" ] && { echo "ERROR: $PKG_DIR 삭제 실패 -> 중단"; exit 1; }

mkdir -p "$WS/src"

### 3.2 새로 clone + submodule ###################################
cd "$WS/src"
# 기본 브랜치가 아니라 hyu 브랜치를 받아야 함
git clone -b "$BRANCH" "$REPO" f1tenth_system \
  || { echo "WARN: '$BRANCH' 브랜치 clone 실패 -> 기본 브랜치로"; git clone "$REPO" f1tenth_system; }
cd f1tenth_system
git submodule update --init --recursive --remote

### 3.3 rosdep + 빌드 ############################################
set +u
# shellcheck disable=SC1091
source /opt/ros/humble/setup.bash
set -u

cd "$WS"
sudo rosdep init 2>/dev/null || true
rosdep update --include-eol --rosdistro=humble || echo "WARN: rosdep update 실패"
rosdep install --include-eol --from-paths src -i -y --rosdistro=humble \
  || echo "WARN: rosdep install 일부 실패"
sudo apt install -y ros-humble-asio-cmake-module
colcon build --symlink-install
echo "빌드 완료: $WS"

echo ""
echo "==== 완료 ===="
echo "키맵은 로그아웃/재로그인(또는 재부팅) 후 완전 적용"
echo "확인: localectl status | grep -i x11"
echo "워크스페이스: source $WS/install/setup.bash"
