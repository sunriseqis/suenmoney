# Windows 侧连接参数（2026-10-27 IP 变更；公钥被拒 → 走密码）
export WIN=rootwin@100.66.45.14
export WINPASS='813112'
export SOPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o ControlPath=/tmp/win.sock -o ControlMaster=auto -o ControlPersist=3600 -o PreferredAuthentications=password -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1"
export T="-t 127.0.0.1:5555"
export TOOL='cd /d "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains" &&'
wssh() { sshpass -p "$WINPASS" ssh $SOPTS "$WIN" "$*"; }
wscp() { sshpass -p "$WINPASS" scp $SOPTS "$@"; }
hdc() { wssh "$TOOL hdc $T $*"; }
