import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_database/firebase_database.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: androidSettings);

    await notifications.initialize(settings: initializationSettings);

    // Android 13+ notification permission
    await notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  static Future<void> showAirQualityAlert({
    required int pm25,
    required int co,
    required int o3,
  }) async {
    const String title = 'Poor Air Quality Detected';

    final String message = 'PM2.5: $pm25 µg/m³ | CO: $co ADC | O₃: $o3 ADC';

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'air_quality_alerts',
          'Air Quality Alerts',
          channelDescription: 'Alerts when poor air quality is detected',
          importance: Importance.high,
          priority: Priority.high,
        );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    // Show phone notification
    await notifications.show(
      id: 1,
      title: title,
      body: message,
      notificationDetails: details,
    );

    // Save notification to Firebase
    final DatabaseReference notificationRef = FirebaseDatabase.instance.ref(
      'notifications',
    );

    final int timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await notificationRef.child(timestamp.toString()).set({
      'title': title,
      'message': message,
      'timestamp': timestamp,
    });
  }

  static Future<void> showSuddenSpikeAlert({
    required int previousPm25,
    required int currentPm25,
  }) async {
    const String title = 'Sudden Air Quality Change';

    final int increase = currentPm25 - previousPm25;

    final String message =
        'PM2.5 suddenly increased by $increase µg/m³ '
        '($previousPm25 → $currentPm25 µg/m³).';

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'sudden_spike_alerts',
          'Sudden Air Quality Alerts',
          channelDescription: 'Alerts when a sudden PM2.5 increase is detected',
          importance: Importance.high,
          priority: Priority.high,
        );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    await notifications.show(
      id: 2,
      title: title,
      body: message,
      notificationDetails: details,
    );

    final DatabaseReference notificationRef = FirebaseDatabase.instance.ref(
      'notifications',
    );

    final int timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await notificationRef.child(timestamp.toString()).set({
      'title': title,
      'message': message,
      'timestamp': timestamp,
      'type': 'sudden_spike',
    });
  }

  static Future<void> showForecastAlert({
    required int currentPm25,
    required double predictedPm25,
    required String trend,
  }) async {
    const String title = 'Air Quality Forecast Warning';

    final String message =
        'PM2.5 is predicted to change from '
        '$currentPm25 to ${predictedPm25.toStringAsFixed(1)} µg/m³ '
        'within the next hour. Trend: $trend.';

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'forecast_alerts',
          'Forecast Alerts',
          channelDescription:
              'Alerts when future air quality is predicted to worsen',
          importance: Importance.high,
          priority: Priority.high,
        );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    await notifications.show(
      id: 3,
      title: title,
      body: message,
      notificationDetails: details,
    );

    final DatabaseReference notificationRef = FirebaseDatabase.instance.ref(
      'notifications',
    );

    final int timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await notificationRef.child(timestamp.toString()).set({
      'title': title,
      'message': message,
      'timestamp': timestamp,
      'type': 'forecast_warning',
    });
  }

  static Future<void> showAiAlert({
    required String title,
    required String message,
    required String type,
    required int timestamp,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'ai_alerts',
          'AI Air Quality Alerts',
          channelDescription: 'AI-generated air quality alert messages',
          importance: Importance.high,
          priority: Priority.high,
        );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    await notifications.show(
      id: timestamp,
      title: title,
      body: message,
      notificationDetails: details,
    );

    final DatabaseReference notificationRef = FirebaseDatabase.instance.ref(
      'notifications',
    );

    await notificationRef.child(timestamp.toString()).set({
      'title': title,
      'message': message,
      'type': type,
      'timestamp': timestamp,
    });
  }
}
