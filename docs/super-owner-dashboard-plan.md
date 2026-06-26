# خطة داشبورد السوبر أونر - كيات

## الهدف

بناء داشبورد ويب إداري للسوبر أونر داخل نفس Monorepo الخاص بكيات، وظيفته مراقبة وإدارة المنظومة من مكان واحد:

- الإحصائيات العامة.
- الخريطة الحية.
- الخطوط والمواقف.
- البلاغات.
- السواق والمركبات.
- المستخدمين والصلاحيات.
- سجلات التدقيق Audit Logs.

هذه الوثيقة خطة فقط. لا يتم تنفيذ أي خطوة إلا بعد موافقة صريحة.

## الخيار التقني المعتمد

الخيار المقترح هو إنشاء تطبيق ويب مستقل داخل المشروع:

```txt
apps/admin
```

التقنيات:

- Next.js + React + TypeScript.
- TanStack Query لجلب البيانات والكاش.
- TanStack Table للجداول والفلاتر.
- MapLibre للخريطة الإدارية لتجنب تكاليف Google Maps وفواتيرها المفاجئة.
- Recharts للرسوم البيانية.
- CSS/Component system يلتزم بتصميم RTL عربي إداري وهادئ.

## سبب اختيار Next.js

- مناسب أكثر من Flutter Web للداشبوردات الإدارية الثقيلة.
- ممتاز للجداول، الفلاتر، الصفحات، الصلاحيات، والـ routing.
- قريب من الـ backend الحالي لأن كليهما TypeScript.
- سهل ربطه مع NestJS APIs الحالية.
- أسهل في النشر كـ subdomain مثل:

```txt
admin.kiyat.app
```

## إعداد المونوريبو

المشروع حالياً يستخدم npm workspaces، لذلك البداية المقترحة تكون بدون Turborepo أو Nx حتى لا نضيف تعقيد مبكر.

نضيف `apps/admin` إلى workspaces في `package.json`:

```json
"workspaces": [
  "apps/backend",
  "apps/admin",
  "packages/shared-types"
]
```

سكريبتات التشغيل المقترحة:

```json
"admin:dev": "npm --workspace @kiyat/admin run dev",
"admin:build": "npm --workspace @kiyat/admin run build",
"admin:start": "npm --workspace @kiyat/admin run start"
```

ملاحظة: إذا كبر المشروع لاحقاً وصارت builds بطيئة، نراجع إدخال Turborepo. بالبداية npm workspaces كافي وأنظف.

## سياسة الدخول Auth

الخطة الأصلية كانت OTP فقط، لكن عملياً السوبر أونر يحتاج جلسة مريحة.

الخيار الأفضل:

1. OTP يستخدم فقط لأول إعداد أو عند استرجاع الحساب.
2. بعدها يكون الدخول عبر email/password أو phone/password.
3. إضافة Remember Me بجلسة طويلة من 7 إلى 30 يوم.
4. access token قصير العمر.
5. refresh token طويل العمر ومحمي.

الخيار الأسرع للـ MVP:

1. نستخدم operator OTP الموجود حالياً.
2. نجعل session طويلة للداشبورد فقط.
3. نضيف لاحقاً password login كمرحلة تحسين.

القرار المطلوب قبل التنفيذ:

- هل نبدأ بـ OTP + session طويلة؟
- أم نضيف email/password من البداية؟

## الصلاحيات RBAC

قبل بناء صفحات admin فعلية، يجب تثبيت الصلاحيات في backend.

الموجود حالياً:

- `UserRole` يحتوي:
  - passenger
  - operator
  - admin
  - owner
  - support
- يوجد `OperatorAuthGuard`.
- بعض الـ controllers تفحص الدور يدوياً داخل الدالة.

المطلوب أولاً:

1. إنشاء `RolesGuard`.
2. إنشاء decorator مثل:

```ts
@Roles(UserRole.Owner, UserRole.Admin)
```

3. إزالة تكرار شروط الصلاحيات اليدوية تدريجياً.
4. اعتماد سياسة واضحة:

| الدور | الصلاحيات |
| --- | --- |
| Owner / Super Owner | كل شيء |
| Admin | إدارة تشغيلية بدون حذف/تغيير صلاحيات حساسة |
| Operator | تشغيل ومتابعة محدودة |
| Support | مشاهدة ومراجعة بلاغات بدون خريطة تفصيلية |

ملاحظة: يمكن استخدام `Owner` الحالي كسوبر أونر بالبداية. إذا نحتاج فصل قانوني/تشغيلي لاحقاً، نضيف `SuperOwner`.

## الخريطة الحية Live Map

التقنية المقترحة:

- MapLibre للعرض.
- OpenStreetMap tiles أو مزود tiles مناسب لاحقاً.
- تحديثات البيانات من backend.

قبل بناء الخريطة يجب التأكد من:

1. هل WebSocket الحالي يدعم بث بيانات admin؟
2. هل البيانات الحالية في `tracking.gateway.ts` مخصصة للموبايل فقط؟
3. هل نحتاج قناة admin منفصلة مثل:

```txt
admin:live-tracking
```

