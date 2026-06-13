# MTProxy FakeTLS Installer Guide

This script installs a Telegram MTProto proxy with TLS/FakeTLS mode enabled by default, promoted-channel tag support, Docker deployment, optional Cloudflare DNS automation, and a post-install management menu.

For script support, development, or customization, contact Telegram: `@Bill_999`

## What It Is For

- Telegram MTProto proxy only.
- Not SOCKS5.
- Not a general-purpose VPN.
- Designed for users with a Linux VPS, a domain name, and root access.

## Requirements

- Linux VPS with root access.
- A systemd-based system with working `systemctl`.
- A domain pointing to the VPS.
- Port `443` available, or another port specified with `--port`.
- Docker and Docker Compose. The installer tries to install missing components automatically.

If you use Cloudflare, the DNS record must be DNS only. Do not enable the orange-cloud proxy.

## TLS / FakeTLS

TLS/FakeTLS mode is enabled by default. The installer generates a Telegram MTProxy secret using the `ee` + SNI-domain format and runs the container in TLS-only mode.

This does not require a Let's Encrypt certificate or a website SSL certificate. The SNI domain defaults to your proxy domain, and you can change it during interactive installation.

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/Sunny8886667/mtproxy-faketls-installer/main/install.sh -o install.sh
sudo bash install.sh
```

During installation, the script asks for your proxy domain, port, TLS/FakeTLS SNI domain, and other optional settings.

After installation, the script prints a Telegram import link:

```text
https://t.me/proxy?server=your-proxy-domain.com&port=443&secret=...
```

Open that link in Telegram to add the proxy.

## Promoted Channel Tag

Promoted-channel tags are usually provided by `@MTProxybot`.

Recommended flow:

1. Install the proxy once without a tag.
2. Open the generated proxy link in Telegram.
3. Register or manage the proxy in `@MTProxybot`.
4. Get the 32-character hexadecimal tag.
5. Update the server:

```bash
sudo bash install.sh --update-tag 0123456789abcdef0123456789abcdef
```

If you already have a tag, you can pass it during installation:

```bash
sudo bash install.sh \
  --domain mtproto.example.com \
  --tag 0123456789abcdef0123456789abcdef
```

## Cloudflare DNS Automation

The cleanest setup is to let the installer ask for Cloudflare details during installation:

```text
Manage Cloudflare DNS? auto/yes/no [auto]: yes
Cloudflare API token:
Cloudflare Zone ID, leave empty for auto-detect:
```

Create a Cloudflare API token:

```text
Cloudflare Dashboard -> My Profile -> API Tokens -> Create Token -> Custom token
Permissions:
  Zone - DNS - Edit
  Zone - Zone - Read
Zone Resources:
  Include - Specific zone - your domain
```

You can leave Zone ID empty in the installer. The script will try to detect it from your proxy domain. The installer creates or updates only the exact hostname you enter, using a DNS-only A record.

## Management Commands

After installation, open the interactive menu:

```bash
sudo mtproxy
```

The menu supports start, stop, restart, status, logs, link output, tag update, secret reset, reinstall, and uninstall.

Direct commands are also available:

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

## Uninstall

```bash
sudo bash install.sh --remove
```

This removes:

```text
/opt/mtproxy-faketls
/etc/systemd/system/mtproxy-faketls.service
/usr/local/bin/mtproxy
```

It does not remove Docker and does not delete DNS records.

## Troubleshooting

Check whether port 443 is in use:

```bash
sudo ss -lntp | grep ':443'
```

Check service status:

```bash
sudo systemctl status mtproxy-faketls
```

Follow logs:

```bash
sudo journalctl -u mtproxy-faketls -f
sudo docker logs -f mtproxy-faketls
```

Print the Telegram link again:

```bash
sudo bash install.sh --link
```

## Contact

For script support, development, or customization, contact Telegram: `@Bill_999`
