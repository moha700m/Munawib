# Munawib v3 «جناح» redesign — notes (branch `redesign-v3`)

## Findings before the redesign
- Native SwiftUI app (iOS 17+), XcodeGen `project.yml`, bundle id `com.mohlab.munawib`, v2.2 (22). CI: `build.yml` (unsigned IPA),
  `uitests.yml`, `screenshots.yml`, `testflight.yml` (main only — **not** touched/triggered).
- Sibling repos checked (rafeeq-ios, tayyar-ios): **no shared source, colours or components** with Munawib (different files,
  bundle prefix `com.moha700m.*` vs `com.mohlab.*`). So the code template is not what made it look alike.
- **Most likely 4.3(a) trigger:** `moha700m/manawb-ios-wrapper` — a Capacitor iOS wrapper for the *same* «مِناوب» hospital
  shift app. If it was ever submitted (same or another account), Apple sees two apps with the same concept/metadata.

## What changed
- Palette: dark amber/indigo/pink → light «ward paper» (#F3F0E8), scrubs teal primary (#0E6B5C), saffron day, coral evening,
  navy night, pine hero tiles. App is now light-only; launch background updated.
- Typography: bundled IBM Plex Sans Arabic (OFL, Regular/SemiBold/Bold) with Dynamic Type; app-wide default font.
- Home: «مدار» timeline hero replaced by a **shift ticket** (huge shift name, time range, perforation, countdown stub),
  a 7-day **duty strip** of capsules, and a **swap board / next night** bento row. Bento metrics: 26pt radius, 88pt rows.
- Roster: cells are 44pt filled capsules (shift-coloured) instead of tinted squares.
- Onboarding/login header: typographic «جدول الجناح في جيبك» with D/E/N capsules instead of an icon tile.
- Empty states: branded `WardEmptyState` (home upcoming + my shifts). Home title «ورديتي».
- New app icon (teal + paper card + three shift pills).

## Still similar / not done (honest)
- Navigation structure, screens, drawer, forms, head-nurse dashboard and the `MasarHero` (still used compactly in my-shifts and
  head-nurse screens) are unchanged. Store logic/backend unchanged. Most other `ContentUnavailableView`s unchanged.
- Not compiled locally (no macOS here); verification relies on the GitHub Actions build on this branch.

## Suggested App Store metadata
**AR** — الاسم: مِناوب: جدول مناوبات التمريض · العنوان الفرعي: جدول الجناح وتبديل الورديات
الوصف (مقدمة): «مِناوب يحوّل جدول القسم الورقي إلى جدول رقمي لفريق التمريض: صوّر الجدول، راجع المناوبات، واعتمدها رئيسة التمريض. اعرض وردية اليوم كتذكرة، واطلب تبديل مناوبة من سوق التبديل، وتابع أقرب سهر، واستلم تنبيه قبل كل مناوبة.»
الكلمات: مناوبات,تمريض,مستشفى,جدول,وردية,تبديل,سهر,رئيسة تمريض,قسم,ممرضة

**EN** — Subtitle: Nurse roster & shift swaps · Keywords: nurse,roster,shift,swap,hospital,ward,on-call,rota,night,schedule
Description lead: "Munawib turns your ward's paper roster into a live schedule: scan it, review, approve, then see today's shift as a ticket, trade shifts on the swap board and get reminded before every shift."

Screenshots plan (light theme, 5): 1) today's shift ticket, 2) scan paper roster, 3) ward roster capsules, 4) swap board/requests, 5) head-nurse coverage.
App Review notes: explain it is the only shift app on the account; remove/never submit `manawb-ios-wrapper`.

## Previews
Real simulator renders from the `screenshots.yml` run on this branch (iPhone): previews/01_home.png, 03_roster.png, 04_dashboard.png, 07_login.png. Tab bar still labels home «مدار» (to rename).
