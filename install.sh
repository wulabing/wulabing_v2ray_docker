#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

cd "$(
  cd "$(dirname "$0")" || exit
  pwd
)" || exit

#fonts color
Green="\033[32m"
Red="\033[31m"
# Yellow="\033[33m"
GreenBG="\033[42;37m"
RedBG="\033[41;37m"
Font="\033[0m"

#notification information
# Info="${Green}[信息]${Font}"
OK="${Green}[OK]${Font}"
Error="${Red}[错误]${Font}"

shell_version="0.1"
shell_mode="None"
github_branch="master"
version_cmp="/tmp/version_cmp.tmp"
v2ray_conf_dir="/etc/v2ray"
nginx_conf_dir="/etc/nginx/conf.d/"
v2ray_conf="${v2ray_conf_dir}/config.json"
nginx_conf="${nginx_conf_dir}/v2ray.conf"
nginx_dir="/etc/nginx"
web_dir="/www"
v2ray_info_file="$HOME/v2ray_info.inf"
v2ray_qr_config_file="/usr/local/vmess_qr.json"
v2ray_access_log="/var/log/v2ray/access.log"
v2ray_error_log="/var/log/v2ray/error.log"

random_num=$((RANDOM % 12 + 4))
#简易随机数
random_num=$((RANDOM % 12 + 4))
#生成伪装路径
camouflage="/$(head -n 10 /dev/urandom | md5sum | head -c ${random_num})/"

source '/etc/os-release'

is_root() {
  if [ 0 == $UID ]; then
    echo -e "${OK} ${GreenBG} 当前用户是root用户，进入安装流程 ${Font}"
    sleep 3
  else
    echo -e "${Error} ${RedBG} 当前用户不是root用户，请切换到root用户后重新执行脚本 ${Font}"
    exit 1
  fi
}

init_system() {
  if [[ "${ID}" == "centos" && ${VERSION_ID} -ge 7 ]]; then
    echo -e "${OK} ${GreenBG} 当前系统为 Centos ${VERSION_ID} ${VERSION} ${Font}"
    INS="yum"
  elif [[ "${ID}" == "debian" && ${VERSION_ID} -ge 9 ]]; then
    echo -e "${OK} ${GreenBG} 当前系统为 Debian ${VERSION_ID} ${VERSION} ${Font}"
    INS="apt"
    $INS update
    ## 添加 Nginx apt源
  elif [[ "${ID}" == "ubuntu" && $(echo "${VERSION_ID}" | cut -d '.' -f1) -ge 18 ]]; then
    echo -e "${OK} ${GreenBG} 当前系统为 Ubuntu ${VERSION_ID} ${UBUNTU_CODENAME} ${Font}"
    INS="apt"
    rm /var/lib/dpkg/lock
    dpkg --configure -a
    rm /var/lib/apt/lists/lock
    rm /var/cache/apt/archives/lock
    $INS update
  else
    echo -e "${Error} ${RedBG} 当前系统为 ${ID} ${VERSION_ID} 不在支持的系统列表内，安装中断 ${Font}"
    exit 1
  fi
  $INS install dbus

  systemctl stop firewalld
  systemctl disable firewalld
  echo -e "${OK} ${GreenBG} firewalld 已关闭 ${Font}"

  systemctl stop ufw
  systemctl disable ufw
  echo -e "${OK} ${GreenBG} ufw 已关闭 ${Font}"
}

judge() {
  if [[ 0 -eq $? ]]; then
    echo -e "${OK} ${GreenBG} $1 完成 ${Font}"
    sleep 1
  else
    echo -e "${Error} ${RedBG} $1 失败${Font}"
    exit 1
  fi
}

