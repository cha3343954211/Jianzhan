#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="/aiproxy"
NEW_API_DIR="$INSTALL_DIR/new-api"
NEW_API_PORT=3000

SCRIPT_VERSION="1.0.0"

logo() {
    echo -e "${BLUE}"
    echo "  _   _                  ___    ____    ___ "
    echo " | \\ | | _____      __ / _ \\  |  _ \\  |_ _|"
    echo " |  \\| |/ _ \\ \ /\ / /| | | | | |_) |  | | "
    echo " | |\\  |  __/\\ V  V / | |_| | |  __/   | | "
    echo " |_| \\_|\\___| \\_/\\_/   \\___/  |_|     |___|"
    echo ""
    echo -e "   New API 一键部署脚本 v${SCRIPT_VERSION}${NC}"
    echo -e "${NC}"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}请使用 root 用户运行此脚本${NC}"
        exit 1
    fi
}

check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        echo -e "${RED}无法检测操作系统版本${NC}"
        exit 1
    fi

    if [[ "$OS" != *"Ubuntu"* ]] && [[ "$OS" != *"Debian"* ]]; then
        echo -e "${YELLOW}警告：此脚本专为 Ubuntu/Debian 设计，当前系统为 $OS，可能会有问题${NC}"
        read -p "是否继续？(y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    echo -e "${GREEN}操作系统检测通过: $OS $VER${NC}"
}

install_dependencies() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  步骤 1/5: 安装系统依赖${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    echo -e "${YELLOW}更新软件包列表...${NC}"
    apt-get update -qq

    echo -e "${YELLOW}安装基础工具...${NC}"
    apt-get install -y -qq curl wget git nginx certbot python3-certbot-nginx ufw > /dev/null 2>&1

    echo -e "${GREEN}系统依赖安装完成${NC}"
}

install_docker() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  步骤 2/5: 安装 Docker${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    if command -v docker &> /dev/null; then
        echo -e "${GREEN}Docker 已安装: $(docker --version)${NC}"
    else
        echo -e "${YELLOW}正在安装 Docker...${NC}"
        curl -fsSL https://get.docker.com | sh > /dev/null 2>&1
        systemctl start docker
        systemctl enable docker
        echo -e "${GREEN}Docker 安装完成: $(docker --version)${NC}"
    fi
}

prompt_domain() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  域名配置${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    echo -e "${YELLOW}请为 New API 配置解析域名（例如：api.example.com）${NC}"
    echo -e "${YELLOW}如果暂不配置域名，可直接回车使用 IP:端口 访问${NC}"
    echo ""

    read -p "请输入 New API 的域名: " NEW_API_DOMAIN

    echo ""
    echo -e "${GREEN}请确认以下配置信息：${NC}"
    echo "----------------------------------------"
    echo -e "  New API 域名:      ${BLUE}${NEW_API_DOMAIN:-未配置（使用 IP:$NEW_API_PORT 访问）}${NC}"
    echo -e "  安装目录:          ${BLUE}$INSTALL_DIR${NC}"
    echo "----------------------------------------"
    echo ""

    read -p "确认以上配置是否正确？(y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}请重新运行脚本进行配置${NC}"
        exit 0
    fi
}

create_directories() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  步骤 3/5: 部署 New API${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    mkdir -p "$INSTALL_DIR"
    echo -e "${GREEN}创建安装目录: $INSTALL_DIR${NC}"
}

