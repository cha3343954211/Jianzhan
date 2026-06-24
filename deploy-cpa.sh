#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="/aiproxy"
CLI_PROXY_UI_DIR="$INSTALL_DIR/cli-proxy-ui"

SCRIPT_VERSION="1.0.0"

logo() {
    echo -e "${BLUE}"
    echo "   ____ _     ___    ____   _    __  __ "
    echo "  / ___| |   |_ _|  |  _ \\ /_\\  |  \\/  |"
    echo " | |   | |    | |   | |_) / _ \\ | |\\/| |"
    echo " | |___| |___ | |   |  __/ ___ \\| |  | |"
    echo "  \\____|_____|___|  |_| /_/   \\_\\_|  |_|"
    echo ""
    echo -e "   CLI Proxy API Management Center 一键部署脚本 v${SCRIPT_VERSION}${NC}"
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

install_bun() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  步骤 2/5: 安装 Bun 运行时${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    if command -v bun &> /dev/null; then
        echo -e "${GREEN}Bun 已安装: $(bun --version)${NC}"
        echo -e "${YELLOW}尝试更新 Bun...${NC}"
        bun upgrade 2>/dev/null || echo -e "${YELLOW}Bun 更新失败，继续使用当前版本${NC}"
    else
        echo -e "${YELLOW}正在安装 Bun...${NC}"
        curl -fsSL https://bun.sh/install | bash > /dev/null 2>&1
        export BUN_INSTALL="$HOME/.bun"
        export PATH="$BUN_INSTALL/bin:$PATH"
        echo 'export BUN_INSTALL="$HOME/.bun"' >> ~/.bashrc
        echo 'export PATH="$BUN_INSTALL/bin:$PATH"' >> ~/.bashrc
        echo -e "${GREEN}Bun 安装完成: $(bun --version)${NC}"
    fi
}

prompt_domain() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  域名配置${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    echo -e "${YELLOW}请为 CLI Proxy UI 配置解析域名（例如：cpa.example.com）${NC}"
    echo -e "${YELLOW}CPA 为静态页面，也可直接部署到任意静态文件托管服务${NC}"
    echo ""

    read -p "请输入 CPA 管理端的域名: " CLI_PROXY_UI_DOMAIN

    echo ""
    echo -e "${GREEN}请确认以下配置信息：${NC}"
    echo "----------------------------------------"
    echo -e "  CPA 管理端域名:    ${BLUE}${CLI_PROXY_UI_DOMAIN:-未配置（需自行配置静态文件服务）}${NC}"
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
    echo -e "${BLUE}  步骤 3/5: 部署 CPA 管理端${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    mkdir -p "$INSTALL_DIR"
    echo -e "${GREEN}创建安装目录: $INSTALL_DIR${NC}"
}

deploy_cli_proxy_ui() {
    echo ""
    echo -e "${YELLOW}正在部署 CLI Proxy API Management Center...${NC}"

    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"

    if [ -d "$CLI_PROXY_UI_DIR" ]; then
        echo -e "${YELLOW}CLI Proxy UI 目录已存在，更新源码...${NC}"
        cd "$CLI_PROXY_UI_DIR"
        git pull > /dev/null 2>&1
    else
        echo -e "${YELLOW}克隆 CLI Proxy UI 仓库...${NC}"
        git clone https://github.com/router-for-me/Cli-Proxy-API-Management-Center.git "$CLI_PROXY_UI_DIR" > /dev/null 2>&1
        cd "$CLI_PROXY_UI_DIR"
    fi

    echo -e "${YELLOW}安装依赖...${NC}"
    bun install --frozen-lockfile > /dev/null 2>&1

    echo -e "${YELLOW}构建项目...${NC}"
    bun run build > /dev/null 2>&1

    if [ -d "$CLI_PROXY_UI_DIR/dist" ]; then
        echo -e "${GREEN}CLI Proxy UI 构建成功${NC}"
    else
        echo -e "${RED}CLI Proxy UI 构建失败${NC}"
        exit 1
    fi

    CLI_PROXY_SERVE_DIR="$INSTALL_DIR/cli-proxy-ui-dist"
    rm -rf "$CLI_PROXY_SERVE_DIR"
    cp -r "$CLI_PROXY_UI_DIR/dist" "$CLI_PROXY_SERVE_DIR"

    echo -e "${GREEN}CLI Proxy UI 部署完成${NC}"
}

configure_nginx() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  步骤 4/5: 配置 Nginx${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    if [ -z "$CLI_PROXY_UI_DOMAIN" ]; then
        echo -e "${YELLOW}未配置域名，跳过 Nginx 配置${NC}"
        echo -e "${YELLOW}静态文件已生成在: $CLI_PROXY_SERVE_DIR${NC}"
        echo -e "${YELLOW}你可以自行配置 Nginx 或其他静态文件服务${NC}"
        return
    fi

    systemctl stop nginx 2>/dev/null || true

    echo -e "${YELLOW}配置 CLI Proxy UI Nginx 站点...${NC}"

    cat > /etc/nginx/sites-available/cli-proxy-ui << 'EOF'
server {
    listen 80;
    server_name CLI_PROXY_UI_DOMAIN_PLACEHOLDER;

    root CLI_PROXY_SERVE_DIR_PLACEHOLDER;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF

    sed -i "s|CLI_PROXY_UI_DOMAIN_PLACEHOLDER|$CLI_PROXY_UI_DOMAIN|g" /etc/nginx/sites-available/cli-proxy-ui
    sed -i "s|CLI_PROXY_SERVE_DIR_PLACEHOLDER|$CLI_PROXY_SERVE_DIR|g" /etc/nginx/sites-available/cli-proxy-ui

    ln -sf /etc/nginx/sites-available/cli-proxy-ui /etc/nginx/sites-enabled/cli-proxy-ui

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
    if [ -z "$CLI_PROXY_UI_DOMAIN" ]; then
        return
    fi

    echo ""
    echo -e "${YELLOW}配置防火墙...${NC}"

    ufw --force reset > /dev/null 2>&1 || true
    ufw default deny incoming > /dev/null 2>&1
    ufw default allow outgoing > /dev/null 2>&1
    ufw allow 22/tcp > /dev/null 2>&1
    ufw allow 80/tcp > /dev/null 2>&1
    ufw allow 443/tcp > /dev/null 2>&1
    ufw --force enable > /dev/null 2>&1

    echo -e "${GREEN}防火墙配置完成（已放行 22/80/443 端口）${NC}"
}

setup_ssl() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  步骤 5/5: SSL 证书配置${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    if [ -z "$CLI_PROXY_UI_DOMAIN" ]; then
        echo -e "${YELLOW}未配置域名，跳过 SSL 证书配置${NC}"
        return
    fi

    read -p "是否配置 SSL 证书（需要域名已解析）？(y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi

    echo -e "${YELLOW}配置 SSL 证书...${NC}"

    if [ -n "$CLI_PROXY_UI_DOMAIN" ]; then
        echo -e "${YELLOW}为 $CLI_PROXY_UI_DOMAIN 申请证书...${NC}"
        certbot --nginx -d "$CLI_PROXY_UI_DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email --redirect 2>/dev/null || \
            echo -e "${YELLOW}SSL 证书申请失败，请稍后手动配置${NC}"
    fi

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

    if [ -n "$CLI_PROXY_UI_DOMAIN" ]; then
        echo -e "  CPA 管理端:      ${GREEN}https://$CLI_PROXY_UI_DOMAIN${NC}"
    else
        echo -e "  静态文件目录:    ${YELLOW}$CLI_PROXY_SERVE_DIR${NC}"
        echo -e "  ${YELLOW}请自行配置 Nginx 或上传到静态文件托管服务${NC}"
    fi

    echo "----------------------------------------"
    echo ""
    echo -e "${BLUE}【安装目录】${NC}"
    echo -e "  主目录:            $INSTALL_DIR"
    echo -e "  CPA 源码:          $CLI_PROXY_UI_DIR"
    echo -e "  CPA 静态文件:      $CLI_PROXY_SERVE_DIR"
    echo ""
    echo -e "${BLUE}【使用说明】${NC}"
    echo -e "  1. CPA 是 New API 的可视化管理前端"
    echo -e "  2. 需要先部署 New API 服务端"
    echo -e "  3. 在 CPA 中配置 New API 的地址和密钥"
    echo ""
}

show_maintenance() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  后期维护与更新操作指南${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""
    echo -e "${YELLOW}【CPA 管理端维护】${NC}"
    echo -e "  更新到最新版本:"
    echo -e "    ${GREEN}cd $CLI_PROXY_UI_DIR${NC}"
    echo -e "    ${GREEN}git pull${NC}"
    echo -e "    ${GREEN}bun install --frozen-lockfile${NC}"
    echo -e "    ${GREEN}bun run build${NC}"
    echo -e "    ${GREEN}rm -rf $CLI_PROXY_SERVE_DIR && cp -r dist $CLI_PROXY_SERVE_DIR${NC}"
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
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  部署完成！感谢使用 CPA 一键部署脚本${NC}"
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
    echo -e "  1. CLI Proxy API Management Center (CPA 管理前端)"
    echo ""
    echo -e "${YELLOW}注意：CPA 是 New API 的可视化管理前端，需要先部署 New API 服务端${NC}"
    echo ""
    read -p "是否继续部署？(y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}部署已取消${NC}"
        exit 0
    fi

    prompt_domain
    install_dependencies
    install_bun
    create_directories
    deploy_cli_proxy_ui
    configure_nginx
    setup_firewall
    setup_ssl
    show_summary
    show_maintenance
}

main "$@"
