#!/bin/bash
# 构建+部署（2026-10-27：Windows IP 变更 100.66.45.14，密码认证）
set -o pipefail
source /tmp/hwenv.sh
cd /home/suenmoney/hw-native || exit 1

# 1) 打包 + 传输 + 校验（ets + resources 都要过，字体/图标在 resources 里）
tar czf /tmp/hw-ets.tgz entry/src/main/ets entry/src/main/resources AppScope || exit 1
# ⚠ 不要上传 oh_modules：里面的软链在 Windows 上会失效，导致 CompileArkTS 报 00308018。
# 新机器首次构建前先跑一次：ohpm install --all
LOCAL_HASH=$(tar xzOf /tmp/hw-ets.tgz entry/src/main/ets/pages/MainPage.ets | sha256sum | cut -d' ' -f1)
echo "[1] 本地 MainPage.ets sha=$LOCAL_HASH"
wscp -q /tmp/hw-ets.tgz "$WIN:C:/work/hw-ets.tgz" || { echo "SCP_FAIL"; exit 1; }
wssh "cd /d C:\work\suenmoney\hw-native && tar xzf C:\work\hw-ets.tgz" || { echo "EXTRACT_FAIL"; exit 1; }
WIN_HASH=$(wssh "certutil -hashfile C:\work\suenmoney\hw-native\entry\src\main\ets\pages\MainPage.ets SHA256" | sed -n '2p' | tr -d ' \r')
ICON_WIN=$(wssh "certutil -hashfile C:\work\suenmoney\hw-native\entry\src\main\resources\base\media\foreground.png SHA256" | sed -n '2p' | tr -d ' \r')
ICON_LOCAL=$(tar xzOf /tmp/hw-ets.tgz entry/src/main/resources/base/media/foreground.png | sha256sum | cut -d' ' -f1)
echo "[2] Windows MainPage=$WIN_HASH"
echo "[2b] 图标 本地=$ICON_LOCAL"
echo "[2c] 图标 远端=$ICON_WIN"
[ "$LOCAL_HASH" = "$WIN_HASH" ] || { echo "HASH_MISMATCH"; exit 1; }
[ "$ICON_LOCAL" = "$ICON_WIN" ] || { echo "ICON_MISMATCH 图标没传上去"; exit 1; }

# 2) 构建
wssh "cd /d C:\work\suenmoney\hw-native && set DEVECO_SDK_HOME=C:\Program Files\Huawei\DevEco Studio\sdk& set PATH=C:\Program Files\Huawei\DevEco Studio\jbr\bin;C:\Program Files\Huawei\DevEco Studio\tools\node;%PATH%& \"C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat\" assembleHap --mode module -p product=default --no-daemon > C:\work\build.log 2>&1" >/dev/null 2>&1
BUILD=$(wssh "type C:\work\build.log" 2>&1)
if ! echo "$BUILD" | grep -q "BUILD SUCCESSFUL"; then
  echo "[3] BUILD FAILED"; echo "$BUILD" | grep -iE "Error Message|ERROR:" | head -12; exit 1
fi
echo "[3] BUILD OK"

# 3) 卸载重装 + 启动
hdc "uninstall com.suenmoney.app" >/dev/null 2>&1
hdc "install C:\work\suenmoney\hw-native\entry\build\default\outputs\default\entry-default-unsigned.hap" 2>&1 | grep -qi "successfully" || { echo "[4] INSTALL FAIL"; exit 1; }
echo "[4] INSTALL OK"
hdc "shell aa force-stop com.suenmoney.app" >/dev/null 2>&1
hdc "shell aa start -a EntryAbility -b com.suenmoney.app" 2>&1 | grep -q "successfully" || { echo "[5] START FAIL"; exit 1; }
echo "[5] START OK"