dependency_install() {
  ${INS} install wget git lsof -y

  #  if [[ "${ID}" == "centos" ]]; then
  #    ${INS} -y install crontabs
  #  else
  #    ${INS} -y install cron
  #  fi
  #  judge "安装 crontab"
  #
  #  if [[ "${ID}" == "centos" ]]; then
  #    touch /var/spool/cron/root && chmod 600 /var/spool/cron/root
  #    systemctl start crond && systemctl enable crond
  #  else
  #    touch /var/spool/cron/crontabs/root && chmod 600 /var/spool/cron/crontabs/root
  #    systemctl start cron && systemctl enable cron
  #
  #  fi
  #  judge "crontab 自启动配置 "

  ${INS} -y install bc
  judge "安装 bc"

  ${INS} -y install unzip
  judge "安装 unzip"

  ${INS} -y install qrencode
  judge "安装 qrencode"

  ${INS} -y install curl
  judge "安装 curl"

  if [[ -z $(command -v docker) ]]; then
    curl -fsSL https://get.docker.com -o get-docker.sh && sh ./get-docker.sh
    systemctl start docker && systemctl enable docker
  fi
  judge "安装 docker"

  if [[ -z $(command -v docker-compose) ]]; then
    ${INS} -y install docker-compose
  fi
  judge "安装 docker-compose"

}

basic_optimization() {
  # 最大文件打开数
  sed -i '/^\*\ *soft\ *nofile\ *[[:digit:]]*/d' /etc/security/limits.conf
  sed -i '/^\*\ *hard\ *nofile\ *[[:digit:]]*/d' /etc/security/limits.conf
  echo '* soft nofile 65536' >>/etc/security/limits.conf
  echo '* hard nofile 65536' >>/etc/security/limits.conf

  # 关闭 Selinux
  if [[ "${ID}" == "centos" ]]; then
    sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
    setenforce 0
  fi
}

port_alterid_set() {
  if [[ "on" != "$old_config_status" ]]; then
    read -rp "请输入连接端口（default:443）:" port
    [[ -z ${port} ]] && port="443"
    read -rp "请输入alterID（default:2 仅允许填数字）:" alterID
    [[ -z ${alterID} ]] && alterID="2"
    #    read -rp "请输入email（正确的邮箱可以在证书到期时收到邮件的提示）:" email
    #    [[ -z ${email} ]] && echo -e "${Error} ${RedBG} 未输入email${Font}" && exit 1
  fi
}

