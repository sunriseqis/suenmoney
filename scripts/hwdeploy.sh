#!/bin/bash
# 可靠构建+部署：每步断言，杜绝「测旧包」
set -o pipefail
SOPTS="-o StrictHostKeyChecking=no -o BatchMode=yes -o ControlPath=/tmp/win.sock -o ControlMaster=auto -o ControlPersist=1800"
T="-t 127.0.0.1:5555"
WIN=rootwin@192.168.89.206
TOOL='cd /d "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains" &&'
cd /home/suenmoney/hw-native || exit 1

hdc() { ssh -i /root/.ssh/id_win $SOPTS $WIN "$TOOL hdc $T $*"; }

# --- 1. 打包 + 传输 + 校验 ---
tar czf /tmp/hw-ets.tgz entry/src/main/ets entry/src/main/resources || exit 1
LOCAL_HASH=$(tar xzOf /tmp/hw-ets.tgz entry/src/main/ets/components/ledger/LedgerScreen.ets | sha256sum | cut -d' ' -f1)
echo "[1] 本地 LedgerScreen.ets sha=$LOCAL_HASH"
timeout 120 scp -q -i /root/.ssh/id_win $SOPTS /tmp/hw-ets.tgz $WIN:C:/work/hw-ets.tgz || { echo "SCP_FAIL"; exit 1; }
timeout 120 ssh -i /root/.ssh/id_win $SOPTS $WIN "cd /d C:\work\suenmoney\hw-native && tar xzf C:\work\hw-ets.tgz" || { echo "EXTRACT_FAIL"; exit 1; }
WIN_HASH=$(timeout 60 ssh -i /root/.ssh/id_win $SOPTS $WIN "certutil -hashfile C:\work\suenmoney\hw-native\entry\src\main\ets\components\ledger\LedgerScreen.ets SHA256" | sed -n '2p' | tr -d ' \r')
FTF_LOCAL=$(tar xzOf /tmp/hw-ets.tgz entry/src/main/resources/rawfile/fonts/Orbitron-700.ttf | sha256sum | cut -d' ' -f1)
FTF_WIN=$(timeout 60 ssh -i /root/.ssh/id_win $SOPTS $WIN "certutil -hashfile C:\work\suenmoney\hw-native\entry\src\main\resources\rawfile\fonts\Orbitron-700.ttf SHA256" | sed -n '2p' | tr -d ' \r')
echo "[2b] Orbitron 本地=$FTF_LOCAL"
echo "[2c] Orbitron 远=$FTF_WIN"
[ "$FTF_LOCAL" = "$FTF_WIN" ] || { echo "FONT_HASH_MISMATCH"; exit 1; }
echo "[2] Windows sha=$WIN_HASH"
[ "$LOCAL_HASH" = "$WIN_HASH" ] || { echo "HASH_MISMATCH 传输没落地"; exit 1; }

# --- 2. 构建 ---
timeout 600 ssh -i /root/.ssh/id_win $SOPTS $WIN "cd /d C:\work\suenmoney\hw-native && set DEVECO_SDK_HOME=C:\Program Files\Huawei\DevEco Studio\sdk& set PATH=C:\Program Files\Huawei\DevEco Studio\jbr\bin;C:\Program Files\Huawei\DevEco Studio\tools\node;%PATH%& \"C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat\" assembleHap --mode module -p product=default --no-daemon > C:\work\build.log 2>&1" >/dev/null 2>&1
BUILD=$(timeout 60 ssh -i /root/.ssh/id_win $SOPTS $WIN "type C:\work\build.log" 2>&1)
if ! echo "$BUILD" | grep -q "BUILD SUCCESSFUL"; then
  echo "[3] BUILD FAILED"; echo "$BUILD" | grep -iE "error" | head -10; exit 1
fi
echo "[3] BUILD OK"

# --- 3. 卸载重装（避免 -r 留下旧资源）+ 启动 ---
hdc "uninstall com.suenmoney.app" >/dev/null 2>&1
hdc "install C:\work\suenmoney\hw-native\entry\build\default\outputs\default\entry-default-unsigned.hap" 2>&1 | grep -qi "successfully" || { echo "[4] INSTALL FAIL"; exit 1; }
echo "[4] INSTALL OK"
hdc "shell aa force-stop com.suenmoney.app" >/dev/null 2>&1
hdc "shell aa start -a EntryAbility -b com.suenmoney.app" 2>&1 | grep -q "successfully" || { echo "[5] START FAIL"; exit 1; }
echo "[5] START OK"
