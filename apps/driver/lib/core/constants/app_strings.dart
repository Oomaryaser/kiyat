/// All user-facing Arabic strings (Iraqi dialect).
abstract final class AppStrings {
  // ── App ────────────────────────────────────────────────────────────
  static const appTitle = 'كيات السائق';

  // ── Onboarding ─────────────────────────────────────────────────────
  static const onboardingTitle1 = 'استقبل الطلبات';
  static const onboardingBody1 = 'شوف الركاب اللي منتظرين على خطك وروح لهم مباشرة.';
  static const onboardingTitle2 = 'تتبع مباشر';
  static const onboardingBody2 = 'موقعك يتحدث تلقائياً والركاب يشوفون كيتك لحظة بلحظة.';
  static const onboardingTitle3 = 'خدمتك للناس';
  static const onboardingBody3 = 'ساعد أهل بغداد يوصلون بأمان وسرعة — خدمة وأجر.';
  static const skip = 'تخطي';
  static const next = 'التالي';
  static const getStarted = 'يلا نبدي';

  // ── Auth ────────────────────────────────────────────────────────────
  static const authTitle = 'دخول السائق';
  static const phoneLabel = 'رقم الهاتف';
  static const phoneHint = '7XX XXX XXXX';
  static const sendOtp = 'إرسال رمز التأكيد';
  static const otpTitle = 'ادخل رمز التأكيد';
  static const otpSentTo = 'أرسلنا رمز التأكيد إلى';
  static const verifyOtp = 'تأكيد';
  static const resendOtp = 'إعادة إرسال الرمز';
  static const resendIn = 'إعادة الإرسال بعد';
  static const seconds = 'ث';
  static const phoneError = 'ادخل رقم هاتف عراقي صحيح';
  static const otpError = 'ادخل الرمز الكامل';
  static const loginFailed = 'تعذر الدخول';
  static const authHeroTitle = 'حساب السائق';
  static const authHeroBody = 'ادخل برقمك حتى نربط الكية بحسابك ونحمي التتبع.';
  static const waiting = 'انتظر...';

  // ── Home ────────────────────────────────────────────────────────────
  static const homeTitle = 'كيات السائق';
  static const heroTitle = 'تطبيق السائق';
  static const heroBody = 'اختار خطك وشغل التتبع حتى الركاب يشوفون كيتك.';
  static const plateLabel = 'اسم/رقم الكية';
  static const chooseRoute = 'اختار خطك';
  static const startTracking = 'بدء التتبع';
  static const starting = 'دا نبدي...';
  static const online = 'متصل';
  static const offline = 'غير متصل';
  static const goOnline = 'تشغيل';
  static const goOffline = 'إيقاف';
  static const confirmOfflineTitle = 'إيقاف التتبع؟';
  static const confirmOfflineBody = 'إذا وقفت التتبع الراكب ما راح يشوف كيتك.';
  static const cancel = 'إلغاء';
  static const stop = 'إيقاف';
  static const noRoutes = 'ماكو خطوط حالياً';
  static const noRoutesHint = 'شغل seed البيانات أو أضف خطوط من لوحة السيرفر.';
  static const routesFetchError = 'ما قدرنا نجيب الخطوط';
  static const routesFetchErrorHint = 'تأكد من تشغيل الباكند والاتصال.';
  static const retry = 'إعادة المحاولة';
  static const refresh = 'تحديث';
  static const fareUnknown = 'الأجرة غير محددة';
  static const hoursUnknown = 'الوقت غير محدد';

  // ── Tracking ───────────────────────────────────────────────────────
  static const trackingActive = 'التتبع شغال والركاب يشوفون كيتك.';
  static const trackingStopped = 'التتبع متوقف';
  static const trackingOn = 'التتبع شغال';
  static const stopTracking = 'إيقاف التتبع';
  static const stopping = 'دا نوقف...';
  static const locationPermissionNeeded = 'نحتاج صلاحية الموقع حتى يشوفك الراكب.';
  static const locationServiceOff = 'خدمة الموقع مطفية. شغلها حتى تبدي التتبع.';
  static const requestingLocation = 'دا نطلب صلاحية الموقع...';
  static const trackingStartError = 'ما قدرنا نشغل التتبع. جرّب مرة ثانية.';
  static const waitUpdateError = 'ما قدرنا نحدث ركاب الانتظار.';
  static const goToNearestPassenger = 'روح لأقرب راكب';
  static const continueOnRoute = 'استمر على خطك';
  static const passengerOnMap = 'الراكب ظاهر على الخريطة';
  static const noWaitingPassengers = 'ماكو ركاب منتظرين حالياً، راقب الخريطة.';
  static const goHere = 'روح لهنا';
  static const nearestPassengerOnMap = 'أقرب راكب محدد على الخريطة';
  static const mapWaitingForLocation = 'الخريطة تنتظر الموقع';
  static const mapWaitingHint = 'أول ما يوصل موقع الكية راح تظهر الخريطة هنا.';
  static const driverPosition = 'موقع كيتك الحالي';
  static const waitingPassenger = 'راكب ينتظر';

  // ── Earnings ───────────────────────────────────────────────────────
  static const earningsTitle = 'الأرباح';
  static const todayEarnings = 'أرباح اليوم';
  static const tripsToday = 'رحلات اليوم';
  static const avgRating = 'التقييم';
  static const weeklyChart = 'أرباح الأسبوع';
  static const tripHistory = 'سجل الرحلات';
  static const noTrips = 'ماكو رحلات لحد الآن';
  static const noTripsHint = 'ابدي خطك وأرباحك راح تظهر هنا.';
  static const currency = 'د.ع';

  // ── Settings ───────────────────────────────────────────────────────
  static const settingsTitle = 'الإعدادات';
  static const driverInfo = 'معلومات السائق';
  static const vehicleInfo = 'معلومات الكية';
  static const theme = 'المظهر';
  static const lightTheme = 'فاتح';
  static const darkTheme = 'داكن';
  static const systemTheme = 'النظام';
  static const notifications = 'الإشعارات';
  static const notificationsHint = 'إشعارات الركاب والتحديثات';
  static const support = 'المساعدة والدعم';
  static const terms = 'الشروط والأحكام';
  static const signOut = 'تسجيل خروج';
  static const signOutConfirmTitle = 'تسجيل الخروج؟';
  static const signOutConfirmBody = 'راح تنطرد من حسابك وتحتاج تدخل مرة ثانية.';
  static const confirm = 'تأكيد';
  static const driverName = 'سائق كيات';
  static const editProfile = 'تعديل الملف';

  // ── Bottom nav ─────────────────────────────────────────────────────
  static const navHome = 'الرئيسية';
  static const navEarnings = 'الأرباح';
  static const navSettings = 'الإعدادات';

  // ── Errors ─────────────────────────────────────────────────────────
  static const genericError = 'صار خطأ';
  static const networkError = 'ماكو اتصال بالإنترنت';
  static const serverError = 'السيرفر تعبان حالياً';
  static const vehicleCreateError = 'ما قدرنا نسجل الكية على هذا الخط.';

  // ── Helpers ────────────────────────────────────────────────────────
  static String distanceLabel(double meters) {
    if (meters < 1000) return '${_arabicDigits(meters.round())} م';
    return '${_arabicDigits((meters / 1000).toStringAsFixed(1))} كم';
  }

  static String arabicDigits(Object value) => _arabicDigits(value);
}

String _arabicDigits(Object value) {
  const western = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
  const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  var result = value.toString();
  for (var i = 0; i < western.length; i++) {
    result = result.replaceAll(western[i], arabic[i]);
  }
  return result;
}