modify_path() {
  if [[ "on" == "$old_config_status" ]]; then
    camouflage="$(grep '\"path\"' $v2ray_qr_config_file | awk -F '"' '{print $4}')"
  fi
  sed -i "/\"path\"/c \\\t  \"path\":\"${camouflage}\"" ${v2ray_conf}
  judge "V2ray 伪装路径 修改"
}
modify_alterid() {
  if [[ "on" == "$old_config_status" ]]; then
    alterID="$(grep '\"aid\"' $v2ray_qr_config_file | awk -F '"' '{print $4}')"
  fi
  sed -i "/\"alterId\"/c \\\t  \"alterId\":${alterID}" ${v2ray_conf}
  judge "V2ray alterid 修改"
  [ -f ${v2ray_qr_config_file} ] && sed -i "/\"aid\"/c \\  \"aid\": \"${alterID}\"," ${v2ray_qr_config_file}
  echo -e "${OK} ${GreenBG} alterID:${alterID} ${Font}"
}
modify_inbound_port() {
  if [[ "on" == "$old_config_status" ]]; then
    port="$(info_extraction '\"port\"')"
  fi
  if [[ "$shell_mode" != "h2" ]]; then
    PORT=$((RANDOM + 10000))
    sed -i "/\"port\"/c  \    \"port\":${PORT}," ${v2ray_conf}
  else
    sed -i "/\"port\"/c  \    \"port\":${port}," ${v2ray_conf}
  fi
  judge "V2ray inbound_port 修改"
}
modify_UUID() {
  [ -z "$UUID" ] && UUID=$(cat /proc/sys/kernel/random/uuid)
  if [[ "on" == "$old_config_status" ]]; then
    UUID="$(info_extraction '\"id\"')"
  fi
  sed -i "/\"id\"/c \\\t  \"id\":\"${UUID}\"," ${v2ray_conf}
  judge "V2ray UUID 修改"
  [ -f ${v2ray_qr_config_file} ] && sed -i "/\"id\"/c \\  \"id\": \"${UUID}\"," ${v2ray_qr_config_file}
  echo -e "${OK} ${GreenBG} UUID:${UUID} ${Font}"
}
modify_nginx_port() {
  if [[ "on" == "$old_config_status" ]]; then
    port="$(info_extraction '\"port\"')"
  fi
  sed -i "/ssl http2;$/c \\\tlisten ${port} ssl http2;" ${nginx_conf}
  sed -i "3c \\\tlisten [::]:${port} http2;" ${nginx_conf}
  judge "V2ray port 修改"
  [ -f ${v2ray_qr_config_file} ] && sed -i "/\"port\"/c \\  \"port\": \"${port}\"," ${v2ray_qr_config_file}
  echo -e "${OK} ${GreenBG} 端口号:${port} ${Font}"
}
modify_nginx_other() {
  sed -i "/server_name/c \\\tserver_name ${domain};" ${nginx_conf}
  sed -i "/location/c \\\tlocation ${camouflage}" ${nginx_conf}
  sed -i "/proxy_pass/c \\\tproxy_pass http://v2ray:${PORT};" ${nginx_conf}
  sed -i "/return/c \\\treturn 301 https://${domain}\$request_uri;" ${nginx_conf}
  #sed -i "27i \\\tproxy_intercept_errors on;"  ${nginx_dir}/conf/nginx.conf
}
web_camouflage() {
  ##请注意 这里和LNMP脚本的默认路径冲突，千万不要在安装了LNMP的环境下使用本脚本，否则后果自负
  rm -rf $web_dir
  mkdir -p $web_dir
  git clone https://github.com/wulabing/3DCEList.git $web_dir
  judge "web 站点伪装"
}
nginx_pre_install() {
  # 取nginx 配置文件
  rm -rf /etc/nginx
  rm -rf $web_dir

  docker run -d --name nginx_conf nginx:stable
  docker cp nginx_conf:/etc/nginx /etc/nginx
  docker stop nginx_conf && docker rm nginx_conf

}

domain_check() {
  read -rp "请输入你的域名信息(eg:www.wulabing.com):" domain
  domain_ip=$(ping "${domain}" -c 1 | sed '1{s/[^(]*(//;s/).*//;q}')
  echo -e "${OK} ${GreenBG} 正在获取 公网ip 信息，请耐心等待 ${Font}"
  local_ip=$(curl https://api-ipv4.ip.sb/ip)
  echo -e "域名dns解析IP：${domain_ip}"
  echo -e "本机IP: ${local_ip}"
  sleep 2
  if [[ $(echo "${local_ip}" | tr '.' '+' | bc) -eq $(echo "${domain_ip}" | tr '.' '+' | bc) ]]; then
    echo -e "${OK} ${GreenBG} 域名dns解析IP 与 本机IP 匹配 ${Font}"
    sleep 2
  else
    echo -e "${Error} ${RedBG} 请确保域名添加了正确的 A 记录，否则将无法正常使用 V2ray ${Font}"
    echo -e "${Error} ${RedBG} 域名dns解析IP 与 本机IP 不匹配 是否继续安装？（y/n）${Font}" && read -r install
    case $install in
    [yY][eE][sS] | [yY])
      echo -e "${GreenBG} 继续安装 ${Font}"
      sleep 2
      ;;
    *)
      echo -e "${RedBG} 安装终止 ${Font}"
      exit 2
      ;;
    esac
  fi
}

