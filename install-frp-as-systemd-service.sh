#!/bin/bash
# Update on 2024/05/29
# 1. use wget to fetch latest frp version when curl was not installed
# 2. Remind users that frp will be run in non-root user
# 3. Add CI
#
# Update on 2024/04/13
# 1. Improved OS compatibility: try wget and then curl for downloading files.
#
# Update on 2024/01/26
# 1. Thanks to GitHub user @aka-Ani, this script now will install latest version of frp:
#    https://gist.github.com/lawrenceching/41244a182307940cc15b45e3c4997346?permalink_comment_id=4851742#gistcomment-4851742
# 2. Use .toml conf file as .ini became lagacy
#
# Update on 2023/06/19
# 1. frp no longer provide systemctl service file. This script creates frpc/fprs systemctl service file by itself
# 2. Update frp from 0.33.0 to 0.49.0
# 3. User=nobody is no longer suggested, use DynamicUser=yes instead

# ---

# set platform (latest options as of 2024/01/25), choose one of:
#   darwin_amd64
#   darwin_arm64
#   freebsd_amd64
#   linux_amd64
#   linux_arm
#   linux_arm64
#   linux_mips
#   linux_mips64le
#   linux_mipsle
#   linux_riscv64
#   windows_amd64
#   windows_arm64

platform=linux_amd64

WGET_INSTALLED=$(command -v wget &> /dev/null && echo 'true')
CURL_INSTALLED=$(command -v curl &> /dev/null && echo 'true')

if [[ "$WGET_INSTALLED" != 'true' &&  "$CURL_INSTALLED" != 'true' ]]; then
  echo "Neither wget nor curl is installed" 1>&2
  exit 1
fi


# download url can be determined by parsing the json of the releases/latest url. 
# each asset has a browser_download_url key, and we want the value where the platform is the one chosen above
if [[ "$WGET_INSTALLED" == 'true' ]]; then
  d_url=$(wget -qO- https://api.github.com/repos/fatedier/frp/releases/latest | grep browser_download_url | grep $platform | head -n 1 | cut -d '"' -f 4)
else
  d_url=$(curl -s https://api.github.com/repos/fatedier/frp/releases/latest | grep browser_download_url | grep $platform | head -n 1 | cut -d '"' -f 4)
fi

echo "Latest version URL: $d_url"
wget -q -P /tmp $d_url || curl -O -L --output-dir /tmp $d_url

DIR=$(basename $d_url .tar.gz)

tar -zxvf /tmp/$DIR.tar.gz -C /tmp

mkdir -p /etc/frp

cp /tmp/$DIR/frpc.toml /etc/frp/frpc.toml
cp /tmp/$DIR/frps.toml /etc/frp/frps.toml


cp /tmp/$DIR/frpc /usr/bin/
cp /tmp/$DIR/frps /usr/bin/

echo '[Unit]
Description=Frp Client Service
After=network.target
[Service]
Type=simple
DynamicUser=yes
Restart=on-failure
RestartSec=5s
ExecStart=/usr/bin/frpc -c /etc/frp/frpc.toml
ExecReload=/usr/bin/frpc reload -c /etc/frp/frpc.toml
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target' > /etc/systemd/system/frpc.service

echo '[Unit]
Description=Frp Server Service
After=network.target
[Service]
Type=simple
DynamicUser=yes
Restart=on-failure
RestartSec=5s
ExecStart=/usr/bin/frps -c /etc/frp/frps.toml
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target' > /etc/systemd/system/frps.service

systemctl daemon-reload

systemctl status frpc
systemctl status frps

echo '
frps and frpc are installed.
Modify /etc/frp/frpc.toml or /etc/frp/frps.toml
And then run

    systemctl enable frps
    systemctl start frps

or 

    systemctl enable frpc
    systemctl start frpc

to launch the services

Remove "DynamicUser=yes" in .toml files if you want frp run in root (which is not suggested for security reason).
'
