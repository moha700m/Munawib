const ADMIN_HTML = "<!doctype html><html lang=\"ar\" dir=\"rtl\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\n<title>مِناوب — لوحة الإدارة</title>\n<script src=\"https://cdn.jsdelivr.net/npm/chart.js@4.4.4/dist/chart.umd.min.js\"></script>\n<style>\n:root{--p:#13827a;--pl:#1a998f;--navy:#0f2a3d;--bg:#f2f7f7;--card:#fff;--t:#11212d;--m:#64748b;--b:#e2e8f0}\n@media(prefers-color-scheme:dark){:root{--bg:#0d1417;--card:#16212a;--t:#e7eef2;--m:#94a3b8;--b:#24323d}}\n*{box-sizing:border-box}body{margin:0;font-family:-apple-system,\"SF Arabic\",\"Segoe UI\",Tahoma,sans-serif;background:var(--bg);color:var(--t)}\nheader{background:var(--navy);color:#fff;padding:12px 16px;display:flex;gap:10px;align-items:center;position:sticky;top:0;z-index:5}\nheader b{font-size:20px}.badge{background:var(--p);padding:3px 10px;border-radius:99px;font-size:12px}\nnav{display:flex;gap:6px;overflow:auto;padding:10px 12px;background:var(--card);border-bottom:1px solid var(--b);position:sticky;top:52px;z-index:4}\nnav button{white-space:nowrap}main{max-width:1200px;margin:auto;padding:16px}\n.card{background:var(--card);border:1px solid var(--b);border-radius:18px;padding:16px;margin-bottom:14px}\n.grid{display:grid;gap:12px;grid-template-columns:repeat(auto-fit,minmax(200px,1fr))}\nbutton,.btn{background:var(--p);color:#fff;border:0;border-radius:12px;padding:10px 14px;font:inherit;cursor:pointer}\nbutton.o{background:transparent;color:var(--p);border:1px solid var(--p)}button.r{background:#dc2626}button:disabled{opacity:.5}\ninput,select,textarea{font:inherit;padding:10px;border-radius:12px;border:1px solid var(--b);background:var(--bg);color:var(--t);width:100%}\nlabel{display:block;font-size:13px;color:var(--m);margin:8px 0 4px}table{width:100%;border-collapse:collapse}td,th{padding:8px;border-bottom:1px solid var(--b);text-align:right;font-size:14px}\n.stat b{font-size:28px;display:block;color:var(--p)}.muted{color:var(--m);font-size:13px}.row{display:flex;gap:8px;flex-wrap:wrap;align-items:end}.row>*{flex:1;min-width:140px}\n.rg{overflow:auto}.rg table td,.rg table th{padding:2px;text-align:center;min-width:34px}.rg td.n{text-align:right;min-width:140px;white-space:nowrap}\n.c{width:32px;height:32px;border-radius:8px;border:0;font-weight:700;padding:0;color:#fff}.cD{background:#2563eb}.cN{background:#7c3aed}.cR{background:#94a3b8}.cL{background:#f97316}.cC{background:#db2777}.c_{background:var(--b);color:var(--m)}\n.pill{padding:2px 8px;border-radius:99px;font-size:12px;background:#fef3c7;color:#92400e}.pill.approved{background:#dcfce7;color:#166534}.pill.rejected{background:#fee2e2;color:#991b1b}\n#toast{position:fixed;bottom:16px;left:50%;transform:translateX(-50%);background:var(--navy);color:#fff;padding:10px 16px;border-radius:12px;display:none;z-index:9}\n.hide{display:none}code{background:var(--bg);padding:2px 6px;border-radius:6px}\n</style></head><body>\n<header><b>مِناوب</b><span class=\"muted\" style=\"color:#9fb\">لوحة الإدارة</span><span style=\"flex:1\"></span><span id=\"who\"></span><span id=\"role\" class=\"badge\"></span><button class=\"o\" id=\"logout\" style=\"color:#fff;border-color:#fff\">خروج</button></header>\n<nav id=\"nav\" class=\"hide\"></nav>\n<main id=\"app\"></main><div id=\"toast\"></div>\n<script>\nconst API=location.origin;let T=localStorage.tok||'',B=null,view='dash',month=new Date();\nconst $=s=>document.querySelector(s),esc=s=>String(s??'').replace(/[&<>\"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',\"'\":'&#39;'}[c]));\nconst toast=m=>{const t=$('#toast');t.textContent=m;t.style.display='block';clearTimeout(t._);t._=setTimeout(()=>t.style.display='none',3500)};\nasync function api(m,p,b){const r=await fetch(API+p,{method:m,headers:{'content-type':'application/json',...(T?{authorization:'Bearer '+T}:{})},body:b?JSON.stringify(b):undefined});const j=await r.json().catch(()=>({}));if(!r.ok){if(r.status===401&&p!=='/auth/login'){logout()}throw new Error(j.error||r.status)}return j}\nconst ROLE={admin:'مدير',head_nurse:'رئيسة تمريض',supervisor:'مشرف',employee:'موظف'};\nconst me=()=>B?.me,isAdmin=()=>me()?.role==='admin',isHead=()=>['admin','head_nurse'].includes(me()?.role),isMgr=()=>['admin','head_nurse','supervisor'].includes(me()?.role);\nconst dn=id=>B.departments.find(d=>d.id===id)?.name||'',un=id=>B.users.find(u=>u.id===id)?.name||'—';\nfunction logout(){T='';localStorage.removeItem('tok');B=null;render()}\n$('#logout').onclick=logout;\nasync function load(){B=await api('GET','/bootstrap');if(!B.me)return;try{B.super=await api('GET','/super/hospitals')}catch{B.super=null}}\nfunction navs(){const v=[['dash','الرئيسية'],['roster','الجدول'],['staff','الموظفون',isMgr()],['req','الموافقات'],['ann','الإعلانات'],['push','تنبيه مخصص',isHead()],['hours','الساعات والتقارير'],['events','الدورات'],['cov','التغطية',isHead()],['depts','الأقسام',isAdmin()],['audit','سجل التدقيق',isHead()],['notif','سجل التنبيهات'],['info','بيانات المستشفى',isHead()],['super','كل المستشفيات',!!B.super]].filter(x=>x[2]!==false);\n $('#nav').innerHTML=v.map(([k,t])=>`<button class=\"${view===k?'':'o'}\" onclick=\"go('${k}')\">${t}</button>`).join('')}\nwindow.go=k=>{view=k;render()};\nasync function render(){const a=$('#app');$('#nav').classList.toggle('hide',!T);$('#logout').classList.toggle('hide',!T);\n if(!T){$('#who').textContent='';$('#role').textContent='';return authView(a)}\n if(!B){a.innerHTML='<div class=\"card\">جارِ التحميل…</div>';try{await load()}catch(e){a.innerHTML=`<div class=\"card\">${esc(e.message)}</div>`;return}}\n $('#who').textContent=me().name;$('#role').textContent=ROLE[me().role];navs();\n try{a.innerHTML=(V[view]||V.dash)();(A[view]||(()=>{}))()}catch(e){a.innerHTML=`<div class=\"card\">${esc(e.message)}</div>`}}\nasync function refresh(){B=null;await render()}\nasync function act(f,msg){try{const r=await f();if(msg)toast(typeof msg==='function'?msg(r):msg);await refresh();return r}catch(e){toast('خطأ: '+e.message)}}\n// ---------- auth ----------\nfunction authView(a){a.innerHTML=`<div class=\"card\" style=\"max-width:460px;margin:30px auto\"><h2>تسجيل الدخول</h2>\n<div class=\"row\"><button id=\"m1\">بالرقم الوظيفي</button><button class=\"o\" id=\"m2\">بالبريد</button><button class=\"o\" id=\"m3\">تسجيل مستشفى</button><button class=\"o\" id=\"m4\">انضمام بدعوة</button></div><div id=\"f\"></div><p id=\"err\" style=\"color:#dc2626\"></p></div>`;\n const forms={m1:`<label>رمز المستشفى</label><input id=\"hc\" value=\"${esc(localStorage.hc||'')}\" dir=\"ltr\"><label>الرقم الوظيفي</label><input id=\"en\" inputmode=\"numeric\" dir=\"ltr\"><label>كلمة المرور</label><input id=\"pw\" type=\"password\"><br><br><button id=\"go\">دخول</button>`,\n m2:`<label>البريد</label><input id=\"em\" type=\"email\" dir=\"ltr\"><label>كلمة المرور</label><input id=\"pw\" type=\"password\"><br><br><button id=\"go\">دخول</button>`,\n m3:`<label>اسم المستشفى</label><input id=\"h\"><label>القسم الأول</label><input id=\"d\" value=\"الطوارئ\"><label>اسمك</label><input id=\"n\"><label>رقمك الوظيفي (اختياري)</label><input id=\"an\" inputmode=\"numeric\" dir=\"ltr\"><label>البريد</label><input id=\"em\" type=\"email\" dir=\"ltr\"><label>كلمة المرور (8+)</label><input id=\"pw\" type=\"password\"><label>رئيسة التمريض (اختياري)</label><div class=\"row\"><input id=\"hn\" placeholder=\"الاسم\"><input id=\"hnn\" placeholder=\"الرقم الوظيفي\" inputmode=\"numeric\"></div><br><button id=\"go\">إنشاء</button>`,\n m4:`<label>رمز الدعوة</label><input id=\"code\" dir=\"ltr\"><label>البريد (اختياري)</label><input id=\"em\" type=\"email\" dir=\"ltr\"><label>كلمة المرور (8+)</label><input id=\"pw\" type=\"password\"><br><br><button id=\"go\">انضمام</button>`};\n const set=k=>{['m1','m2','m3','m4'].forEach(x=>$('#'+x).className=x===k?'':'o');$('#f').innerHTML=forms[k];$('#go').onclick=()=>submit(k)};\n ['m1','m2','m3','m4'].forEach(k=>$('#'+k).onclick=()=>set(k));set('m1');\n async function submit(k){const v=id=>($('#'+id)?.value||'').trim();try{let r;\n  if(k==='m1'){localStorage.hc=v('hc').toUpperCase();r=await api('POST','/auth/login',{hospital_code:v('hc').toUpperCase(),employee_number:v('en'),password:$('#pw').value})}\n  if(k==='m2')r=await api('POST','/auth/login',{email:v('em'),password:$('#pw').value});\n  if(k==='m3'){r=await api('POST','/auth/signup',{hospital:v('h'),department:v('d'),name:v('n'),email:v('em'),password:$('#pw').value,...(v('an')?{employee_number:v('an')}:{}),...(v('hn')?{head_nurse:{name:v('hn'),employee_number:v('hnn')}}:{})});T=r.token;localStorage.tok=T;view='info';created=true;await refresh();return}\n  if(k==='m4')r=await api('POST','/auth/join',{code:v('code').toUpperCase(),email:v('em')||undefined,password:$('#pw').value});\n  T=r.token;localStorage.tok=T;view='dash';await refresh()}catch(e){$('#err').textContent=e.message}}}\n// ---------- views ----------\nconst ym=()=>[month.getFullYear(),month.getMonth()+1],dim=()=>new Date(month.getFullYear(),month.getMonth()+1,0).getDate();\nconst myDept=()=>B._dept||me().department_id||B.departments[0]?.id;\nconst deptSel=()=>isAdmin()?`<select onchange=\"B._dept=this.value;render()\">${B.departments.map(d=>`<option value=\"${d.id}\" ${d.id===myDept()?'selected':''}>${esc(d.name)}</option>`).join('')}</select>`:`<b>${esc(dn(myDept()))}</b>`;\nconst staff=()=>B.users.filter(u=>u.department_id===myDept());\nconst roster=()=>{const[y,m]=ym();return B.rosters.find(r=>r.department_id===myDept()&&r.year===y&&r.month===m)};\nconst today=()=>new Date().toISOString().slice(0,10);\nfunction cov(r,d){let D=0,N=0;for(const u of staff()){const c=r?.grid?.[u.id]?.[d];if(c==='D')D++;if(c==='N')N++}return{D,N}}\nlet created=false;\nfunction infoText(){const L=['بيانات الدخول إلى مِناوب','المستشفى: '+(B.hospital?.name||'')];if(B.hospital?.code)L.push('رمز المستشفى: '+B.hospital.code);const m=me();L.push(ROLE[m.role]+': '+m.name+(m.employee_number?' — الرقم الوظيفي '+m.employee_number:'')+(m.email?' — '+m.email:''));\n for(const u of B.users.filter(u=>u.role==='head_nurse'&&u.id!==m.id))L.push('رئيسة التمريض: '+u.name+(u.employee_number?' — الرقم الوظيفي '+u.employee_number:'')+(u.invite_code?' — كود التفعيل '+u.invite_code:' — مفعّل'));\n L.push('طريقة الدخول: افتح مِناوب ← أدخل الرقم الوظيفي ورمز المستشفى وكلمة المرور. أول مرة: «تفعيل حساب بدعوة».');return L.join('\\n')}\nwindow.cp=(t,b)=>{navigator.clipboard.writeText(t).then(()=>{toast('تم النسخ');if(b){const o=b.textContent;b.textContent='✓ تم النسخ';setTimeout(()=>b.textContent=o,1500)}navigator.vibrate?.(20)})};\nwindow.shareAll=()=>{const t=infoText();if(navigator.share)navigator.share({text:t}).catch(()=>{});else cp(t)};\nconst crow=(k,v)=>`<div class=\"row\" style=\"justify-content:space-between;align-items:center;padding:6px 0;border-bottom:1px solid #e5e7eb\"><span class=\"muted\">${k}</span><span><code style=\"font-size:1.1em\">${esc(v)}</code> <button class=\"o\" onclick=\"cp('${esc(v)}',this)\">نسخ</button></span></div>`;\nconst V={\ninfo(){const m=me();let h=`<div class=\"card\" style=\"max-width:560px\">${created?'<h2>✅ تم إنشاء المستشفى</h2><p class=\"muted\">احتفظ بهذه البيانات وشاركها مع رئيسة التمريض. تجدها لاحقًا في «بيانات المستشفى».</p>':'<h2>بيانات المستشفى</h2>'}\n <div class=\"row\" style=\"justify-content:space-between;padding:6px 0\"><span class=\"muted\">المستشفى</span><b>${esc(B.hospital?.name||'')}</b></div>`;\n if(B.hospital?.code)h+=crow('رمز المستشفى',B.hospital.code);if(m.employee_number)h+=crow('رقمك الوظيفي',m.employee_number);if(m.email)h+=crow('بريدك',m.email);\n for(const u of B.users.filter(u=>u.role==='head_nurse'&&u.id!==m.id)){h+=`<h3 style=\"margin-top:14px\">رئيسة التمريض: ${esc(u.name)}</h3>`;if(u.employee_number)h+=crow('الرقم الوظيفي',u.employee_number);h+=u.invite_code?crow('كود التفعيل',u.invite_code):'<p style=\"color:#16a34a\">الحساب مفعّل ✓</p>'}\n created=false;return h+`<br><button onclick=\"shareAll()\">مشاركة الكل</button><p class=\"muted\" style=\"font-size:.8em\">لا تتضمن المشاركة أي كلمة مرور.</p></div>`},\ndash(){const dep=B.departments.find(d=>d.id===myDept())||{};const r=roster(),d=new Date().getDate(),c=cov(r,d);const pend=B.leaves.filter(x=>x.status==='pending').length+B.swaps.filter(x=>x.status==='pending').length;\n const onLeave=B.leaves.filter(l=>l.status==='approved'&&l.start_date<=today()&&l.end_date>=today());\n return `<div class=\"card row\"><div>${deptSel()}</div><div class=\"muted\">${esc(B.hospital?.name)} ${B.hospital?.code?`· رمز المستشفى <code>${B.hospital.code}</code>`:''}</div></div>\n <div class=\"grid\"><div class=\"card stat\">بانتظار الموافقة<b>${pend}</b></div><div class=\"card stat\">تغطية اليوم<b>D${c.D} · N${c.N}</b><span class=\"muted\">الحد الأدنى D${dep.min_day??2} · N${dep.min_night??1}</span></div>\n <div class=\"card stat\">في إجازة اليوم<b>${onLeave.length}</b><span class=\"muted\">${onLeave.map(l=>esc(un(l.user_id))).join('، ')}</span></div><div class=\"card stat\">الموظفون<b>${staff().length}</b><span class=\"muted\">${staff().filter(u=>u.joined).length} منضم</span></div>\n <div class=\"card stat\">حالة الجدول<b style=\"font-size:20px\">${r?{draft:'مسودة',review:'مراجعة',approved:'معتمد'}[r.status]:'لا يوجد'}</b></div></div>\n <div class=\"card\"><h3>إجراءات سريعة</h3><div class=\"row\"><button onclick=\"go('roster')\">الجدول</button><button onclick=\"go('req')\">الموافقات</button>${isHead()?`<button onclick=\"go('push')\">تنبيه</button><button onclick=\"go('staff')\">إضافة موظف</button>`:''}<button onclick=\"go('hours')\">التقارير</button></div></div>`},\nroster(){const[y,m]=ym(),r=roster(),n=dim(),dep=B.departments.find(d=>d.id===myDept())||{};B._grid=JSON.parse(JSON.stringify(r?.grid||{}));\n let h=`<div class=\"card\"><div class=\"row\"><button class=\"o\" onclick=\"month.setMonth(month.getMonth()-1);render()\">→ السابق</button><div style=\"text-align:center\"><b>${m}/${y}</b> ${deptSel()}<div class=\"muted\">الحالة: ${r?r.status:'جديد'}</div></div><button class=\"o\" onclick=\"month.setMonth(month.getMonth()+1);render()\">التالي ←</button></div></div>\n <div class=\"card rg\"><table><tr><th>الموظف</th>${Array.from({length:n},(_,i)=>`<th>${i+1}</th>`).join('')}<th>ساعات</th></tr>`;\n for(const u of staff()){h+=`<tr><td class=\"n\">${esc(u.name)} <span class=\"muted\">${esc(u.employee_number||'')}</span></td>`;for(let d=1;d<=n;d++){const c=B._grid[u.id]?.[d]||'';h+=`<td><button class=\"c c${c||'_'}\" data-u=\"${u.id}\" data-d=\"${d}\" ${isMgr()?'':'disabled'}>${c||'·'}</button></td>`}h+=`<td id=\"h_${u.id}\"></td></tr>`}\n h+=`<tr><td class=\"n muted\">التغطية D/N</td>${Array.from({length:n},(_,i)=>{const c=cov({grid:B._grid},i+1),bad=c.D<(dep.min_day??2)||c.N<(dep.min_night??1);return `<td class=\"muted\" style=\"${bad?'background:#fee2e2;color:#991b1b':''}\">${c.D}/${c.N}</td>`}).join('')}<td></td></tr></table></div>\n <div class=\"card row\">${isMgr()?`<button onclick=\"saveRoster()\">حفظ</button><button class=\"o\" onclick=\"saveRoster('review')\">حفظ المراجعة</button><button onclick=\"saveRoster('approved')\">اعتماد وإرسال</button><button class=\"o\" onclick=\"fairFill()\">تعبئة عادلة</button>`:''}<button class=\"o\" onclick=\"exportRoster()\">تصدير CSV</button></div>`;return h},\nstaff(){return `<div class=\"card\"><h3>إضافة موظف</h3><div class=\"row\"><input id=\"sn\" placeholder=\"الاسم\"><input id=\"st\" placeholder=\"المسمى\" value=\"Nurse\"><input id=\"se\" placeholder=\"الرقم الوظيفي\" inputmode=\"numeric\"><input id=\"sp\" placeholder=\"الجوال\">\n <select id=\"sr\"><option value=\"employee\">موظف</option><option value=\"supervisor\">مشرف</option>${isAdmin()?'<option value=\"head_nurse\">رئيسة تمريض</option><option value=\"admin\">مدير</option>':''}</select>${isAdmin()?`<select id=\"sd\">${B.departments.map(d=>`<option value=\"${d.id}\" ${d.id===myDept()?'selected':''}>${esc(d.name)}</option>`).join('')}</select>`:''}<button onclick=\"addStaff()\">إضافة</button></div></div>\n <div class=\"card\"><input id=\"q\" placeholder=\"بحث بالاسم أو الرقم\" oninput=\"filterStaff(this.value)\"><table id=\"stbl\"><tr><th>الاسم</th><th>الرقم</th><th>القسم</th><th>الدور</th><th>الدعوة</th><th></th></tr>${B.users.filter(u=>isAdmin()||u.department_id===me().department_id).map(u=>`<tr data-s=\"${esc((u.name+' '+(u.employee_number||'')).toLowerCase())}\"><td>${esc(u.name)}<div class=\"muted\">${esc(u.title||'')}</div></td><td>${esc(u.employee_number||'')}</td><td>${esc(dn(u.department_id))}</td>\n <td>${isHead()&&u.id!==me().id&&(isAdmin()||['employee','supervisor'].includes(u.role))?`<select onchange=\"setRole('${u.id}',this.value)\">${Object.entries(ROLE).filter(([k])=>isAdmin()||['employee','supervisor'].includes(k)).map(([k,v])=>`<option value=\"${k}\" ${u.role===k?'selected':''}>${v}</option>`).join('')}</select>`:ROLE[u.role]}</td>\n <td>${u.joined?'<span class=\"pill approved\">منضم</span>':u.invite_code?`<code>${u.invite_code}</code> <button class=\"o\" onclick=\"navigator.clipboard.writeText('${u.invite_code}');toast('تم النسخ')\">نسخ</button>`:'—'}</td>\n <td>${isHead()&&u.id!==me().id?`<button class=\"o\" onclick=\"editStaff('${u.id}')\">تعديل</button> <button class=\"r\" onclick=\"delStaff('${u.id}')\">حذف</button>`:''}</td></tr>`).join('')}</table></div>`},\nreq(){const row=(t,d,s,id,k)=>`<tr><td>${t}</td><td>${d}</td><td><span class=\"pill ${s}\">${{pending:'قيد الانتظار',approved:'موافق',rejected:'مرفوض'}[s]}</span></td><td>${isMgr()&&s==='pending'?`<button onclick=\"decide('${k}','${id}',true)\">موافقة</button> <button class=\"r\" onclick=\"decide('${k}','${id}',false)\">رفض</button>`:''}</td></tr>`;\n return `<div class=\"card\"><h3>طلب إجازة</h3><div class=\"row\"><input type=\"date\" id=\"ls\"><input type=\"date\" id=\"le\"><input id=\"lr\" placeholder=\"السبب\"><button onclick=\"reqLeave()\">إرسال</button></div></div>\n <div class=\"card\"><h3>طلب تبديل</h3><div class=\"row\"><select id=\"sw\">${B.users.filter(u=>u.id!==me().id&&u.department_id===me().department_id).map(u=>`<option value=\"${u.id}\">${esc(u.name)}</option>`).join('')}</select><input type=\"date\" id=\"swd\"><input id=\"swn\" placeholder=\"ملاحظة\"><button onclick=\"reqSwap()\">إرسال</button></div></div>\n <div class=\"card\"><h3>الإجازات</h3><table>${B.leaves.map(l=>row(esc(un(l.user_id)),`${l.start_date} ← ${l.end_date} ${esc(l.reason||'')}`,l.status,l.id,'leaves')).join('')||'<tr><td class=\"muted\">لا يوجد</td></tr>'}</table></div>\n <div class=\"card\"><h3>التبديلات</h3><table>${B.swaps.map(s=>row(`${esc(un(s.from_user))} ⇄ ${esc(un(s.to_user))}`,`${s.date} ${esc(s.note||'')}`,s.status,s.id,'swaps')).join('')||'<tr><td class=\"muted\">لا يوجد</td></tr>'}</table></div>`},\nann(){return `${isMgr()?`<div class=\"card\"><h3>إعلان جديد</h3><input id=\"at\" placeholder=\"العنوان\"><br><br><textarea id=\"ab\" rows=\"3\" placeholder=\"النص\"></textarea><br><br><button onclick=\"postAnn()\">نشر وإرسال تنبيه</button></div>`:''}\n <div class=\"card\"><h3>لوحة الإعلانات</h3>${B.announcements.map(a=>`<div style=\"border-bottom:1px solid var(--b);padding:8px 0\"><b>${esc(a.title)}</b><div>${esc(a.body||'')}</div><div class=\"muted\">${esc(a.author||'')} · ${new Date(a.created_at).toLocaleString('ar')}</div></div>`).join('')||'<p class=\"muted\">لا توجد إعلانات</p>'}</div>`},\npush(){return `<div class=\"card\"><h3>تنبيه مخصص</h3><input id=\"pt\" placeholder=\"العنوان\"><br><br><textarea id=\"pb\" rows=\"3\" placeholder=\"النص\"></textarea><label><input type=\"checkbox\" id=\"pall\" checked style=\"width:auto\"> كل القسم</label>\n <div id=\"plist\">${staff().map(u=>`<label><input type=\"checkbox\" class=\"pu\" value=\"${u.id}\" style=\"width:auto\"> ${esc(u.name)}</label>`).join('')}</div><br><button onclick=\"sendPush()\">إرسال</button> <button class=\"o\" onclick=\"act(()=>api('POST','/push/test'),r=>'اختبار: '+r.sent+'/'+r.devices)\">اختبار على أجهزتي</button></div>`},\nhours(){const[y,m]=ym(),pre=`${y}-${String(m).padStart(2,'0')}`;const r=roster();const rows=staff().map(u=>{const sh=Object.values(r?.grid?.[u.id]||{}).filter(c=>c==='D'||c==='N').length;const lg=B.attendance.filter(a=>a.user_id===u.id&&a.date.startsWith(pre)).reduce((s,a)=>s+a.hours,0);return{u,sh:sh*12,lg}});B._hrows=rows;\n return `<div class=\"card row\"><button class=\"o\" onclick=\"month.setMonth(month.getMonth()-1);render()\">→</button><b style=\"text-align:center\">${m}/${y}</b><button class=\"o\" onclick=\"month.setMonth(month.getMonth()+1);render()\">←</button>${deptSel()}</div>\n <div class=\"card\"><h3>تسجيل ساعات</h3><div class=\"row\"><select id=\"hu\">${staff().map(u=>`<option value=\"${u.id}\">${esc(u.name)}</option>`).join('')}</select><input type=\"date\" id=\"hd\" value=\"${today()}\"><select id=\"hk\"><option value=\"H\">حضور فعلي</option><option value=\"OT\">إضافي</option><option value=\"SB\">استعداد</option><option value=\"CT\">تعويضي</option><option value=\"LV\">إجازة</option><option value=\"CR\">دورة</option></select><input id=\"hh\" type=\"number\" value=\"12\" step=\"0.5\"><button onclick=\"addHours()\">إضافة</button></div></div>\n <div class=\"card\"><canvas id=\"ch\" height=\"120\"></canvas></div><div class=\"card\"><canvas id=\"cc\" height=\"90\"></canvas></div>\n <div class=\"card\"><table><tr><th>الموظف</th><th>ساعات الجدول</th><th>المسجلة</th></tr>${rows.map(x=>`<tr><td>${esc(x.u.name)}</td><td>${x.sh}</td><td>${x.lg}</td></tr>`).join('')}</table><br><button class=\"o\" onclick=\"exportHours()\">تصدير CSV</button> <button class=\"o\" onclick=\"window.print()\">طباعة / PDF</button></div>`},\nevents(){return `${isMgr()?`<div class=\"card\"><h3>دورة / فعالية</h3><div class=\"row\"><input id=\"et\" placeholder=\"العنوان\"><input id=\"ed\" type=\"datetime-local\"><input id=\"el\" placeholder=\"المكان\"><input id=\"ea\" placeholder=\"الفئة\"><button onclick=\"addEvent()\">إضافة</button></div></div>`:''}\n <div class=\"card\"><table>${B.events.map(e=>`<tr><td><b>${esc(e.title)}</b></td><td>${new Date(e.date).toLocaleString('ar')}</td><td>${esc(e.location||'')}</td><td>${esc(e.audience||'')}</td><td>${isMgr()?`<button class=\"r\" onclick=\"act(()=>api('DELETE','/events/${e.id}'),'حُذف')\">حذف</button>`:''}</td></tr>`).join('')||'<tr><td class=\"muted\">لا يوجد</td></tr>'}</table></div>`},\ncov(){const d=B.departments.find(x=>x.id===myDept())||{};return `<div class=\"card\"><h3>الحد الأدنى للتغطية — ${deptSel()}</h3><div class=\"row\"><div><label>نهاري ≥</label><input id=\"mnd\" type=\"number\" value=\"${d.min_day??2}\"></div><div><label>ليلي ≥</label><input id=\"mnn\" type=\"number\" value=\"${d.min_night??1}\"></div><button onclick=\"act(()=>api('PATCH','/departments/${myDept()}',{min_day:+$('#mnd').value,min_night:+$('#mnn').value}),'تم الحفظ')\">حفظ</button></div></div>`},\ndepts(){return `<div class=\"card\"><h3>الأقسام</h3><div class=\"row\"><input id=\"dn\" placeholder=\"قسم جديد\"><button onclick=\"act(()=>api('POST','/departments',{name:$('#dn').value}),'أُضيف')\">إضافة</button></div><table>${B.departments.map(d=>`<tr><td>${esc(d.name)}</td><td>${B.users.filter(u=>u.department_id===d.id).length} موظف</td><td><button class=\"r\" onclick=\"confirm('حذف القسم؟')&&act(()=>api('DELETE','/departments/${d.id}'),'حُذف')\">حذف</button></td></tr>`).join('')}</table></div>`},\naudit(){return `<div class=\"card\"><h3>سجل التدقيق</h3><table><tr><th>الوقت</th><th>المستخدم</th><th>الإجراء</th><th>التفاصيل</th></tr>${(B.audit_log||[]).map(a=>`<tr><td class=\"muted\">${new Date(a.created_at).toLocaleString('ar')}</td><td>${esc(a.user_name)}</td><td>${esc(a.action)}</td><td class=\"muted\">${esc(a.detail)}</td></tr>`).join('')}</table></div>`},\nnotif(){return `<div class=\"card\"><h3>سجل التنبيهات (لي)</h3><table>${B.notifications.map(n=>`<tr><td>${esc(n.title)}</td><td>${esc(n.body||'')}</td><td class=\"muted\">${esc(n.result)}</td><td class=\"muted\">${new Date(n.created_at).toLocaleString('ar')}</td></tr>`).join('')||'<tr><td class=\"muted\">لا يوجد</td></tr>'}</table></div>`},\nsuper(){return `<div class=\"card\"><h3>كل المستشفيات (${B.super.length})</h3><table><tr><th>المستشفى</th><th>الرمز</th><th>الأقسام</th><th>الموظفون</th><th>الأجهزة</th><th>الإنشاء</th></tr>${B.super.map(h=>`<tr><td>${esc(h.name)}</td><td><code>${esc(h.code)}</code></td><td>${h.departments}</td><td>${h.users}</td><td>${h.devices}</td><td class=\"muted\">${new Date(h.created_at).toLocaleDateString('ar')}</td></tr>`).join('')}</table><p class=\"muted\">لإنشاء مستشفى جديد: سجّل خروج ← «تسجيل مستشفى».</p></div>`}\n};\nconst A={roster(){document.querySelectorAll('button.c').forEach(b=>b.onclick=()=>{const o=['D','N','R','L','C',''],u=b.dataset.u,d=b.dataset.d;B._grid[u]??={};const c=B._grid[u][d]||'';const nx=o[(o.indexOf(c)+1)%o.length];if(nx)B._grid[u][d]=nx;else delete B._grid[u][d];b.className='c c'+(nx||'_');b.textContent=nx||'·';hrs()});hrs()},\nhours(){const r=B._hrows;new Chart($('#ch'),{type:'bar',data:{labels:r.map(x=>x.u.name),datasets:[{label:'ساعات الجدول',data:r.map(x=>x.sh),backgroundColor:'#13827a'},{label:'المسجلة',data:r.map(x=>x.lg),backgroundColor:'#7c3aed'}]},options:{indexAxis:'y'}});\n const ro=roster(),n=dim(),ds=Array.from({length:n},(_,i)=>cov(ro,i+1));new Chart($('#cc'),{type:'line',data:{labels:ds.map((_,i)=>i+1),datasets:[{label:'نهاري',data:ds.map(x=>x.D),borderColor:'#2563eb'},{label:'ليلي',data:ds.map(x=>x.N),borderColor:'#7c3aed'}]}})}};\nfunction hrs(){for(const u of staff()){const e=$('#h_'+u.id);if(e)e.textContent=Object.values(B._grid[u.id]||{}).filter(c=>c==='D'||c==='N').length*12}}\nwindow.saveRoster=async st=>{const[y,m]=ym();await act(async()=>{const r=await api('PUT','/rosters',{department_id:myDept(),year:y,month:m,grid:B._grid});if(st)return api('POST',`/rosters/${r.id}/status`,{status:st});return r},r=>r.push?`تم — أُرسل ${r.push.filter(x=>x.status===200).length} تنبيه`:'تم الحفظ')};\nwindow.fairFill=()=>{const dep=B.departments.find(d=>d.id===myDept())||{},minD=dep.min_day??2,minN=dep.min_night??1,[y,m]=ym(),n=dim(),S=staff().map(u=>u.id),tot={},ni={},wk={},last={};\n for(let d=1;d<=n;d++){const w=[5,6].includes(new Date(y,m-1,d).getDay());let free=S.filter(u=>!['L','C'].includes(B._grid[u]?.[d]));\n  const pick=(k,night)=>{const c=free.filter(u=>night||last[u]!=='N').sort((a,b)=>((tot[a]||0)-(tot[b]||0))||(night?(ni[a]||0)-(ni[b]||0):0)||(w?(wk[a]||0)-(wk[b]||0):0)).slice(0,k);free=free.filter(u=>!c.includes(u));return c};\n  const N=pick(minN,true),D=pick(minD,false);for(const u of S){B._grid[u]??={};const cur=B._grid[u][d];const c=N.includes(u)?'N':D.includes(u)?'D':(['L','C'].includes(cur)?cur:'R');B._grid[u][d]=c;if(c==='D'||c==='N'){tot[u]=(tot[u]||0)+1;if(w)wk[u]=(wk[u]||0)+1}if(c==='N')ni[u]=(ni[u]||0)+1;last[u]=c}}\n const g=B._grid;const[yy,mm]=ym();const r=roster();if(r)r.grid=g;else B.rosters.push({department_id:myDept(),year:yy,month:mm,status:'draft',grid:g});$('#app').innerHTML=V.roster();B._grid=g;A.roster();toast('تمت التعبئة — اضغط حفظ')};\nconst csv=(rows,name)=>{const b=new Blob(['\\ufeff'+rows.map(r=>r.map(c=>`\"${String(c).replace(/\"/g,'\"\"')}\"`).join(',')).join('\\n')],{type:'text/csv'});const a=document.createElement('a');a.href=URL.createObjectURL(b);a.download=name;a.click()};\nwindow.exportRoster=()=>{const[y,m]=ym(),n=dim();csv([['الموظف','الرقم',...Array.from({length:n},(_,i)=>i+1)],...staff().map(u=>[u.name,u.employee_number||'',...Array.from({length:n},(_,i)=>B._grid[u.id]?.[i+1]||'')])],`roster-${y}-${m}.csv`)};\nwindow.exportHours=()=>{const[y,m]=ym();csv([['الموظف','ساعات الجدول','المسجلة'],...B._hrows.map(x=>[x.u.name,x.sh,x.lg])],`hours-${y}-${m}.csv`)};\nwindow.addStaff=()=>act(()=>api('POST','/employees',{name:$('#sn').value,title:$('#st').value,employee_number:$('#se').value.trim(),phone:$('#sp').value,role:$('#sr').value,department_id:$('#sd')?.value||myDept()}),r=>'رمز الدعوة: '+r.invite_code);\nwindow.setRole=(id,r)=>act(()=>api('POST',`/employees/${id}/role`,{role:r}),'تم تغيير الصلاحية');\nwindow.delStaff=id=>confirm('حذف الموظف؟')&&act(()=>api('DELETE','/employees/'+id),'حُذف');\nwindow.editStaff=id=>{const u=B.users.find(x=>x.id===id);const n=prompt('الاسم',u.name);if(n===null)return;const e=prompt('الرقم الوظيفي',u.employee_number||'');if(e===null)return;const t=prompt('المسمى',u.title||'');act(()=>api('PATCH','/employees/'+id,{name:n,employee_number:e,title:t??u.title}),'تم التعديل')};\nwindow.filterStaff=q=>document.querySelectorAll('#stbl tr[data-s]').forEach(r=>r.style.display=r.dataset.s.includes(q.toLowerCase())?'':'none');\nwindow.decide=(k,id,ok)=>act(()=>api('POST',`/${k}/${id}/decision`,{approve:ok}),ok?'تمت الموافقة':'تم الرفض');\nwindow.reqLeave=()=>act(()=>api('POST','/leaves',{start_date:$('#ls').value,end_date:$('#le').value,reason:$('#lr').value}),'أُرسل الطلب');\nwindow.reqSwap=()=>act(()=>api('POST','/swaps',{to_user:$('#sw').value,date:$('#swd').value,note:$('#swn').value}),'أُرسل الطلب');\nwindow.postAnn=()=>act(()=>api('POST','/announcements',{title:$('#at').value,body:$('#ab').value,department_id:isAdmin()?null:me().department_id}),'نُشر الإعلان');\nwindow.sendPush=()=>{const ids=$('#pall').checked?[]:[...document.querySelectorAll('.pu:checked')].map(x=>x.value);act(()=>api('POST','/push/custom',{title:$('#pt').value,body:$('#pb').value,user_ids:ids,department_id:myDept()}),r=>`أُرسل إلى ${r.recipients} موظف (${r.sent}/${r.devices} جهاز)`)};\nwindow.addHours=()=>act(()=>api('POST','/attendance',{user_id:$('#hu').value,date:$('#hd').value,kind:$('#hk').value,hours:+$('#hh').value}),'سُجّلت');\nwindow.addEvent=()=>act(()=>api('POST','/events',{title:$('#et').value,date:new Date($('#ed').value).toISOString(),location:$('#el').value,audience:$('#ea').value}),'أُضيفت');\nrender();\n</script></body></html>\n";
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