خيار MVP:

- نبدأ بـ polling كل 15-30 ثانية على:

```txt
GET /analytics/live-tracking
```

- هذا كافي للـ MVP الإداري لأن الهدف مراقبة تشغيلية عامة، وليس تتبع لحظي بدقة تطبيق السائق.
- إذا احتجنا إحساساً أسرع قبل WebSocket، نقلل polling إلى 10 ثواني.
- بعدها نضيف WebSocket إذا احتجنا تحديثاً حياً أكثر واستجابة أعلى.

الخصوصية:

- لا تعرض مواقع الركاب الفردية.
- تعرض passenger zones مجمعة فقط.
- تقريب الإحداثيات أو تجميعها كما يفعل backend حالياً.

## صفحات الداشبورد

### 1. Login

- إدخال رقم الهاتف أو البريد.
- تحقق OTP أو password حسب القرار.
- Remember Me.
- منع الدخول إذا الدور غير مسموح.
- توجيه المستخدم للـ overview بعد الدخول.

### 2. Layout

- Sidebar RTL.
- Topbar فيه اسم المستخدم والدور.
- Session state.
- Empty/loading/error states.
- حماية الصفحات من الدخول بدون token.

### 3. Overview

تعرض:

- عدد الكيات النشطة.
- عدد الركاب المنتظرين.
- عدد الخطوط.
- متوسط الانتظار.
- متوسط التقييم.
- أكثر الخطوط ازدحاماً.
- آخر تحديث.

في Sprint 1 يمكن استعمال بيانات وهمية أو mock adapter، ثم ربطها بـ:

```txt
GET /analytics/overview
```

### 4. Live Map

تعرض:

- المركبات النشطة.
- اتجاه المركبة إن توفر.
- آخر ظهور.
- السرعة.
- اسم السائق.
- اسم الخط.
- مناطق انتظار الركاب بشكل مجمع.
- فلترة حسب الخط.

### 5. Routes

تعرض:

- قائمة الخطوط.
- البحث والفلترة.
- الحالة: active / inactive / unverified.
- النوع: kia / coaster / bus / minibus.
- عدد المواقف.
- آخر تعديل.

لاحقاً:

- إضافة خط.
- تعديل خط.
- تعطيل/تفعيل خط.
- إدارة نقاط المسار والمواقف.

### 6. Reports

تعرض:

- البلاغات حسب الحالة.
- النوع.
- الخط المرتبط.
- المستخدم المرسل.
- تاريخ الإرسال.
- قبول أو رفض البلاغ.
- ملاحظات المراجع.

### 7. Drivers & Vehicles

مرحلة لاحقة:

- عرض السواق.
- عرض المركبات.
- ربط سائق بمركبة.
- ربط مركبة بخط.
- تعطيل/تفعيل.
- آخر ظهور.
- حالة التتبع.

### 8. Users & Roles

مرحلة لاحقة:

- عرض المستخدمين الإداريين.
- إضافة Admin / Operator / Support.
- تعديل الدور.
- منع تعديل Owner إلا من Owner.
- تسجيل كل تغيير في Audit Log.

### 9. Audit Logs

مرحلة لاحقة:

- من عدل خط؟
- من راجع بلاغ؟
- من غير دور مستخدم؟
- من عطل مركبة؟
- وقت العملية.
- IP أو user agent إذا توفر.

## Backend APIs المطلوبة

### موجود حالياً ويمكن استخدامه

```txt
POST /auth/operator/login
POST /auth/operator/verify-otp
GET  /auth/operator/me
GET  /analytics/overview
GET  /analytics/live-tracking
GET  /routes
GET  /reports
PATCH /reports/:id
```

### مطلوب إضافته أو تحسينه

```txt
GET    /admin/users
PATCH  /admin/users/:id/role

GET    /admin/drivers
PATCH  /admin/drivers/:id

GET    /admin/vehicles
POST   /admin/vehicles
PATCH  /admin/vehicles/:id

GET    /admin/audit-logs

GET    /analytics/timeseries
GET    /analytics/routes/:id
```

## خطة التنفيذ كسبرنتات

### Sprint 0 - تثبيت الأساس الأمني

الهدف: لا نبني dashboard فوق صلاحيات رخوة.

المهام:

- مراجعة `OperatorAuthGuard`.
- إضافة `RolesGuard`.
- إضافة `@Roles`.
- تحديد هل `Owner` هو السوبر أونر أو نضيف `SuperOwner`.
- حماية endpoints الإدارية.
- كتابة seed script يضيف owner test account واضح للاختبار المحلي.
- تجهيز حسابات اختبار للأدوار الأساسية:
  - Owner.
  - Admin.
  - Operator.
  - Support.
- اختبار كل endpoint إداري عبر Postman أو Insomnia بأدوار مختلفة.
- توثيق النتيجة المتوقعة لكل دور:
  - 200/201 عند السماح.
  - 403 عند عدم امتلاك الصلاحية.
  - 401 عند غياب أو فساد token.
- اختبار endpoints الحالية المهمة:
  - `/analytics/overview`.
  - `/analytics/live-tracking`.
  - `/routes` create/update.
  - `/reports` list/review.

