# راهنمای نصب MTProxy FakeTLS

این اسکریپت برای نصب سریع پروکسی Telegram MTProto با حالت FakeTLS، پشتیبانی از tag کانال تبلیغی، اجرا با Docker، تنظیم اختیاری DNS در Cloudflare و منوی مدیریت پس از نصب ساخته شده است.

برای مشکلات استفاده از اسکریپت، توسعه اسکریپت یا سفارشی‌سازی، در Telegram تماس بگیرید: `@Bill_999`

## این ابزار برای چیست

- فقط برای پروکسی Telegram MTProto است.
- SOCKS5 نیست.
- VPN عمومی نیست.
- برای کاربرانی مناسب است که Linux VPS، دامنه و دسترسی root دارند.

## پیش‌نیازها

- Linux VPS با دسترسی root.
- سیستم مبتنی بر systemd با دستور فعال `systemctl`.
- دامنه‌ای که به VPS اشاره کند.
- آزاد بودن پورت `443`، یا انتخاب پورت دیگر با `--port`.
- Docker و Docker Compose. اسکریپت تلاش می‌کند موارد ناقص را خودکار نصب کند.

اگر از Cloudflare استفاده می‌کنید، رکورد DNS باید DNS only باشد. orange-cloud proxy را فعال نکنید.

## نصب سریع

```bash
curl -fsSL https://raw.githubusercontent.com/Sunny8886667/mtproxy-faketls-installer/main/install.sh -o install.sh
sudo bash install.sh --domain mtproto.example.com
```

به جای `mtproto.example.com` دامنه واقعی خود را وارد کنید.

بعد از نصب، اسکریپت لینک ورود به Telegram را نمایش می‌دهد:

```text
https://t.me/proxy?server=mtproto.example.com&port=443&secret=...
```

این لینک را در Telegram باز کنید تا پروکسی اضافه شود.

## tag کانال تبلیغی

tag کانال تبلیغی معمولا از `@MTProxybot` دریافت می‌شود.

روند پیشنهادی:

1. ابتدا پروکسی را بدون tag نصب کنید.
2. لینک تولیدشده را در Telegram باز کنید.
3. پروکسی را در `@MTProxybot` ثبت یا مدیریت کنید.
4. tag شانزده‌تایی 32 کاراکتری را دریافت کنید.
5. سرور را به‌روزرسانی کنید:

```bash
sudo bash install.sh --update-tag 0123456789abcdef0123456789abcdef
```

اگر از قبل tag دارید، می‌توانید هنگام نصب وارد کنید:

```bash
sudo bash install.sh \
  --domain mtproto.example.com \
  --tag 0123456789abcdef0123456789abcdef
```

## تنظیم خودکار DNS در Cloudflare

یک Cloudflare API token با این دسترسی‌ها بسازید:

```text
Zone:DNS:Edit
Zone:Zone:Read
```

سپس اجرا کنید:

```bash
export CF_API_TOKEN="your_token"
export CF_ZONE_ID="your_zone_id"
sudo -E bash install.sh --domain mtproto.example.com --dns yes
```

اسکریپت فقط همان دامنه کامل واردشده با `--domain` را ایجاد یا به‌روزرسانی می‌کند و رکورد A را به صورت DNS only نگه می‌دارد.

## دستورات مدیریت

پس از نصب، منوی مدیریت را باز کنید:

```bash
sudo mtproxy
```

در این منو می‌توانید سرویس را start، stop، restart کنید، وضعیت و log را ببینید، لینک را نمایش دهید، tag را به‌روزرسانی کنید، secret را reset کنید، دوباره نصب کنید یا حذف کنید.

دستورات مستقیم:

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

## حذف نصب

```bash
sudo bash install.sh --remove
```

موارد زیر حذف می‌شوند:

```text
/opt/mtproxy-faketls
/etc/systemd/system/mtproxy-faketls.service
/usr/local/bin/mtproxy
```

Docker حذف نمی‌شود و رکوردهای DNS نیز پاک نمی‌شوند.

## عیب‌یابی

بررسی اشغال بودن پورت 443:

```bash
sudo ss -lntp | grep ':443'
```

بررسی وضعیت سرویس:

```bash
sudo systemctl status mtproxy-faketls
```

مشاهده log:

```bash
sudo journalctl -u mtproxy-faketls -f
sudo docker logs -f mtproxy-faketls
```

نمایش دوباره لینک Telegram:

```bash
sudo bash install.sh --link
```

## تماس

برای مشکلات استفاده از اسکریپت، توسعه اسکریپت یا سفارشی‌سازی، در Telegram تماس بگیرید: `@Bill_999`