// Munawib API — Cloudflare Worker + D1 + APNs
const enc = new TextEncoder();
const b64u = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const b64uStr = (s) => b64u(enc.encode(s));
const fromB64u = (s) => Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((s.length + 3) % 4)), c => c.charCodeAt(0));
const uid = () => crypto.randomUUID();
const now = () => Date.now();
const json = (d, s = 200) => new Response(JSON.stringify(d), { status: s, headers: { 'content-type': 'application/json; charset=utf-8', 'access-control-allow-origin': '*' } });
class HttpError extends Error { constructor(s, m, retry) { super(m); this.status = s; this.retry = retry; } }
const need = (c, s, m) => { if (!c) throw new HttpError(s, m); };

async function hashPw(pw, saltB64) {
  const salt = saltB64 ? fromB64u(saltB64) : crypto.getRandomValues(new Uint8Array(16));
  const key = await crypto.subtle.importKey('raw', enc.encode(pw), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt, iterations: 100000 }, key, 256);
  return `pbkdf2$100000$${b64u(salt)}$${b64u(bits)}`;
}
async function verifyPw(pw, stored) {
  if (!stored) return false;
  const [, , salt, h] = stored.split('$');
  const again = (await hashPw(pw, salt)).split('$')[3];
  if (again.length !== h.length) return false;
  let r = 0; for (let i = 0; i < h.length; i++) r |= again.charCodeAt(i) ^ h.charCodeAt(i);
  return r === 0;
}
async function hmacKey(env) { return crypto.subtle.importKey('raw', enc.encode(env.JWT_SECRET), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify']); }
async function signJWT(env, payload) {
  const h = b64uStr(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const p = b64uStr(JSON.stringify({ ...payload, exp: Math.floor(now() / 1000) + 60 * 60 * 24 * 30 }));
  const sig = await crypto.subtle.sign('HMAC', await hmacKey(env), enc.encode(`${h}.${p}`));
  return `${h}.${p}.${b64u(sig)}`;
}
async function verifyJWT(env, t) {
  const [h, p, s] = (t || '').split('.'); if (!s) return null;
  const ok = await crypto.subtle.verify('HMAC', await hmacKey(env), fromB64u(s), enc.encode(`${h}.${p}`));
  if (!ok) return null;
  const pl = JSON.parse(new TextDecoder().decode(fromB64u(p)));
  return pl.exp > now() / 1000 ? pl : null;
}

// ---------- APNs ----------
let apnsCache = null;
async function apnsJWT(env) {
  if (apnsCache && apnsCache.t > now() - 50 * 60 * 1000) return apnsCache.jwt;
  const pem = env.APNS_KEY.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const key = await crypto.subtle.importKey('pkcs8', Uint8Array.from(atob(pem), c => c.charCodeAt(0)), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const h = b64uStr(JSON.stringify({ alg: 'ES256', kid: env.APNS_KEY_ID }));
  const p = b64uStr(JSON.stringify({ iss: env.TEAM_ID, iat: Math.floor(now() / 1000) }));
  const sig = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, enc.encode(`${h}.${p}`));
  apnsCache = { t: now(), jwt: `${h}.${p}.${b64u(sig)}` };
  return apnsCache.jwt;
}
async function apnsSend(env, token, envName, title, body, data = {}) {
  const host = envName === 'sandbox' ? 'api.sandbox.push.apple.com' : 'api.push.apple.com';
  const r = await (globalThis.__apnsFetch || fetch)(`https://${host}/3/device/${token}`, {
    method: 'POST',
    headers: { authorization: `bearer ${await apnsJWT(env)}`, 'apns-topic': env.APNS_TOPIC || 'com.mohlab.munawib', 'apns-push-type': 'alert', 'apns-priority': '10' },
    body: JSON.stringify({ aps: { alert: { title, body }, sound: 'default', badge: 1 }, ...data }),
  });
  let reason = ''; if (r.status !== 200) { try { reason = (await r.json()).reason; } catch { } }
  return { status: r.status, reason, host };
}
async function pushToUsers(env, hospitalId, userIds, title, body, data) {
  const results = [];
  if (!userIds.length) return results;
  const ph = userIds.map(() => '?').join(',');
  const { results: toks } = await env.DB.prepare(`SELECT token,user_id,env FROM device_tokens WHERE user_id IN (${ph})`).bind(...userIds).all();
  for (const t of toks) {
    let r;
    try {
      r = await apnsSend(env, t.token, t.env, title, body, data);
      if (r.status === 400 && r.reason === 'BadDeviceToken') {
        const other = t.env === 'sandbox' ? 'production' : 'sandbox';
        const r2 = await apnsSend(env, t.token, other, title, body, data);
        if (r2.status === 200) await env.DB.prepare('UPDATE device_tokens SET env=? WHERE token=?').bind(other, t.token).run();
        r = r2;
      }
      if (r.status === 410 || r.reason === 'Unregistered') await env.DB.prepare('DELETE FROM device_tokens WHERE token=?').bind(t.token).run();
    } catch (e) { r = { status: 0, reason: String(e) }; }
    results.push({ token: t.token.slice(0, 8) + '…', ...r });
  }
  for (const u of userIds) {
    const mine = results.length ? results.map(x => `${x.status}${x.reason ? ':' + x.reason : ''}`).join(',') : 'no-devices';
    await env.DB.prepare('INSERT INTO notification_log VALUES(?,?,?,?,?,?,?)').bind(uid(), hospitalId, u, title, body, mine, now()).run();
  }
  return results;
}
async function staffIds(env, hospitalId, deptId, roles) {
  let q = 'SELECT id FROM users WHERE hospital_id=?'; const a = [hospitalId];
  if (deptId) { q += ' AND department_id=?'; a.push(deptId); }
  if (roles) { q += ` AND role IN (${roles.map(() => '?').join(',')})`; a.push(...roles); }
  return (await env.DB.prepare(q).bind(...a).all()).results.map(r => r.id);
}

// ---------- helpers ----------
const inviteCode = () => Array.from(crypto.getRandomValues(new Uint8Array(6)), b => 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'[b % 31]).join('');
const pubUser = (u) => u && ({ id: u.id, hospital_id: u.hospital_id, department_id: u.department_id, email: u.email, name: u.name, title: u.title, employee_number: u.employee_number, role: u.role, phone: u.phone, photo: u.photo, reminder_minutes: u.reminder_minutes, invite_code: u.pw_hash ? null : u.invite_code, joined: !!u.pw_hash });
async function session(env, u) { return { token: await signJWT(env, { sub: u.id, hid: u.hospital_id, role: u.role, tv: u.token_version || 1, iat: Math.floor(now() / 1000) }), user: pubUser(u) }; }
// ---- brute-force protection: 5 failures -> 15 min lockout per key ----
const LOCK_MAX = 5, LOCK_MS = 15 * 60 * 1000;
async function lockCheck(env, keys) {
  for (const k of keys) {
    const r = await env.DB.prepare('SELECT fails,locked_until FROM login_attempts WHERE k=?').bind(k).first();
    if (r && r.locked_until && r.locked_until > now()) throw new HttpError(429, 'too many attempts', Math.ceil((r.locked_until - now()) / 60000));
  }
}
async function lockFail(env, keys) {
  for (const k of keys) {
    const r = await env.DB.prepare('SELECT fails,locked_until FROM login_attempts WHERE k=?').bind(k).first();
    const max = k.startsWith('id:') ? LOCK_MAX : 30;
    const fails = (r && (!r.locked_until || r.locked_until <= now()) ? r.fails : 0) + 1;
    await env.DB.prepare('INSERT OR REPLACE INTO login_attempts(k,fails,locked_until,updated_at) VALUES(?,?,?,?)').bind(k, fails >= max ? 0 : fails, fails >= max ? now() + LOCK_MS : null, now()).run();
  }
}
async function lockClear(env, keys) { for (const k of keys) await env.DB.prepare('DELETE FROM login_attempts WHERE k=?').bind(k).run(); }
const isMgr = (me) => ['admin', 'head_nurse', 'supervisor'].includes(me.role);
const ROLES = ['employee', 'supervisor', 'head_nurse', 'admin'];
async function audit(env, me, deptId, action, detail) {
  await env.DB.prepare('INSERT INTO audit_log VALUES(?,?,?,?,?,?,?,?)').bind(uid(), me.hospital_id, deptId || me.department_id || null, me.id, me.name, action, typeof detail === 'string' ? detail : JSON.stringify(detail), now()).run();
}
const hospCode = () => Array.from(crypto.getRandomValues(new Uint8Array(6)), b => 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'[b % 31]).join('');

async function route(req, env) {
  const url = new URL(req.url); const p = url.pathname.replace(/\/+$/, '') || '/'; const m = req.method;
  if (m === 'OPTIONS') return new Response(null, { headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' } });
  const body = ['POST', 'PUT', 'PATCH', 'DELETE'].includes(m) ? await req.json().catch(() => ({})) : {};
  const DB = env.DB;
  if (p === '/privacy') return new Response(PRIVACY_HTML, { headers: { 'content-type': 'text/html; charset=utf-8' } });
  if (p === '/support' || p === '/marketing') return new Response(SUPPORT_HTML, { headers: { 'content-type': 'text/html; charset=utf-8' } });
  if (p === '/admin' || p === '/admin/index.html') return new Response(typeof ADMIN_HTML === 'string' ? ADMIN_HTML : 'admin not bundled', { headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-cache', 'x-frame-options': 'DENY' } });
  if (p === '/' || p === '/health') return json({ ok: true, service: 'munawib-api', version: '2.2', apns: !!env.APNS_KEY, runtime: env.RUNTIME || 'cloudflare' });

  if (p === '/auth/signup' && m === 'POST') {
    const { hospital, email, password, name, department } = body;
    need(hospital && email && password && name, 400, 'missing fields'); if (body.employee_number && body.head_nurse?.employee_number) need(String(body.employee_number) !== String(body.head_nurse.employee_number), 400, 'duplicate employee number'); need(password.length >= 8, 400, 'password too short');
    need(!(await DB.prepare('SELECT 1 FROM users WHERE email=?').bind(email.toLowerCase()).first()), 409, 'email exists');
    const hid = uid(), did = uid(), u = uid();
    await DB.batch([
      DB.prepare('INSERT INTO hospitals(id,name,created_at,code) VALUES(?,?,?,?)').bind(hid, hospital, now(), hospCode()),
      DB.prepare('INSERT INTO departments(id,hospital_id,name) VALUES(?,?,?)').bind(did, hid, department || 'القسم الرئيسي'),
      DB.prepare('INSERT INTO users(id,hospital_id,department_id,email,pw_hash,name,title,role,employee_number,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)').bind(u, hid, did, email.toLowerCase(), await hashPw(password), name, 'Admin', 'admin', String(body.employee_number || '').trim() || null, now()),
    ]);
    const out = await session(env, await DB.prepare('SELECT * FROM users WHERE id=?').bind(u).first());
    if (body.head_nurse?.name) {
      const hn = uid(), code = inviteCode();
      await DB.prepare("INSERT INTO users(id,hospital_id,department_id,name,title,employee_number,role,invite_code,created_at) VALUES(?,?,?,?,?,?,'head_nurse',?,?)")
        .bind(hn, hid, did, body.head_nurse.name, 'Head Nurse', String(body.head_nurse.employee_number || ''), code, now()).run();
      out.head_nurse_invite = code;
    }
    out.hospital_code = (await DB.prepare('SELECT code FROM hospitals WHERE id=?').bind(hid).first()).code;
    out.hospital_name = hospital; out.department = department || 'القسم الرئيسي';
    return json(out, 201);
  }
  if (p === '/auth/login' && m === 'POST') {
    let u;
    const ip = req.headers.get('cf-connecting-ip') || req.headers.get('x-forwarded-for') || 'ip';
    const idKey = 'id:' + String(body.identifier || body.email || body.employee_number || '').trim().toLowerCase() + '@' + String(body.hospital_code || body.hospitalCode || '').trim().toUpperCase();
    const LK = [idKey, 'ip:' + ip];
    await lockCheck(env, LK);
    need(String(body.password || '').length > 0, 400, 'missing fields');
    const ident = String(body.identifier || '').trim();
    if (ident && !body.employee_number && !body.email) { if (ident.includes('@')) body.email = ident; else body.employee_number = ident; }
    if (body.employee_number || body.employeeNumber) {
      const hc = String(body.hospital_code || body.hospitalCode || body.hospital_id || '').trim();
      const h = await DB.prepare('SELECT id FROM hospitals WHERE code=? OR id=?').bind(hc.toUpperCase(), hc).first();
      if (!h) { await lockFail(env, LK); need(false, 404, 'hospital not found'); }
      u = await DB.prepare('SELECT * FROM users WHERE hospital_id=? AND employee_number=?').bind(h.id, String(body.employee_number || body.employeeNumber).trim()).first();
    } else u = await DB.prepare('SELECT * FROM users WHERE email=?').bind((body.email || '').toLowerCase()).first();
    if (!u) { await lockFail(env, LK); need(false, 404, 'account not found'); }
    need(u.pw_hash, 403, 'account not activated');
    if (!(await verifyPw(String(body.password), u.pw_hash))) { await lockFail(env, LK); need(false, 401, 'wrong password'); }
    await lockClear(env, [idKey]);
    return json(await session(env, u));
  }
  if (p === '/auth/join' && m === 'POST') {
    const { code, password } = body; const email = body.email || null; need(code && password && password.length >= 8, 400, 'missing fields');
    const JK = ['join:' + (req.headers.get('cf-connecting-ip') || req.headers.get('x-forwarded-for') || 'ip')];
    await lockCheck(env, JK);
    const u = await DB.prepare('SELECT * FROM users WHERE invite_code=? AND pw_hash IS NULL').bind(code.toUpperCase().trim()).first();
    if (!u) { await lockFail(env, JK); need(false, 404, 'invalid invite'); }
    if (email) need(!(await DB.prepare('SELECT 1 FROM users WHERE email=? AND id<>?').bind(email.toLowerCase(), u.id).first()), 409, 'email exists');
    await DB.prepare('UPDATE users SET email=?,pw_hash=?,invite_code=NULL,token_version=COALESCE(token_version,1)+1 WHERE id=?').bind(email ? email.toLowerCase() : null, await hashPw(password), u.id).run();
    return json(await session(env, await DB.prepare('SELECT * FROM users WHERE id=?').bind(u.id).first()));
  }
  if (p.startsWith('/invite/') && m === 'GET') {
    const u = await DB.prepare('SELECT u.name,h.name hospital FROM users u JOIN hospitals h ON h.id=u.hospital_id WHERE invite_code=? AND pw_hash IS NULL').bind(p.split('/')[2].toUpperCase()).first();
    need(u, 404, 'invalid invite'); return json(u);
  }

  // ---- authenticated ----
  const claims = await verifyJWT(env, (req.headers.get('authorization') || '').replace(/^Bearer /i, ''));
  need(claims, 401, 'unauthorized');
  const me = await DB.prepare('SELECT * FROM users WHERE id=?').bind(claims.sub).first(); need(me, 401, 'unauthorized');
  need(me.pw_hash && claims.tv && claims.tv === (me.token_version || 1), 401, 'session expired');
  const H = me.hospital_id;
  const mgr = () => need(isMgr(me), 403, 'forbidden');
  const inDept = (d) => me.role === 'admin' || (d && d === me.department_id);
  const mgrOf = (d) => need(isMgr(me) && inDept(d), 403, 'forbidden');
  const headOf = (d) => need((me.role === 'admin') || (me.role === 'head_nurse' && d === me.department_id), 403, 'forbidden');
  const userDept = async (id) => (await DB.prepare('SELECT department_id FROM users WHERE id=? AND hospital_id=?').bind(id, H).first())?.department_id;
  const seg = p.split('/').filter(Boolean);

  if (p === '/me' && m === 'GET') return json({ user: pubUser(me), hospital: await DB.prepare('SELECT id,name,CASE WHEN ? THEN code END code FROM hospitals WHERE id=?').bind(isMgr(me) ? 1 : 0, H).first() });
  if (p === '/me' && m === 'PATCH') {
    await DB.prepare('UPDATE users SET name=COALESCE(?,name),phone=COALESCE(?,phone),photo=COALESCE(?,photo),reminder_minutes=COALESCE(?,reminder_minutes) WHERE id=?')
      .bind(body.name ?? null, body.phone ?? null, body.photo ?? null, body.reminder_minutes ?? null, me.id).run();
    return json({ user: pubUser(await DB.prepare('SELECT * FROM users WHERE id=?').bind(me.id).first()) });
  }
  if (p === '/me' && m === 'DELETE') {
    need(await verifyPw(body.password || '', me.pw_hash), 401, 'invalid credentials');
    const admins = (await DB.prepare("SELECT count(*) n FROM users WHERE hospital_id=? AND role='admin'").bind(H).first()).n;
    if (me.role === 'admin' && admins <= 1) {
      const t = ['attendance', 'events', 'leave_requests', 'swap_requests', 'announcements', 'notification_log', 'rosters', 'departments', 'audit_log'];
      await DB.batch([...t.map(x => DB.prepare(`DELETE FROM ${x} WHERE hospital_id=?`).bind(H)),
        DB.prepare('DELETE FROM device_tokens WHERE user_id IN (SELECT id FROM users WHERE hospital_id=?)').bind(H),
        DB.prepare('DELETE FROM users WHERE hospital_id=?').bind(H), DB.prepare('DELETE FROM hospitals WHERE id=?').bind(H)]);
      return json({ ok: true, deleted: 'hospital' });
    }
    await DB.batch([DB.prepare('DELETE FROM device_tokens WHERE user_id=?').bind(me.id), DB.prepare('DELETE FROM attendance WHERE user_id=?').bind(me.id),
      DB.prepare('DELETE FROM leave_requests WHERE user_id=?').bind(me.id), DB.prepare('DELETE FROM swap_requests WHERE from_user=? OR to_user=?').bind(me.id, me.id),
      DB.prepare('DELETE FROM notification_log WHERE user_id=?').bind(me.id), DB.prepare('DELETE FROM users WHERE id=?').bind(me.id)]);
    await audit(env, me, me.department_id, 'account.delete', me.name);
    return json({ ok: true, deleted: 'user' });
  }
  if (p === '/bootstrap' && m === 'GET') {
    const q = (s, ...a) => DB.prepare(s).bind(...a).all().then(r => r.results);
    const [hospital, departments, users, rosters, attendance, events, leaves, swaps, announcements, notifications] = await Promise.all([
      DB.prepare('SELECT * FROM hospitals WHERE id=?').bind(H).first(),
      q('SELECT * FROM departments WHERE hospital_id=?', H), q('SELECT * FROM users WHERE hospital_id=?', H),
      q('SELECT * FROM rosters WHERE hospital_id=? ORDER BY year DESC,month DESC LIMIT 36', H),
      q('SELECT * FROM attendance WHERE hospital_id=? ORDER BY date DESC LIMIT 1000', H),
      q('SELECT * FROM events WHERE hospital_id=? ORDER BY date', H),
      q('SELECT * FROM leave_requests WHERE hospital_id=? ORDER BY created_at DESC LIMIT 200', H),
      q('SELECT * FROM swap_requests WHERE hospital_id=? ORDER BY created_at DESC LIMIT 200', H),
      q('SELECT * FROM announcements WHERE hospital_id=? ORDER BY created_at DESC LIMIT 100', H),
      q('SELECT * FROM notification_log WHERE user_id=? ORDER BY created_at DESC LIMIT 50', me.id),
    ]);
    const audit_log = (me.role === 'admin' || me.role === 'head_nurse') ? (await DB.prepare(`SELECT * FROM audit_log WHERE hospital_id=? ${me.role === 'admin' ? '' : 'AND department_id=?'} ORDER BY created_at DESC LIMIT 200`).bind(...(me.role === 'admin' ? [H] : [H, me.department_id])).all()).results : [];
    if (hospital && !isMgr(me)) hospital.code = null;
    return json({ audit_log, me: pubUser(me), hospital, departments, users: users.map(u => (isMgr(me) && inDept(u.department_id)) ? pubUser(u) : { ...pubUser(u), invite_code: null, email: null }), rosters: rosters.map(r => ({ ...r, grid: JSON.parse(r.grid || '{}') })), attendance, events, leaves, swaps, announcements, notifications });
  }
  if (p === '/departments' && m === 'POST') { need(me.role === 'admin', 403, 'forbidden'); const id = uid(); await DB.prepare('INSERT INTO departments(id,hospital_id,name) VALUES(?,?,?)').bind(id, H, body.name).run(); await audit(env, me, id, 'department.create', body.name); return json({ id, name: body.name }, 201); }
  if (seg[0] === 'departments' && seg[1] && m === 'PATCH') {
    headOf(seg[1]);
    await DB.prepare('UPDATE departments SET min_day=COALESCE(?,min_day),min_night=COALESCE(?,min_night),name=COALESCE(?,name) WHERE id=? AND hospital_id=?').bind(body.min_day ?? null, body.min_night ?? null, me.role === 'admin' ? (body.name ?? null) : null, seg[1], H).run();
    await audit(env, me, seg[1], 'department.update', body); return json({ ok: true });
  }
  if (seg[0] === 'departments' && seg[1] && m === 'DELETE') { need(me.role === 'admin', 403, 'forbidden'); await audit(env, me, seg[1], 'department.delete', seg[1]); await DB.prepare('DELETE FROM departments WHERE id=? AND hospital_id=?').bind(seg[1], H).run(); return json({ ok: true }); }

  if (p === '/employees' && m === 'POST') {
    const dept = body.department_id || me.department_id; headOf(dept); const id = uid(), code = inviteCode();
    const allowed = me.role === 'admin' ? ROLES : ['employee', 'supervisor'];
    const role = allowed.includes(body.role) ? body.role : 'employee';
    if (body.employee_number) need(!(await DB.prepare('SELECT 1 FROM users WHERE hospital_id=? AND employee_number=?').bind(H, String(body.employee_number)).first()), 409, 'employee number exists');
    await DB.prepare('INSERT INTO users(id,hospital_id,department_id,name,title,employee_number,role,invite_code,phone,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)')
      .bind(id, H, dept, body.name, body.title || '', String(body.employee_number || ''), role, code, body.phone || '', now()).run();
    await audit(env, me, dept, 'employee.create', `${body.name} (${role})`);
    return json({ user: pubUser(await DB.prepare('SELECT * FROM users WHERE id=?').bind(id).first()), invite_code: code, invite_link: `munawib://join?code=${code}` }, 201);
  }
  if (seg[0] === 'employees' && seg[1] && m === 'PATCH') {
    headOf(await userDept(seg[1])); if (body.department_id && me.role !== 'admin') need(body.department_id === me.department_id, 403, 'forbidden');
    await DB.prepare('UPDATE users SET name=COALESCE(?,name),title=COALESCE(?,title),employee_number=COALESCE(?,employee_number),department_id=COALESCE(?,department_id),phone=COALESCE(?,phone),role=COALESCE(?,role) WHERE id=? AND hospital_id=?')
      .bind(body.name ?? null, body.title ?? null, body.employee_number ?? null, body.department_id ?? null, body.phone ?? null, me.role === 'admin' ? (body.role ?? null) : null, seg[1], H).run();
    await audit(env, me, await userDept(seg[1]), 'employee.update', { id: seg[1], ...body });
    return json({ user: pubUser(await DB.prepare('SELECT * FROM users WHERE id=?').bind(seg[1]).first()) });
  }
  if (seg[0] === 'employees' && seg[2] === 'role' && m === 'POST') {
    const d = await userDept(seg[1]); headOf(d); need(seg[1] !== me.id, 400, 'cannot change own role');
    const allowed = me.role === 'admin' ? ROLES : ['employee', 'supervisor'];
    const t = await DB.prepare('SELECT role,name FROM users WHERE id=?').bind(seg[1]).first(); need(t, 404, 'not found');
    need(allowed.includes(body.role) && (me.role === 'admin' || ['employee', 'supervisor'].includes(t.role)), 403, 'forbidden');
    await DB.prepare('UPDATE users SET role=? WHERE id=?').bind(body.role, seg[1]).run();
    await audit(env, me, d, 'employee.role', `${t.name}: ${t.role} → ${body.role}`); return json({ ok: true });
  }
  if (seg[0] === 'employees' && seg[2] === 'reset' && m === 'POST') {
    const d = await userDept(seg[1]); headOf(d); need(seg[1] !== me.id, 400, 'cannot reset self');
    const t = await DB.prepare('SELECT role,name FROM users WHERE id=?').bind(seg[1]).first(); need(t && (me.role === 'admin' || t.role !== 'admin'), 403, 'forbidden');
    const code = inviteCode();
    await DB.prepare('UPDATE users SET pw_hash=NULL,invite_code=?,token_version=COALESCE(token_version,1)+1 WHERE id=?').bind(code, seg[1]).run();
    await DB.prepare('DELETE FROM device_tokens WHERE user_id=?').bind(seg[1]).run();
    await audit(env, me, d, 'employee.reset', t.name);
    return json({ invite_code: code, invite_link: `munawib://join?code=${code}` });
  }
  if (seg[0] === 'employees' && seg[1] && m === 'DELETE') { const d0 = await userDept(seg[1]); headOf(d0); need(seg[1] !== me.id, 400, 'cannot delete self'); await audit(env, me, d0, 'employee.delete', seg[1]); await DB.prepare('DELETE FROM users WHERE id=? AND hospital_id=?').bind(seg[1], H).run(); return json({ ok: true }); }

  if (p === '/rosters' && m === 'PUT') {
    const { department_id, year, month, grid } = body; need(department_id && year && month, 400, 'missing fields'); mgrOf(department_id);
    const ex = await DB.prepare('SELECT id FROM rosters WHERE department_id=? AND year=? AND month=?').bind(department_id, year, month).first();
    const id = ex?.id || uid();
    await DB.prepare(`INSERT INTO rosters(id,hospital_id,department_id,year,month,status,grid,day_start,night_start,updated_at) VALUES(?,?,?,?,?,'draft',?,?,?,?)
      ON CONFLICT(department_id,year,month) DO UPDATE SET grid=excluded.grid,status='draft',day_start=excluded.day_start,night_start=excluded.night_start,updated_at=excluded.updated_at`)
      .bind(id, H, department_id, year, month, JSON.stringify(grid || {}), body.day_start ?? 5, body.night_start ?? 17, now()).run();
    await audit(env, me, department_id, 'roster.save', `${month}/${year}`);
    return json({ id, status: 'draft' });
  }
  if (seg[0] === 'rosters' && seg[2] === 'status' && m === 'POST') {
    const st = body.status; need(['draft', 'review', 'approved'].includes(st), 400, 'bad status');
    const r = await DB.prepare('SELECT * FROM rosters WHERE id=? AND hospital_id=?').bind(seg[1], H).first(); need(r, 404, 'not found'); mgrOf(r.department_id);
    await audit(env, me, r.department_id, 'roster.' + st, `${r.month}/${r.year}`);
    await DB.prepare('UPDATE rosters SET status=?,updated_at=? WHERE id=?').bind(st, now(), r.id).run();
    let push = [];
    if (st === 'approved') push = await pushToUsers(env, H, await staffIds(env, H, r.department_id), 'تم اعتماد الجدول ✅', `جدول ${r.month}/${r.year} أصبح معتمدًا. افتح مِناوب لمشاهدة مناوباتك.`, { type: 'roster', id: r.id });
    return json({ ok: true, status: st, push });
  }

  if (p === '/attendance' && m === 'POST') {
    let target = me.id; if (body.user_id && body.user_id !== me.id) { mgrOf(await userDept(body.user_id)); target = body.user_id; } const id = uid();
    await audit(env, me, await userDept(target), 'attendance.add', `${body.date} ${body.kind} ${body.hours}`);
    await DB.prepare('INSERT INTO attendance VALUES(?,?,?,?,?,?,?)').bind(id, H, target, body.date, body.kind || 'H', body.hours || 0, body.note || '').run();
    return json({ id }, 201);
  }
  if (seg[0] === 'attendance' && seg[1] && m === 'DELETE') { const a = await DB.prepare('SELECT user_id FROM attendance WHERE id=? AND hospital_id=?').bind(seg[1], H).first(); need(a, 404, 'not found'); mgrOf(await userDept(a.user_id)); await audit(env, me, null, 'attendance.delete', seg[1]); await DB.prepare('DELETE FROM attendance WHERE id=? AND hospital_id=?').bind(seg[1], H).run(); return json({ ok: true }); }
  if (p === '/events' && m === 'POST') { mgr(); const id = uid(); await audit(env, me, null, 'event.create', body.title); await DB.prepare('INSERT INTO events VALUES(?,?,?,?,?,?)').bind(id, H, body.title, body.date, body.location || '', body.audience || '').run(); return json({ id }, 201); }
  if (seg[0] === 'events' && seg[1] && m === 'DELETE') { mgr(); await audit(env, me, null, 'event.delete', seg[1]); await DB.prepare('DELETE FROM events WHERE id=? AND hospital_id=?').bind(seg[1], H).run(); return json({ ok: true }); }

  if (p === '/leaves' && m === 'POST') {
    const id = uid(); await DB.prepare('INSERT INTO leave_requests(id,hospital_id,user_id,start_date,end_date,reason,created_at) VALUES(?,?,?,?,?,?,?)').bind(id, H, me.id, body.start_date, body.end_date, body.reason || '', now()).run();
    await audit(env, me, me.department_id, 'leave.request', `${body.start_date}→${body.end_date}`);
    const push = await pushToUsers(env, H, [...new Set([...(await staffIds(env, H, me.department_id, ['head_nurse', 'supervisor'])), ...(await staffIds(env, H, null, ['admin']))])].filter(x => x !== me.id), 'طلب إجازة جديد', `${me.name}: ${body.start_date} → ${body.end_date}`, { type: 'leave', id });
    return json({ id, push }, 201);
  }
  if (seg[0] === 'leaves' && seg[2] === 'decision' && m === 'POST') {
    const st = body.approve ? 'approved' : 'rejected';
    const l = await DB.prepare('SELECT * FROM leave_requests WHERE id=? AND hospital_id=?').bind(seg[1], H).first(); need(l, 404, 'not found');
    const ld = await userDept(l.user_id); mgrOf(ld); await audit(env, me, ld, 'leave.' + st, `${l.start_date}→${l.end_date}`);
    await DB.prepare('UPDATE leave_requests SET status=?,decided_by=? WHERE id=?').bind(st, me.id, l.id).run();
    const push = await pushToUsers(env, H, [l.user_id], st === 'approved' ? 'تمت الموافقة على إجازتك ✅' : 'تم رفض طلب الإجازة', `${l.start_date} → ${l.end_date}`, { type: 'leave', id: l.id });
    return json({ ok: true, status: st, push });
  }
  if (p === '/swaps' && m === 'POST') {
    const id = uid(); await DB.prepare('INSERT INTO swap_requests(id,hospital_id,from_user,to_user,date,note,created_at) VALUES(?,?,?,?,?,?,?)').bind(id, H, me.id, body.to_user, body.date, body.note || '', now()).run();
    need((await userDept(body.to_user)) === me.department_id, 400, 'colleague must be in your department');
    await audit(env, me, me.department_id, 'swap.request', body.date);
    const targets = [...new Set([body.to_user, ...(await staffIds(env, H, me.department_id, ['head_nurse', 'supervisor'])), ...(await staffIds(env, H, null, ['admin']))])].filter(x => x && x !== me.id);
    const push = await pushToUsers(env, H, targets, 'طلب تبديل مناوبة', `${me.name} يطلب تبديل مناوبة يوم ${body.date}`, { type: 'swap', id });
    return json({ id, push }, 201);
  }
  if (seg[0] === 'swaps' && seg[2] === 'decision' && m === 'POST') {
    const st = body.approve ? 'approved' : 'rejected';
    const s = await DB.prepare('SELECT * FROM swap_requests WHERE id=? AND hospital_id=?').bind(seg[1], H).first(); need(s, 404, 'not found');
    const sd = await userDept(s.from_user); mgrOf(sd); await audit(env, me, sd, 'swap.' + st, s.date);
    await DB.prepare('UPDATE swap_requests SET status=?,decided_by=? WHERE id=?').bind(st, me.id, s.id).run();
    if (st === 'approved') {
      const [y, mo, d] = s.date.split('-').map(Number);
      const fu = await DB.prepare('SELECT department_id FROM users WHERE id=?').bind(s.from_user).first();
      const r = fu && await DB.prepare('SELECT * FROM rosters WHERE department_id=? AND year=? AND month=?').bind(fu.department_id, y, mo).first();
      if (r) { const g = JSON.parse(r.grid || '{}'); g[s.from_user] ||= {}; g[s.to_user] ||= {}; const a = g[s.from_user][d] || ''; g[s.from_user][d] = g[s.to_user][d] || ''; g[s.to_user][d] = a; await DB.prepare('UPDATE rosters SET grid=?,updated_at=? WHERE id=?').bind(JSON.stringify(g), now(), r.id).run(); }
    }
    const push = await pushToUsers(env, H, [s.from_user, s.to_user], st === 'approved' ? 'تمت الموافقة على التبديل ✅' : 'تم رفض طلب التبديل', `مناوبة يوم ${s.date}`, { type: 'swap', id: s.id });
    return json({ ok: true, status: st, push });
  }
  if (p === '/announcements' && m === 'POST') {
    mgr(); const id = uid(); const adept = me.role === 'admin' ? (body.department_id || null) : me.department_id;
    await audit(env, me, adept, 'announcement', body.title);
    await DB.prepare('INSERT INTO announcements VALUES(?,?,?,?,?,?,?)').bind(id, H, adept, me.name, body.title, body.body || '', now()).run();
    const push = await pushToUsers(env, H, (await staffIds(env, H, adept)).filter(x => x !== me.id), `📢 ${body.title}`, body.body || '', { type: 'announcement', id });
    return json({ id, push }, 201);
  }
  if (p === '/devices' && m === 'POST') {
    need(/^[0-9a-f]{32,200}$/i.test(body.token || ''), 400, 'bad token');
    await DB.prepare('INSERT INTO device_tokens VALUES(?,?,?,?) ON CONFLICT(token) DO UPDATE SET user_id=excluded.user_id,env=excluded.env,updated_at=excluded.updated_at').bind(body.token, me.id, body.env === 'sandbox' ? 'sandbox' : 'production', now()).run();
    return json({ ok: true });
  }
  if (p === '/devices' && m === 'DELETE') { await DB.prepare('DELETE FROM device_tokens WHERE token=? AND user_id=?').bind(body.token || url.searchParams.get('token'), me.id).run(); return json({ ok: true }); }
  if (p === '/push/test' && m === 'POST') {
    need(env.APNS_KEY, 503, 'APNs not configured');
    const results = await pushToUsers(env, H, [me.id], 'اختبار التنبيهات 🔔', 'وصل تنبيه حقيقي من خادم مِناوب إلى جهازك.', { type: 'test' });
    return json({ sent: results.filter(r => r.status === 200).length, devices: results.length, results });
  }
  if (p === '/push/custom' && m === 'POST') {
    need(me.role === 'admin' || me.role === 'head_nurse', 403, 'forbidden'); need(body.title, 400, 'missing fields');
    let ids = Array.isArray(body.user_ids) && body.user_ids.length ? body.user_ids : await staffIds(env, H, me.role === 'admin' ? (body.department_id || null) : me.department_id);
    if (me.role !== 'admin') { const ok = new Set(await staffIds(env, H, me.department_id)); ids = ids.filter(x => ok.has(x)); }
    await audit(env, me, me.role === 'admin' ? body.department_id : me.department_id, 'push.custom', `${body.title} → ${ids.length}`);
    const results = await pushToUsers(env, H, ids, body.title, body.body || '', { type: 'custom' });
    return json({ recipients: ids.length, sent: results.filter(r => r.status === 200).length, devices: results.length });
  }
  if (p === '/audit' && m === 'GET') {
    need(me.role === 'admin' || me.role === 'head_nurse', 403, 'forbidden');
    const r = me.role === 'admin' ? await DB.prepare('SELECT * FROM audit_log WHERE hospital_id=? ORDER BY created_at DESC LIMIT 500').bind(H).all() : await DB.prepare('SELECT * FROM audit_log WHERE hospital_id=? AND department_id=? ORDER BY created_at DESC LIMIT 500').bind(H, me.department_id).all();
    return json(r.results);
  }
  if (p === '/super/hospitals' && m === 'GET') {
    need(me.email && me.email === (env.OWNER_EMAIL || 'm.alzhrani977@gmail.com') && me.role === 'admin', 403, 'forbidden');
    return json((await DB.prepare(`SELECT h.id,h.name,h.code,h.created_at,(SELECT count(*) FROM departments d WHERE d.hospital_id=h.id) departments,(SELECT count(*) FROM users u WHERE u.hospital_id=h.id) users,(SELECT count(*) FROM device_tokens t JOIN users u ON u.id=t.user_id WHERE u.hospital_id=h.id) devices FROM hospitals h ORDER BY h.created_at DESC`).all()).results);
  }
  if (p === '/notifications' && m === 'GET') return json((await DB.prepare('SELECT * FROM notification_log WHERE user_id=? ORDER BY created_at DESC LIMIT 100').bind(me.id).all()).results);
  throw new HttpError(404, 'not found');
}

// ---------- cron: shift reminders ----------
async function shiftReminders(env) {
  if (!env.APNS_KEY) return;
  const t = new Date(now() + 3 * 3600 * 1000); // Asia/Riyadh (UTC+3, no DST)
  const months = [[t.getUTCFullYear(), t.getUTCMonth() + 1]];
  const nx = new Date(Date.UTC(t.getUTCFullYear(), t.getUTCMonth() + 1, 1)); months.push([nx.getUTCFullYear(), nx.getUTCMonth() + 1]);
  for (const [y, mo] of months) {
    const { results: rs } = await env.DB.prepare("SELECT * FROM rosters WHERE status='approved' AND year=? AND month=?").bind(y, mo).all();
    for (const r of rs) {
      const g = JSON.parse(r.grid || '{}');
      for (const [userId, days] of Object.entries(g)) {
        const u = await env.DB.prepare('SELECT reminder_minutes FROM users WHERE id=?').bind(userId).first(); if (!u) continue;
        const lead = (u.reminder_minutes ?? 60) * 60000;
        for (const [d, code] of Object.entries(days)) {
          if (code !== 'D' && code !== 'N') continue;
          const startLocal = Date.UTC(y, mo - 1, Number(d), code === 'D' ? r.day_start : r.night_start);
          const fireUtc = startLocal - 3 * 3600 * 1000 - lead;
          if (fireUtc <= now() && fireUtc > now() - 10 * 60000) {
            const key = `${userId}:${y}-${mo}-${d}:${code}`;
            const ins = await env.DB.prepare('INSERT OR IGNORE INTO reminders_sent VALUES(?)').bind(key).run();
            if (ins.meta.changes) await pushToUsers(env, r.hospital_id, [userId], 'تذكير بالمناوبة ⏰', `مناوبتك ${code === 'D' ? 'النهارية' : 'الليلية'} تبدأ الساعة ${code === 'D' ? r.day_start : r.night_start}:00`, { type: 'reminder' });
          }
        }
      }
    }
  }
}

export default {
  async fetch(req, env) {
    try { return await route(req, env); }
    catch (e) { if (!e.status) console.error(e); return json(e.status ? { error: e.message, ...(e.retry ? { retry_minutes: e.retry } : {}) } : { error: 'server error' }, e.status || 500); }
  },
  async scheduled(_ev, env, ctx) { ctx.waitUntil(shiftReminders(env)); },
};
