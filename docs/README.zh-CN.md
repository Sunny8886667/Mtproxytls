# MTProxy FakeTLS 安装器使用文档

这个脚本用于一键部署 Telegram MTProto 代理，默认启用 TLS/FakeTLS 模式，支持推广频道 tag、Docker 部署、Cloudflare DNS 自动配置和安装后的管理菜单。

脚本使用问题、脚本开发、定制请联系 Telegram：`@Bill_999`

## 适用场景

- 只用于 Telegram MTProto 代理。
- 不是 SOCKS5。
- 不是通用 VPN。
- 适合有 Linux VPS、域名和 root 权限的用户。

## 系统要求

- Linux VPS，拥有 root 权限。
- 系统使用 systemd，并且 `systemctl` 正常可用。
- 域名已经解析到 VPS。
- 端口 `443` 空闲，或者使用 `--port` 指定其他端口。
- Docker 和 Docker Compose。脚本会尝试自动安装缺失组件。

如果使用 Cloudflare，DNS 记录必须是 DNS only，不能开启橙云代理。

## TLS / FakeTLS 说明

脚本默认启用 Telegram MTProxy 的 TLS/FakeTLS 模式。它会生成 `ee` + SNI 域名格式的 Telegram secret，并让容器以 TLS-only 模式运行。

这里不需要申请 Let's Encrypt 证书，也不需要网站 SSL 证书。SNI 域名默认等于你的代理域名，安装过程中可以修改。

## 快速安装

```bash
curl -fsSL https://raw.githubusercontent.com/Sunny8886667/mtproxy-faketls-installer/main/install.sh -o install.sh
sudo bash install.sh
```

安装过程中脚本会提示你输入代理域名、端口、TLS/FakeTLS SNI 域名和其他可选配置。

安装完成后，脚本会输出 Telegram 导入链接：

```text
https://t.me/proxy?server=你的代理域名&port=443&secret=...
```

打开这个链接即可在 Telegram 中添加代理。

## 使用推广频道 Tag

推广频道 tag 一般从 `@MTProxybot` 获取。

推荐流程：

1. 先不带 tag 安装代理。
2. 在 Telegram 里打开脚本输出的代理链接。
3. 到 `@MTProxybot` 注册或管理这个代理。
4. 获取 32 位十六进制 tag。
5. 执行更新命令：

```bash
sudo bash install.sh --update-tag 0123456789abcdef0123456789abcdef
```

如果你已经有 tag，也可以安装时直接传入：

```bash
sudo bash install.sh \
  --domain mtproto.example.com \
  --tag 0123456789abcdef0123456789abcdef
```

## Cloudflare DNS 自动配置

最漂亮的方式是在安装过程中让脚本自动询问 Cloudflare 配置：

```text
Manage Cloudflare DNS? auto/yes/no [auto]: yes
Cloudflare API token:
Cloudflare Zone ID, leave empty for auto-detect:
```

创建 Cloudflare API Token 的步骤：

```text
Cloudflare Dashboard -> My Profile -> API Tokens -> Create Token -> Custom token
权限：
  Zone - DNS - Edit
  Zone - Zone - Read
Zone Resources：
  Include - Specific zone - 你的域名
```

安装时 Zone ID 可以留空，脚本会根据你的代理域名自动识别。脚本只会创建或更新你输入的完整代理域名对应的 A 记录，并保持 DNS only。

## 常用管理命令

安装完成后可以使用：

```bash
sudo mtproxy
```

打开菜单后可以启动、停止、重启、查看状态、查看日志、显示链接、更新 tag、重置 secret、重新安装和卸载。

也可以直接执行：

```bash
sudo mtproxy start
sudo mtproxy stop
sudo mtproxy restart
sudo mtproxy status
sudo mtproxy logs
sudo mtproxy link
sudo mtproxy tag 0123456789abcdef0123456789abcdef
sudo mtproxy reset-secret
sudo mtproxy reinstall
sudo mtproxy uninstall
```

## 卸载

```bash
sudo bash install.sh --remove
```

卸载会删除：

```text
/opt/mtproxy-faketls
/etc/systemd/system/mtproxy-faketls.service
/usr/local/bin/mtproxy
```

不会删除 Docker，也不会删除 DNS 记录。

## 常见问题

端口被占用：

```bash
sudo ss -lntp | grep ':443'
```

服务状态：

```bash
sudo systemctl status mtproxy-faketls
```

查看日志：

```bash
sudo journalctl -u mtproxy-faketls -f
sudo docker logs -f mtproxy-faketls
```

重新输出 Telegram 链接：

```bash
sudo bash install.sh --link
```

## 联系方式

脚本使用问题、脚本开发、定制请联系 Telegram：`@Bill_999`