deploy_new_api() {
    echo ""
    echo -e "${YELLOW}正在部署 New API...${NC}"

    NEW_API_DATA_DIR="$NEW_API_DIR/data"
    mkdir -p "$NEW_API_DATA_DIR"
    echo -e "${GREEN}创建数据目录: $NEW_API_DATA_DIR${NC}"

    echo -e "${YELLOW}拉取最新 Docker 镜像...${NC}"
    docker pull calciumion/new-api:latest > /dev/null 2>&1

    if docker ps -a --format '{{.Names}}' | grep -q '^new-api$'; then
        echo -e "${YELLOW}已存在 new-api 容器，正在更新...${NC}"
        docker stop new-api > /dev/null 2>&1
        docker rm new-api > /dev/null 2>&1
    fi

    echo -e "${YELLOW}启动 New API 容器...${NC}"

    if [ -n "$NEW_API_DOMAIN" ]; then
        BIND_ADDR="127.0.0.1"
    else
        BIND_ADDR="0.0.0.0"
    fi

    docker run --name new-api -d --restart always \
        -p "$BIND_ADDR:$NEW_API_PORT:3000" \
        -e TZ=Asia/Shanghai \
        -v "$NEW_API_DATA_DIR:/data" \
        calciumion/new-api:latest > /dev/null 2>&1

    sleep 3

    if docker ps --format '{{.Names}}' | grep -q '^new-api$'; then
        echo -e "${GREEN}New API 部署成功，运行在端口 $NEW_API_PORT${NC}"
    else
        echo -e "${RED}New API 启动失败，请检查日志: docker logs new-api${NC}"
        exit 1
    fi
}

configure_nginx() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  步骤 4/5: 配置 Nginx${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    systemctl stop nginx 2>/dev/null || true

    if [ -n "$NEW_API_DOMAIN" ]; then
        echo -e "${YELLOW}配置 New API Nginx 站点...${NC}"

        cat > /etc/nginx/sites-available/new-api << 'EOF'
server {
    listen 80;
    server_name NEW_API_DOMAIN_PLACEHOLDER;

    client_max_body_size 100M;

    location / {
        proxy_pass http://127.0.0.1:NEW_API_PORT_PLACEHOLDER;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
        proxy_buffering off;
    }
}
EOF

        sed -i "s/NEW_API_DOMAIN_PLACEHOLDER/$NEW_API_DOMAIN/g" /etc/nginx/sites-available/new-api
        sed -i "s/NEW_API_PORT_PLACEHOLDER/$NEW_API_PORT/g" /etc/nginx/sites-available/new-api

        ln -sf /etc/nginx/sites-available/new-api /etc/nginx/sites-enabled/new-api
        echo -e "${GREEN}New API Nginx 配置完成${NC}"
    fi

    rm -f /etc/nginx/sites-enabled/default

    nginx -t > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        systemctl start nginx
        systemctl enable nginx > /dev/null 2>&1
        echo -e "${GREEN}Nginx 配置成功并已启动${NC}"
    else
        echo -e "${RED}Nginx 配置失败，请检查配置文件${NC}"
        nginx -t
        exit 1
    fi
}

setup_firewall() {
    echo ""
    echo -e "${YELLOW}配置防火墙...${NC}"

    ufw --force reset > /dev/null 2>&1 || true
    ufw default deny incoming > /dev/null 2>&1
    ufw default allow outgoing > /dev/null 2>&1
    ufw allow 22/tcp > /dev/null 2>&1
    ufw allow 80/tcp > /dev/null 2>&1
    ufw allow 443/tcp > /dev/null 2>&1
    ufw allow "$NEW_API_PORT/tcp" > /dev/null 2>&1
    ufw --force enable > /dev/null 2>&1

    echo -e "${GREEN}防火墙配置完成（已放行 22/80/443/$NEW_API_PORT 端口）${NC}"
}

setup_ssl() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  步骤 5/5: SSL 证书配置${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    if [ -z "$NEW_API_DOMAIN" ]; then
        echo -e "${YELLOW}未配置域名，跳过 SSL 证书配置${NC}"
        return
    fi

    read -p "是否配置 SSL 证书（需要域名已解析到本服务器）？(y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi

    echo -e "${YELLOW}为 $NEW_API_DOMAIN 申请证书...${NC}"
    certbot --nginx -d "$NEW_API_DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email --redirect 2>/dev/null || \
        echo -e "${YELLOW}SSL 证书申请失败，请稍后手动配置${NC}"

    echo -e "${GREEN}SSL 证书配置完成${NC}"
}