port_exist_check() {
  if [[ 0 -eq $(lsof -i:"$1" | grep -i -c "listen") ]]; then
    echo -e "${OK} ${GreenBG} $1 端口未被占用 ${Font}"
    sleep 1
  else
    echo -e "${Error} ${RedBG} 检测到 $1 端口被占用，以下为 $1 端口占用信息 ${Font}"
    lsof -i:"$1"
    echo -e "${OK} ${GreenBG} 5s 后将尝试自动 kill 占用进程 ${Font}"
    sleep 5
    lsof -i:"$1" | awk '{print $2}' | grep -v "PID" | xargs kill -9
    echo -e "${OK} ${GreenBG} kill 完成 ${Font}"
    sleep 1
  fi
}

v2ray_conf_add_tls() {
  mkdir -p /etc/v2ray
  cp -a ./tls/config.json /etc/v2ray/
  modify_alterid
  modify_inbound_port
  modify_UUID
  modify_path
}

old_config_exist_check() {
  if [[ -f $v2ray_qr_config_file ]]; then
    echo -e "${OK} ${GreenBG} 检测到旧配置文件，是否读取旧文件配置 [Y/N]? ${Font}"
    read -r ssl_delete
    case $ssl_delete in
    [yY][eE][sS] | [yY])
      echo -e "${OK} ${GreenBG} 已保留旧配置  ${Font}"
      old_config_status="on"
      port=$(info_extraction '\"port\"')
      ;;
    *)
      rm -rf $v2ray_qr_config_file
      echo -e "${OK} ${GreenBG} 已删除旧配置  ${Font}"
      ;;
    esac
  fi
}

nginx_conf_add() {
  touch ${nginx_conf_dir}/v2ray.conf
  cat >${nginx_conf_dir}/v2ray.conf <<EOF
    server {
        listen 443 ssl http2;
        listen [::]:443 http2;
        ssl_certificate       /ssl/v2ray.crt;
        ssl_certificate_key   /ssl/v2ray.key;
        ssl_protocols         TLSv1.3;
        ssl_ciphers           TLS13-AES-256-GCM-SHA384:TLS13-CHACHA20-POLY1305-SHA256:TLS13-AES-128-GCM-SHA256:TLS13-AES-128-CCM-8-SHA256:TLS13-AES-128-CCM-SHA256:EECDH+CHACHA20:EECDH+CHACHA20-draft:EECDH+ECDSA+AES128:EECDH+aRSA+AES128:RSA+AES128:EECDH+ECDSA+AES256:EECDH+aRSA+AES256:RSA+AES256:EECDH+ECDSA+3DES:EECDH+aRSA+3DES:RSA+3DES:!MD5;
        server_name           serveraddr.com;
        index index.html index.htm;
        root  /www;
        error_page 400 = /400.html;

        # Config for 0-RTT in TLSv1.3
        ssl_early_data on;
        ssl_stapling on;
        ssl_stapling_verify on;
        add_header Strict-Transport-Security "max-age=31536000";

        location /ray/
        {
        proxy_redirect off;
        proxy_read_timeout 1200s;
        proxy_pass http://v2ray:10000;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;

        # Config for 0-RTT in TLSv1.3
        proxy_set_header Early-Data \$ssl_early_data;
        }
}
    server {
        listen 80;
        listen [::]:80;
        server_name serveraddr.com;
        return 301 https://use.shadowsocksr.win\$request_uri;
    }
EOF

  modify_nginx_port
  modify_nginx_other
  judge "Nginx 配置修改"

}

vmess_qr_config_tls_ws() {
  cat >$v2ray_qr_config_file <<-EOF
{
  "v": "2",
  "ps": "wulabing_${domain}",
  "add": "${domain}",
  "port": "${port}",
  "id": "${UUID}",
  "aid": "${alterID}",
  "net": "ws",
  "type": "none",
  "host": "${domain}",
  "path": "${camouflage}",
  "tls": "tls"
}
EOF
}

