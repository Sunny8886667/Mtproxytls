# راهنمای نصب MTProxy FakeTLS

این اسکریپت برای نصب سریع پروکسی Telegram MTProto با حالت TLS/FakeTLS فعال به صورت پیش‌فرض، پشتیبانی از tag کانال تبلیغی، اجرا با Docker، تنظیم اختیاری DNS در Cloudflare و منوی مدیریت پس از نصب ساخته شده است.

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

## TLS / FakeTLS

حالت TLS/FakeTLS به صورت پیش‌فرض فعال است. اسکریپت secret مخصوص Telegram MTProxy را با قالب `ee` + دامنه SNI تولید می‌کند و کانتینر را در حالت TLS-only اجرا می‌کند.

برای این حالت نیازی به گواهی Let's Encrypt یا SSL سایت ندارید. دامنه SNI به صورت پیش‌فرض همان دامنه پروکسی شماست و هنگام نصب می‌توانید آن را تغییر دهید.

## نصب سریع

```bash
curl -fsSL https://raw.githubusercontent.com/Sunny8886667/mtproxy-faketls-installer/main/install.sh -o install.sh
sudo bash install.sh
```

در زمان نصب، اسکریپت دامنه پروکسی، پورت، دامنه SNI برای TLS/FakeTLS و تنظیمات اختیاری دیگر را از شما می‌پرسد.

بعد از نصب، اسکریپت لینک ورود به Telegram را نمایش می‌دهد:

```text
https://t.me/proxy?server=your-proxy-domain.com&port=443&secret=...
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

بهترین روش این است که هنگام نصب، خود اسکریپت اطلاعات Cloudflare را از شما بپرسد:

```text
Manage Cloudflare DNS? auto/yes/no [auto]: yes
Cloudflare API token:
Cloudflare Zone ID, leave empty for auto-detect:
```

یک Cloudflare API token بسازید:

```text
Cloudflare Dashboard -> My Profile -> API Tokens -> Create Token -> Custom token
Permissions:
  Zone - DNS - Edit
  Zone - Zone - Read
Zone Resources:
  Include - Specific zone - your domain
```

در زمان نصب می‌توانید Zone ID را خالی بگذارید. اسکریپت تلاش می‌کند آن را از دامنه پروکسی شما تشخیص دهد. اسکریپت فقط همان hostname واردشده را ایجاد یا به‌روزرسانی می‌کند و رکورد A را به صورت DNS only نگه می‌دارد.

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
