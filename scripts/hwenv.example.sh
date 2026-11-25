#!/bin/bash
# Windows 侧连接参数模板 —— 复制为 scripts/hwenv.sh 或 /tmp/hwenv.sh 后填真实值。
# 该文件含明文口令，绝不入库（scripts/hwenv.sh 已在 .gitignore）。
#
# 用法：
#   cp scripts/hwenv.example.sh /tmp/hwenv.sh
#   # 填好 WIN / WINPASS 后，hwdeploy.sh 即可 source /tmp/hwenv.sh

export WIN=rootwin@<内网IP>
export WINPASS='<SSH密码>'
export SOPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o ControlPath=/tmp/win.sock -o ControlMaster=auto -o ControlPersist=3600 -o PreferredAuthentications=password -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1"
export T="-t 127.0.0.1:5555"
export TOOL='cd /d "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains" &&'
wssh() { sshpass -p "$WINPASS" ssh $SOPTS "$WIN" "$*"; }
wscp() { sshpass -p "$WINPASS" scp $SOPTS "$@"; }
hdc() { wssh "$TOOL hdc $T $*"; }
