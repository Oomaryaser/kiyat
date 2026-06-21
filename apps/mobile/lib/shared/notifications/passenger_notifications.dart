import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final passengerNotifications = PassengerNotifications();

class PassengerNotifications {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      ),
    );
    _initialized = true;
  }

  Future<void> requestPermission() async {
    if (kIsWeb) return;
    await initialize();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    await _plugin
        .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<void> showArrivalAlert({
    required String vehicleLabel,
    required int etaMinutes,
    bool arrived = false,
  }) async {
    if (kIsWeb) return;
    await initialize();
    await _plugin.show(
      id: 21,
      title: arrived ? 'الكية وصلت' : 'الكية قربت',
      body: arrived
          ? '$vehicleLabel وصلت تقريباً لنقطة صعودك. اطلع الحين.'
          : '$vehicleLabel توصل تقريباً خلال $etaMinutes دقيقة.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'kiyat_arrivals',
          'تنبيهات وصول الكيات',
          channelDescription: 'تنبيهات عندما تقترب الكية من الراكب',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }
}