vmess_qr_link_image() {
  vmess_link="vmess://$(base64 -w 0 $v2ray_qr_config_file)"
  {
    echo -e "$Red 二维码: $Font"
    echo -n "${vmess_link}" | qrencode -o - -t utf8
    echo -e "${Red} URL导入链接:${vmess_link} ${Font}"
  } >>"${v2ray_info_file}"
}
vmess_quan_link_image() {
  echo "$(info_extraction '\"ps\"') = vmess, $(info_extraction '\"add\"'), \
    $(info_extraction '\"port\"'), chacha20-ietf-poly1305, "\"$(info_extraction '\"id\"')\"", over-tls=true, \
    certificate=1, obfs=ws, obfs-path="\"$(info_extraction '\"path\"')\"", " >/tmp/vmess_quan.tmp
  vmess_link="vmess://$(base64 -w 0 /tmp/vmess_quan.tmp)"
  {
    echo -e "$Red 二维码: $Font"
    echo -n "${vmess_link}" | qrencode -o - -t utf8
    echo -e "${Red} URL导入链接:${vmess_link} ${Font}"
  } >>"${v2ray_info_file}"
}

vmess_link_image_choice() {
  echo "请选择生成的链接种类"
  echo "1: V2RayNG/V2RayN"
  echo "2: quantumult"
  read -rp "请输入：" link_version
  [[ -z ${link_version} ]] && link_version=1
  if [[ $link_version == 1 ]]; then
    vmess_qr_link_image
  elif [[ $link_version == 2 ]]; then
    vmess_quan_link_image
  else
    vmess_qr_link_image
  fi
}
info_extraction() {
  grep "$1" $v2ray_qr_config_file | awk -F '"' '{print $4}'
}

basic_information() {
  {
    echo -e "${OK} ${GreenBG} V2ray+ws+tls 安装成功"
    echo -e "${Red} V2ray 配置信息 ${Font}"
    echo -e "${Red} 地址（address）:${Font} $(info_extraction '\"add\"') "
    echo -e "${Red} 端口（port）：${Font} $(info_extraction '\"port\"') "
    echo -e "${Red} 用户id（UUID）：${Font} $(info_extraction '\"id\"')"
    echo -e "${Red} 额外id（alterId）：${Font} $(info_extraction '\"aid\"')"
    echo -e "${Red} 加密方式（security）：${Font} 自适应 "
    echo -e "${Red} 传输协议（network）：${Font} $(info_extraction '\"net\"') "
    echo -e "${Red} 伪装类型（type）：${Font} none "
    echo -e "${Red} 路径（不要落下/）：${Font} $(info_extraction '\"path\"') "
    echo -e "${Red} 底层传输安全：${Font} tls "
  } >"${v2ray_info_file}"
}
show_information() {
  cat "${v2ray_info_file}"
}

