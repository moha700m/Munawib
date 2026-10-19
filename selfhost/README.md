# مِناوب — التشغيل على خادم المستشفى (Self-hosted)

نفس خادم مِناوب السحابي، يعمل داخل شبكة المستشفى على **Docker** بقاعدة بيانات **SQLite** محلية. البيانات لا تغادر خادمكم.

## المتطلبات
- خادم عليه Docker و Docker Compose.
- نطاق داخلي وشهادة HTTPS (تطبيق iPhone يتطلب HTTPS).

## التشغيل في 3 خطوات
```bash
cd selfhost
cp .env.example .env        # عدّل البريد وإعدادات الإشعارات
docker compose up -d --build
```
تحقّق: افتح `http://IP-الخادم:8787/health` ويجب أن يظهر `"runtime":"node"`.

- لوحة التحكم على الويب: `/admin`
- قاعدة البيانات: `selfhost/data/munawib.db` (انسخها احتياطيًا يوميًا).

## ربط التطبيق بالخادم
في شاشة الدخول اضغط ⚙️ ← «خادم المستشفى» ← أدخل الرابط ← «اختبار الاتصال» ← حفظ.
أو أرسل للموظفين: `munawib://server?url=https://munawib.hospital.local`

## HTTPS
ضع الخادم خلف Nginx أو Caddy، مثال Caddy:
```
munawib.hospital.local {
  reverse_proxy localhost:8787
}
```

## الإشعارات (APNs)
ضع ملف `AuthKey_XXXX.p8` في `selfhost/keys/` واملأ `APNS_KEY_ID` و`TEAM_ID` في `.env`. يحتاج اتصالًا صادرًا إلى `api.push.apple.com:443`.

## بدون Docker (Node 22+)
```bash
cd selfhost && node --experimental-sqlite server.mjs
```

## التحديث
```bash
git pull && docker compose up -d --build
```
البيانات تبقى، والأعمدة الجديدة تُضاف تلقائيًا.

## للمطوّر
الكود المشترك في `backend/worker.js`؛ شغّل `node backend/build.mjs` بعد أي تعديل.