get_server_ip() {
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || hostname -I | awk '{print $1}')
    echo "$SERVER_IP"
}

show_summary() {
    local SERVER_IP
    SERVER_IP=$(get_server_ip)

    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  部署完成！${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo -e "${BLUE}【访问地址】${NC}"
    echo "----------------------------------------"

    if [ -n "$NEW_API_DOMAIN" ]; then
        echo -e "  New API 管理台:  ${GREEN}https://$NEW_API_DOMAIN${NC}"
    else
        echo -e "  New API 管理台:  ${GREEN}http://$SERVER_IP:$NEW_API_PORT${NC}"
    fi

    echo "----------------------------------------"
    echo ""
    echo -e "${BLUE}【安装目录】${NC}"
    echo -e "  主目录:       $INSTALL_DIR"
    echo -e "  New API:      $NEW_API_DIR"
    echo -e "  数据目录:     $NEW_API_DIR/data"
    echo ""
    echo -e "${BLUE}【默认管理员账号】${NC}"
    echo -e "  用户名: ${YELLOW}root${NC}"
    echo -e "  密码:   ${YELLOW}123456${NC}"
    echo -e "  ${RED}请登录后立即修改密码！${NC}"
    echo ""
}

show_maintenance() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  后期维护与更新操作指南${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""
    echo -e "${YELLOW}【New API 维护】${NC}"
    echo -e "  查看状态:    ${GREEN}docker ps | grep new-api${NC}"
    echo -e "  查看日志:    ${GREEN}docker logs -f new-api${NC}"
    echo -e "  重启服务:    ${GREEN}docker restart new-api${NC}"
    echo -e "  停止服务:    ${GREEN}docker stop new-api${NC}"
    echo -e "  启动服务:    ${GREEN}docker start new-api${NC}"
    echo ""
    echo -e "  更新到最新版本:"
    echo -e "    ${GREEN}cd $NEW_API_DIR${NC}"
    echo -e "    ${GREEN}docker pull calciumion/new-api:latest${NC}"
    echo -e "    ${GREEN}docker stop new-api \&\& docker rm new-api${NC}"
    echo -e "    ${GREEN}docker run --name new-api -d --restart always -p $NEW_API_PORT:3000 -e TZ=Asia/Shanghai -v $NEW_API_DIR/data:/data calciumion/new-api:latest${NC}"
    echo ""
    echo -e "${YELLOW}【Nginx 维护】${NC}"
    echo -e "  测试配置:    ${GREEN}nginx -t${NC}"
    echo -e "  重载配置:    ${GREEN}systemctl reload nginx${NC}"
    echo -e "  重启服务:    ${GREEN}systemctl restart nginx${NC}"
    echo -e "  查看日志:    ${GREEN}tail -f /var/log/nginx/error.log${NC}"
    echo ""
    echo -e "${YELLOW}【SSL 证书续期】${NC}"
    echo -e "  手动续期:    ${GREEN}certbot renew${NC}"
    echo -e "  测试续期:    ${GREEN}certbot renew --dry-run${NC}"
    echo ""
    echo -e "${YELLOW}【数据备份】${NC}"
    echo -e "  New API 数据: $NEW_API_DIR/data/ 目录"
    echo -e "  备份命令:    ${GREEN}cp -r $NEW_API_DIR/data /path/to/backup/\$(date +%Y%m%d)${NC}"
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  部署完成！感谢使用 New API 一键部署脚本${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
}

main() {
    clear
    logo
    check_root
    check_os

    echo ""
    echo -e "${YELLOW}即将在服务器上部署以下项目：${NC}"
    echo -e "  1. New API (AI API 网关)"
    echo ""
    read -p "是否继续部署？(y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}部署已取消${NC}"
        exit 0
    fi

    prompt_domain
    install_dependencies
    install_docker
    create_directories
    deploy_new_api
    configure_nginx
    setup_firewall
    setup_ssl
    show_summary
    show_maintenance
}

main "$@"