ssl_judge_and_install() {
  if [[ -f "/ssl/v2ray.key" || -f "/ssl/v2ray.crt" ]]; then
    echo "/ssl 目录下证书文件已存在"
    echo -e "${OK} ${GreenBG} 是否删除 [Y/N]? ${Font}"
    read -r ssl_delete
    case $ssl_delete in
    [yY][eE][sS] | [yY])
      rm -rf /ssl/*
      echo -e "${OK} ${GreenBG} 已删除 ${Font}"
      ;;
    *) ;;

    esac
  fi

  if [[ -f "/ssl/v2ray.key" || -f "/ssl/v2ray.crt" ]]; then
    echo "证书文件已存在"
  else
    acme
  fi
}
acme() {
  docker run -it --rm \
    -p 80:80 \
    -p 443:443 \
    -v "$(pwd)/acme":/acme.sh \
    neilpang/acme.sh --issue --standalone --server letsencrypt --preferred-chain "ISRG Root X1" -d $domain

  docker run -it --rm \
    -v "$(pwd)/acme":/acme.sh \
    -v /ssl:/ssl \
    neilpang/acme.sh --install-cert -d $domain \
    --key-file /ssl/v2ray.key \
    --fullchain-file /ssl/v2ray.crt
  judge "证书签发"
}

tls_type() {
  if [[ -d "/etc/nginx/conf.d" ]] && [[ -f "$nginx_conf" ]] && [[ "$shell_mode" == "ws" ]]; then
    echo "请选择支持的 TLS 版本（default:3）:"
    echo "请注意,如果你使用 Quantaumlt X / 路由器 / 旧版 Shadowrocket / 低于 4.18.1 版本的 V2ray core 请选择 兼容模式"
    echo "1: TLS1.1 TLS1.2 and TLS1.3（兼容模式）"
    echo "2: TLS1.2 and TLS1.3 (兼容模式)"
    echo "3: TLS1.3 only"
    read -rp "请输入：" tls_version
    [[ -z ${tls_version} ]] && tls_version=3
    if [[ $tls_version == 3 ]]; then
      sed -i 's/ssl_protocols.*/ssl_protocols         TLSv1.3;/' $nginx_conf
      echo -e "${OK} ${GreenBG} 已切换至 TLS1.3 only ${Font}"
    elif [[ $tls_version == 1 ]]; then
      sed -i 's/ssl_protocols.*/ssl_protocols         TLSv1.1 TLSv1.2 TLSv1.3;/' $nginx_conf
      echo -e "${OK} ${GreenBG} 已切换至 TLS1.1 TLS1.2 and TLS1.3 ${Font}"
    else
      sed -i 's/ssl_protocols.*/ssl_protocols         TLSv1.2 TLSv1.3;/' $nginx_conf
      echo -e "${OK} ${GreenBG} 已切换至 TLS1.2 and TLS1.3 ${Font}"
    fi
  else
    echo -e "${Error} ${RedBG} Nginx 或 配置文件不存在 或当前安装版本为 h2 ，请正确安装脚本后执行${Font}"
  fi
}
show_access_log() {
  [ -f ${v2ray_access_log} ] && tail -f ${v2ray_access_log} || echo -e "${RedBG}log文件不存在${Font}"
}
show_error_log() {
  [ -f ${v2ray_error_log} ] && tail -f ${v2ray_error_log} || echo -e "${RedBG}log文件不存在${Font}"
}
ssl_update_manuel() {
  [ -f ${amce_sh_file} ] && "/root/.acme.sh"/acme.sh --cron --home "/root/.acme.sh" || echo -e "${RedBG}证书签发工具不存在，请确认你是否使用了自己的证书${Font}"
  domain="$(info_extraction '\"add\"')"
  "$HOME"/.acme.sh/acme.sh --installcert -d "${domain}" --fullchainpath /data/v2ray.crt --keypath /data/v2ray.key --ecc
}
bbr_boost_sh() {
  [ -f "tcp.sh" ] && rm -rf ./tcp.sh
  wget -N --no-check-certificate "https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcp.sh" && chmod +x tcp.sh && ./tcp.sh
}
mtproxy_sh() {
  echo -e "${Error} ${RedBG} 功能维护，暂不可用 ${Font}"
}

