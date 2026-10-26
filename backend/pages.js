const PAGE = (title, body) => `<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title><style>body{font-family:-apple-system,Tahoma,sans-serif;max-width:760px;margin:auto;padding:24px;line-height:1.8;color:#11212d}h1,h2{color:#13827a}.en{direction:ltr;text-align:left;border-top:1px solid #ddd;margin-top:32px;padding-top:16px}</style></head><body>${body}</body></html>`;
const PRIVACY_HTML = PAGE('سياسة الخصوصية — مِناوب', `
<h1>سياسة الخصوصية — مِناوب</h1><p>آخر تحديث: 27 أكتوبر 2026</p>
<p>مِناوب تطبيق داخلي لإدارة مناوبات موظفي المستشفيات. نجمع فقط البيانات اللازمة لتشغيل الخدمة:</p>
<ul><li>بيانات الحساب: الاسم، الرقم الوظيفي، البريد الإلكتروني (اختياري للموظفين)، الجوال (اختياري)، والمسمى والقسم.</li>
<li>بيانات العمل: جداول المناوبات، ساعات الحضور، طلبات الإجازة والتبديل، الإعلانات.</li>
<li>رمز الجهاز للإشعارات (APNs) لإرسال تنبيهات المناوبات.</li></ul>
<p>الكاميرا ومكتبة الصور: يطلب التطبيق الوصول إلى الكاميرا أو الصور فقط عندما تختار «صوّر الجدول الورقي». تُقرأ الصورة بتقنية التعرف على النص من Apple على جهازك مباشرة، ولا تُرفع الصورة ولا النص المستخرج إلى خوادمنا؛ تُحفظ المناوبات التي تؤكدها فقط. صورة الملف الشخصي تبقى على جهازك كذلك.</p>
<p>لا نبيع البيانات ولا نشاركها مع أي طرف ثالث لأغراض إعلانية، ولا نستخدم أدوات تتبع أو إعلانات. تُخزَّن البيانات على خوادم Cloudflare مشفّرة أثناء النقل، وكلمات المرور مجزّأة (PBKDF2).</p>
<p>الوضع المحلي («تجربة التطبيق بدون حساب»): كل البيانات تبقى على جهازك ولا يُرسل شيء إلى الخادم.</p>
<p>حذف الحساب: يمكنك حذف حسابك وبياناتك في أي وقت من التطبيق: الإعدادات ← حذف الحساب. حذف حساب المدير الوحيد يحذف بيانات المستشفى كاملة.</p>
<p>للتواصل: m.alzhrani977@gmail.com</p>
<div class="en"><h2>Privacy Policy — Munawib</h2><p>Last updated: October 27, 2026</p>
<p>Munawib is an internal shift-management app for hospital staff. We collect only what is needed to run the service: account data (name, employee number, optional email/phone, title, department), work data (rosters, attendance hours, leave/swap requests, announcements) and a push-notification device token.</p>
<p>Camera and photo library: access is requested only when you choose “Photograph the paper roster”. The picture is read with Apple's on-device text recognition; neither the photo nor the extracted text is uploaded to our servers — only the shifts you confirm are saved. Profile photos also stay on your device.</p>
<p>We do not sell or share data with third parties for advertising, and we use no tracking or ads. Data is stored on Cloudflare servers, encrypted in transit; passwords are hashed (PBKDF2).</p>
<p>Local mode (“Try the app without an account”): everything stays on your device and nothing is sent to a server.</p>
<p>Account deletion: delete your account and data any time in the app: Settings → Delete account. Deleting the only admin account deletes the hospital's data.</p>
<p>Contact: m.alzhrani977@gmail.com</p></div>`);
const SUPPORT_HTML = PAGE('الدعم — مِناوب', `
<h1>الدعم — مِناوب</h1>
<p>مِناوب يساعد إدارات التمريض في المستشفيات على إعداد جداول المناوبات واعتمادها وإرسال تنبيهات للموظفين.</p>
<h2>الأسئلة الشائعة</h2>
<p><b>كيف أدخل؟</b> الموظف يدخل برمز المستشفى ورقمه الوظيفي بعد الانضمام برمز الدعوة من رئيسة التمريض. المدير يدخل بالبريد.</p>
<p><b>لا تصلني التنبيهات؟</b> الإعدادات ← اختبار التنبيهات، وتأكد من السماح بالإشعارات.</p>
<p><b>حذف الحساب؟</b> الإعدادات ← حذف الحساب.</p>
<p>التواصل: <a href="mailto:m.alzhrani977@gmail.com">m.alzhrani977@gmail.com</a></p>
<p>لوحة الإدارة على الويب: <a href="/admin">/admin</a></p>
<div class="en"><h2>Support — Munawib</h2><p>Munawib helps hospital nursing departments build and approve shift rosters and notify staff.</p>
<p><b>Sign in:</b> staff join with an invite code from their head nurse, then sign in with hospital code + employee number. Admins sign in with email.</p>
<p><b>Not receiving notifications?</b> Settings → Notification test, and allow notifications.</p>
<p><b>Delete account:</b> Settings → Delete account.</p>
<p>Contact: <a href="mailto:m.alzhrani977@gmail.com">m.alzhrani977@gmail.com</a></p></div>`);