ناتج السبرنت:

- backend جاهز يستقبل dashboard بأمان، مع طريقة مكررة وواضحة لفحص الصلاحيات محلياً.

### Sprint 1 - Login + Layout + Overview mock

الهدف: أول نسخة قابلة للفتح والتصفح.

المهام:

- إنشاء `apps/admin`.
- إضافته إلى npm workspaces.
- إعداد Next.js + TypeScript.
- إعداد RTL.
- بناء Login.
- بناء layout.
- حماية routes.
- بناء Overview ببيانات وهمية أو adapter قابل للاستبدال.

ناتج السبرنت:

- داشبورد يفتح محلياً.
- تسجيل دخول يعمل.
- Overview مبدئي.

### Sprint 2 - ربط Overview + Live Map + Routes list

الهدف: تحويل الداشبورد من شكل إلى أداة مراقبة حقيقية.

المهام:

- ربط `GET /analytics/overview`.
- ربط `GET /analytics/live-tracking`.
- بناء MapLibre map.
- عرض المركبات والمناطق المجمعة.
- بناء Routes list.
- فلترة وبحث أساسي.

ناتج السبرنت:

- السوبر أونر يشوف الحالة الحية والخطوط.

### Sprint 3 - Reports

الهدف: إدارة البلاغات من الداشبورد.

المهام:

- بناء Reports table.
- فلاتر حسب الحالة والنوع.
- صفحة أو panel للتفاصيل.
- قبول/رفض البلاغ.
- إظهار reviewer ووقت المراجعة إذا مدعوم.

ناتج السبرنت:

- دورة البلاغات تعمل من الداشبورد.

### Sprint 4 - Drivers & Vehicles

الهدف: إدارة التشغيل.

المهام:

- APIs للسواق والمركبات إذا غير موجودة.
- عرض السواق.
- عرض المركبات.
- ربط السائق بالمركبة.
- ربط المركبة بخط.
- تعطيل/تفعيل.

ناتج السبرنت:

- إدارة تشغيلية أساسية للسواق والمركبات.

### Sprint 5 - Users, Roles, Audit Logs

الهدف: إدارة إدارية كاملة وقابلة للمحاسبة.

المهام:

- إدارة المستخدمين الإداريين.
- تعديل الأدوار.
- منع تغييرات خطرة بدون Owner.
- إنشاء Audit Log.
- عرض Audit Logs داخل الداشبورد.

ناتج السبرنت:

- صلاحيات واضحة وسجل تغييرات.

### Sprint 6 - Production readiness

الهدف: تجهيز للإطلاق.

المهام:

- مراجعة security.
- تحسين session handling.
- تحسين loading/error states.
- اختبارات أساسية.
- build production.
- إعداد deployment.

ناتج السبرنت:

- نسخة جاهزة للنشر.

## Deployment

الخيار المفضل:

```txt
admin.kiyat.app
```

مع API منفصل:

```txt
api.kiyat.app
```

أو في البداية:

```txt
kiyat.app/admin
```

لكن subdomain أنظف وأوضح أمنياً وتشغيلياً.

خيارات النشر:

1. نفس السيرفر:
   - Nginx reverse proxy.
   - backend على port داخلي.
   - admin Next.js على port داخلي.
   - SSL عبر Let's Encrypt.

2. سيرفر منفصل:
   - أفضل لاحقاً إذا كبر الحمل.
   - فصل أوضح بين backend والواجهة.

3. منصة managed:
   - Vercel للـ admin.
   - VPS أو container للـ backend.
   - يحتاج ضبط CORS وcookies بعناية.

التوصية:

- في البداية نفس السيرفر مع subdomain منفصل.
- لاحقاً يمكن فصل admin إذا احتاج.

## قرارات مطلوبة قبل التنفيذ

قبل البدء بالكود يجب تثبيت هذه القرارات:

1. هل نستخدم `Owner` كسوبر أونر، أم نضيف `SuperOwner`؟
2. هل Auth يكون:
   - OTP + session طويلة للـ MVP؟
   - أم email/password من البداية؟
3. هل الخريطة تبدأ polling على `/analytics/live-tracking` أم WebSocket مباشرة؟
4. هل النشر المستهدف:
   - `admin.kiyat.app`
   - أم `/admin` على نفس الدومين؟
5. هل نبدأ بسبرنت 0 فقط، أم Sprint 0 + Sprint 1 معاً؟

## التوصية النهائية

أنسب مسار عملي:

1. نثبت RBAC أولاً في backend.
2. نبدأ بـ `Owner` كسوبر أونر مبدئياً.
3. نستخدم OTP + session طويلة في MVP.
4. نبدأ الخريطة بـ polling حتى لا نعقد البداية.
5. ننشر لاحقاً على `admin.kiyat.app`.

أول تنفيذ مقترح بعد الموافقة:

```txt
Sprint 0 -> Sprint 1
```

أي:

- تثبيت الصلاحيات.
- إنشاء تطبيق admin.
- login.
- layout.
- overview مبدئي.