uninstall_all() {
  stop_process_systemd
  [[ -f $v2ray_systemd_file ]] && rm -f $v2ray_systemd_file
  [[ -f $v2ray_bin_dir ]] && rm -f $v2ray_bin_dir
  [[ -f $v2ctl_bin_dir ]] && rm -f $v2ctl_bin_dir
  [[ -d $v2ray_bin_dir_old ]] && rm -rf $v2ray_bin_dir_old
  if [[ -d $nginx_dir ]]; then
    echo -e "${OK} ${Green} 是否卸载 Nginx [Y/N]? ${Font}"
    read -r uninstall_nginx
    case $uninstall_nginx in
    [yY][eE][sS] | [yY])
      rm -rf $nginx_dir
      rm -rf $nginx_systemd_file
      echo -e "${OK} ${Green} 已卸载 Nginx ${Font}"
      ;;
    *) ;;

    esac
  fi
  [[ -d $v2ray_conf_dir ]] && rm -rf $v2ray_conf_dir
  [[ -d $web_dir ]] && rm -rf $web_dir
  echo -e "${OK} ${Green} 是否卸载acme.sh及证书 [Y/N]? ${Font}"
  read -r uninstall_acme
  case $uninstall_acme in
  [yY][eE][sS] | [yY])
    /root/.acme.sh/acme.sh --uninstall
    rm -rf /root/.acme.sh
    rm -rf /data/*
    ;;
  *) ;;
  esac
  systemctl daemon-reload
  echo -e "${OK} ${GreenBG} 已卸载 ${Font}"
}
delete_tls_key_and_crt() {
  [[ -f $HOME/.acme.sh/acme.sh ]] && /root/.acme.sh/acme.sh uninstall >/dev/null 2>&1
  [[ -d $HOME/.acme.sh ]] && rm -rf "$HOME/.acme.sh"
  echo -e "${OK} ${GreenBG} 已清空证书遗留文件 ${Font}"
}
judge_mode() {
  if [ -f $v2ray_bin_dir ] || [ -f $v2ray_bin_dir_old/v2ray ]; then
    if grep -q "ws" $v2ray_qr_config_file >/dev/null 2>&1; then
      shell_mode="ws"
    elif grep -q "h2" $v2ray_qr_config_file >/dev/null 2>&1; then
      shell_mode="h2"
    fi
  fi
}
v2ray_nginx_install() {
  docker-compose up -d
}
install_v2ray_ws_tls() {
  is_root
  init_system
  dependency_install
  basic_optimization
  domain_check
  old_config_exist_check
  port_alterid_set
  port_exist_check 80
  port_exist_check "${port}"
  ssl_judge_and_install
  nginx_pre_install
  v2ray_conf_add_tls
  nginx_conf_add
  web_camouflage
  vmess_qr_config_tls_ws
  tls_type
  v2ray_nginx_install
  basic_information
  vmess_link_image_choice
  show_information
}

update_sh() {
  ol_version=$(curl -L -s https://raw.githubusercontent.com/wulabing/wulabing_v2ray_docker/${github_branch}/install.sh | grep "shell_version=" | head -1 | awk -F '=|"' '{print $3}')
  echo "$ol_version" >$version_cmp
  echo "$shell_version" >>$version_cmp
  if [[ "$shell_version" < "$(sort -rV $version_cmp | head -1)" ]]; then
    echo -e "${OK} ${GreenBG} 存在新版本，是否更新 [Y/N]? ${Font}"
    read -r update_confirm
    case $update_confirm in
    [yY][eE][sS] | [yY])
      wget -N --no-check-certificate https://raw.githubusercontent.com/wulabing/wulabing_v2ray_docker/${github_branch}/install.sh
      echo -e "${OK} ${GreenBG} 更新完成 ${Font}"
      exit 0
      ;;
    *) ;;

    esac
  else
    echo -e "${OK} ${GreenBG} 当前版本为最新版本 ${Font}"
  fi

}
maintain() {
  echo -e "${RedBG}该选项暂时无法使用${Font}"
  echo -e "${RedBG}$1${Font}"
  exit 0
}
list() {
  case $1 in
  tls_modify)
    tls_type
    ;;
  uninstall)
    uninstall_all
    ;;
  crontab_modify)
    acme_cron_update
    ;;
  boost)
    bbr_boost_sh
    ;;
  *)
    menu
    ;;
  esac
}
modify_camouflage_path() {
  [[ -z ${camouflage_path} ]] && camouflage_path=1
  sed -i "/location/c \\\tlocation \/${camouflage_path}\/" ${nginx_conf}       #Modify the camouflage path of the nginx configuration file
  sed -i "/\"path\"/c \\\t  \"path\":\"\/${camouflage_path}\/\"" ${v2ray_conf} #Modify the camouflage path of the v2ray configuration file
  judge "V2ray camouflage path modified"
}

menu() {
  update_sh
  echo -e "\t V2ray 安装管理脚本 ${Red}[${shell_version}]${Font}"
  echo -e "\t---authored by wulabing---"
  echo -e "\thttps://github.com/wulabing\n"
  echo -e "当前已安装版本:${shell_mode}\n"

  echo -e "—————————————— 安装向导 ——————————————"""
  echo -e "${Green}0.${Font}  升级 脚本"
  echo -e "${Green}1.${Font}  安装 V2Ray (Nginx+ws+tls)"
  echo -e "${Green}2.${Font}  安装 V2Ray (http/2)"
  echo -e "${Green}3.${Font}  升级 V2Ray core"
  echo -e "—————————————— 配置变更 ——————————————"
  echo -e "${Green}4.${Font}  变更 UUID"
  echo -e "${Green}5.${Font}  变更 alterid"
  echo -e "${Green}6.${Font}  变更 port"
  echo -e "${Green}7.${Font}  变更 TLS 版本(仅ws+tls有效)"
  echo -e "${Green}18.${Font}  变更伪装路径"
  echo -e "—————————————— 查看信息 ——————————————"
  echo -e "${Green}8.${Font}  查看 实时访问日志"
  echo -e "${Green}9.${Font}  查看 实时错误日志"
  echo -e "${Green}10.${Font} 查看 V2Ray 配置信息"
  echo -e "—————————————— 其他选项 ——————————————"
  echo -e "${Green}11.${Font} 安装 4合1 bbr 锐速安装脚本"
  echo -e "${Green}12.${Font} 安装 MTproxy(支持TLS混淆)"
  echo -e "${Green}13.${Font} 证书 有效期更新"
  echo -e "${Green}14.${Font} 卸载 V2Ray"
  echo -e "${Green}15.${Font} 更新 证书crontab计划任务"
  echo -e "${Green}16.${Font} 清空 证书遗留文件"
  echo -e "${Green}17.${Font} 退出 \n"

  read -rp "请输入数字：" menu_num
  case $menu_num in
  0)
    update_sh
    ;;
  1)
    shell_mode="ws"
    install_v2ray_ws_tls
    ;;
  2)
    shell_mode="h2"
    install_v2_h2
    ;;
  3)
    bash <(curl -L -s https://raw.githubusercontent.com/wulabing/wulabing_v2ray_docker/${github_branch}/v2ray.sh)
    ;;
  4)
    read -rp "请输入UUID:" UUID
    modify_UUID
    start_process_systemd
    ;;
  5)
    read -rp "请输入alterID:" alterID
    modify_alterid
    start_process_systemd
    ;;
  6)
    read -rp "请输入连接端口:" port
    if grep -q "ws" $v2ray_qr_config_file; then
      modify_nginx_port
    elif grep -q "h2" $v2ray_qr_config_file; then
      modify_inbound_port
    fi
    start_process_systemd
    ;;
  7)
    tls_type
    ;;
  8)
    show_access_log
    ;;
  9)
    show_error_log
    ;;
  10)
    basic_information
    if [[ $shell_mode == "ws" ]]; then
      vmess_link_image_choice
    else
      vmess_qr_link_image
    fi
    show_information
    ;;
  11)
    bbr_boost_sh
    ;;
  12)
    mtproxy_sh
    ;;
  13)
    stop_process_systemd
    ssl_update_manuel
    start_process_systemd
    ;;
  14)
    source '/etc/os-release'
    uninstall_all
    ;;
  15)
    acme_cron_update
    ;;
  16)
    delete_tls_key_and_crt
    ;;
  17)
    exit 0
    ;;
  18)
    read -rp "请输入伪装路径(注意！不需要加斜杠 eg:ray):" camouflage_path
    modify_camouflage_path
    start_process_systemd
    ;;
  *)
    echo -e "${RedBG}请输入正确的数字${Font}"
    ;;
  esac
}

judge_mode
list "$1"
