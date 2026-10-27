#!/bin/bash
# Joseph's Voice-Typing 맥 설치·업데이트 (터미널 한 줄, specs/002 FR-023)
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Febrile-HJ/voice-typing-mac/main/install.sh)"
# 1) Apple 실리콘·macOS 14 이상 확인  2) 새 판 정보와 비밀번호 걸린 DMG 받기, 크기·SHA-256 확인
# 3) 조셉에게 받은 비밀번호로 열기  4) 조셉 인증서로 서명된 앱인지 확인  5) 켜진 앱 끄기, 옛 앱은 휴지통으로
# 6) 새 앱 넣기, 비밀번호는 앱 안 업데이트용으로 남기기(앱이 켜질 때 암호화해 옮기고 지운다)  7) 켜기
# 터미널로 받은 파일에는 macOS '인터넷에서 받음' 표시가 붙지 않아 차단 창이 뜨지 않는다.
set -euo pipefail
REPO="Febrile-HJ/voice-typing-mac"
BASE="${VT_RELEASE_BASE:-https://github.com/$REPO/releases/latest/download}"
TARGET="${VT_INSTALL_TARGET:-/Applications/Voice-Typing.app}"
CONFIG="${VT_CONFIG_DIR:-$HOME/.voice-typing}"
REQ='identifier "kr.joseph.voice-typing" and certificate leaf = H"fa6800c224114814fbb237ab321b03c4d16f3c7a"'
EXE="$TARGET/Contents/MacOS/JosephsVoiceTyping"

say() { printf '%s\n' "$*"; }
fail() { printf '\n설치하지 못했어요: %s\n' "$*" >&2; exit 1; }

say "Joseph's Voice-Typing 설치"
[[ "$(uname -m)" == "arm64" ]] || fail "Apple 실리콘(M 시리즈) 맥에서만 쓸 수 있어요."
major=$(sw_vers -productVersion | cut -d. -f1)
(( major >= 14 )) || fail "macOS 14 이상이 필요해요 (지금 $(sw_vers -productVersion))."

WORK=$(mktemp -d)
cleanup() { hdiutil detach -quiet "$WORK/mnt" 2>/dev/null || true; rm -rf "$WORK"; }
trap cleanup EXIT
mkdir -p "$WORK/mnt"

say "1) 새 판 정보 받기"
curl -fsSL "$BASE/latest.json" -o "$WORK/latest.json" || fail "새 판 정보를 받지 못했어요. 인터넷 연결을 확인해 주세요."
VERSION=$(plutil -extract version raw -o - "$WORK/latest.json")
URL=$(plutil -extract url raw -o - "$WORK/latest.json")
SHA=$(plutil -extract sha256 raw -o - "$WORK/latest.json")
SIZE=$(plutil -extract size raw -o - "$WORK/latest.json")
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]] || fail "새 판 정보가 올바르지 않아요."
say "   판 $VERSION ($(( SIZE / 1024 / 1024 ))MB)"

say "2) 받기"
curl -fL --progress-bar "$URL" -o "$WORK/vt.dmg" || fail "파일을 받지 못했어요."
[[ "$(stat -f %z "$WORK/vt.dmg")" == "$SIZE" ]] || fail "받은 파일 크기가 달라요. 다시 실행해 주세요."
[[ "$(shasum -a 256 "$WORK/vt.dmg" | cut -d' ' -f1)" == "$SHA" ]] || fail "받은 파일이 새 판 정보와 달라요. 다시 실행해 주세요."

ask_password() {  # 화면이 있으면 macOS 대화상자(취소하면 멈춤), 원격 접속이면 터미널에서 묻는다
  if [[ -n "${VT_TEST_PASSWORD:-}" ]]; then printf '%s' "$VT_TEST_PASSWORD"; return; fi
  if [[ -n "${SSH_TTY:-}" ]]; then IFS= read -rsp "$1 " pw < /dev/tty && echo >&2 && printf '%s' "$pw"; return; fi
  osascript -e "text returned of (display dialog \"$1\" with title \"Voice-Typing 설치\" default answer \"\" with hidden answer buttons {\"취소\", \"확인\"} default button \"확인\" cancel button \"취소\")" 2>/dev/null
}

say "3) 비밀번호로 열기"
PASSWORD=""
for try in 1 2 3; do
  if (( try == 1 )); then PASSWORD=$(ask_password "조셉에게 받은 설치 비밀번호를 넣어 주세요.") || fail "취소했어요."
  else PASSWORD=$(ask_password "비밀번호가 맞지 않아요. 다시 넣어 주세요.") || fail "취소했어요."; fi
  if printf '%s' "$PASSWORD" | hdiutil attach -quiet -nobrowse -readonly -noautoopen -stdinpass \
       -mountpoint "$WORK/mnt" "$WORK/vt.dmg" 2>/dev/null; then break; fi
  PASSWORD=""
  [[ -n "${VT_TEST_PASSWORD:-}" ]] && break
done
[[ -n "$PASSWORD" ]] || fail "비밀번호가 맞지 않아요."

say "4) 서명 확인"
codesign --verify --deep --strict -R "=$REQ" "$WORK/mnt/Voice-Typing.app" 2>/dev/null \
  || fail "조셉이 만든 앱이 아니에요. 설치하지 않았어요."
ditto "$WORK/mnt/Voice-Typing.app" "$WORK/Voice-Typing.app"
hdiutil detach -quiet "$WORK/mnt"

say "5) 켜진 앱 끄기"
running() { pgrep -f "^$EXE\$" >/dev/null 2>&1; }
if running; then
  : > "$(getconf DARWIN_USER_TEMP_DIR)Local_voice-typing-quit.signal"  # 앱 메뉴의 '종료'와 같은 정리
  for _ in $(seq 1 30); do running || break; sleep 0.5; done
  running && { pkill -TERM -f "^$EXE\$" || true; sleep 2; }
  running && fail "켜진 앱이 꺼지지 않았어요. 메뉴 막대의 Voice-Typing › 종료 뒤 다시 실행해 주세요."
fi

say "6) 넣기"
if [[ -d "$TARGET" ]]; then
  OLD=$(defaults read "$TARGET/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "옛 판")
  mkdir -p "$HOME/.Trash"
  rm -rf "$HOME/.Trash/Voice-Typing $OLD.app"
  mv "$TARGET" "$HOME/.Trash/Voice-Typing $OLD.app"
  say "   옛 앱($OLD)은 휴지통으로 옮겼어요"
fi
mv "$WORK/Voice-Typing.app" "$TARGET"
mkdir -p "$CONFIG"
( umask 077; printf '%s' "$PASSWORD" > "$CONFIG/.update-password" )  # 앱이 켜질 때 암호화해 옮기고 지운다
unset PASSWORD

if [[ -z "${VT_NO_LAUNCH:-}" ]]; then
  say "7) 켜기"
  open "$TARGET"
fi
say ""
say "완료: Voice-Typing $VERSION"
say "처음이면 macOS 가 묻는 것 두 가지만 허용해 주세요: 마이크 '허용', 손쉬운 사용에서 Voice-Typing 켜기."
say "다음 업데이트는 메뉴 막대 › 업데이트 에서 할 수 있어요."
