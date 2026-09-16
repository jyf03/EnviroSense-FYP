import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import 'firebase_options.dart';
import 'history_page.dart';
import 'user_page.dart';
import 'notification_service.dart';
import 'notification_page.dart';
import 'aqi_details_page.dart';
import 'dart:collection';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_page.dart';

class _PmSample {
  final DateTime timestamp;
  final double pm25;
  final double pm10;

  _PmSample({required this.timestamp, required this.pm25, required this.pm10});
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await NotificationService.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Environment monitor',

      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4A90E2),
        ),

        scaffoldBackgroundColor:
        const Color(0xFFEAF6FF),

        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFEAF6FF),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),

        bottomNavigationBarTheme:
        const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: Color(0xFF3977B8),
          unselectedItemColor: Colors.grey,
        ),
      ),

      // Always enter your main application.
      home: const MyHomePage(
        title: 'EnviroSense',
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool wasBad = false;

  int currentIndex = 0;
  int lastAiAlertTimestamp = 0;
  // ============================================
  // LIVE SENSOR VALUES
  // ============================================

  double temperature = 0;
  double humidity = 0;
  double pressure = 0;

  int pm1 = 0;
  int pm25 = 0;
  int pm10 = 0;
  int co = 0;
  int o3 = 0;

  // ============================================
  // 5-MINUTE ROLLING AQI WINDOW
  // ============================================

  final Queue<_PmSample> pmSamples = Queue<_PmSample>();

  double rollingPm25 = 0;
  double rollingPm10 = 0;
  double displayedOverallAqi = 0;
  String displayedMainPollutant = 'PM2.5';

  void addPmReading(int newPm25, int newPm10) {
    final now = DateTime.now();

    pmSamples.addLast(
      _PmSample(
        timestamp: now,
        pm25: newPm25.toDouble(),
        pm10: newPm10.toDouble(),
      ),
    );

    final cutoff = now.subtract(const Duration(minutes: 5));

    while (pmSamples.isNotEmpty && pmSamples.first.timestamp.isBefore(cutoff)) {
      pmSamples.removeFirst();
    }

    if (pmSamples.isEmpty) {
      return;
    }

    //calculate rolling average for pm2.5 and pm10
    final avgPm25 =
        pmSamples.map((sample) => sample.pm25).reduce((a, b) => a + b) /
        pmSamples.length;

    final avgPm10 =
        pmSamples.map((sample) => sample.pm10).reduce((a, b) => a + b) /
        pmSamples.length;

    final pm25Aqi = calculatePm25Aqi(avgPm25);
    final pm10Aqi = calculatePm10Aqi(avgPm10);

    rollingPm25 = avgPm25;
    rollingPm10 = avgPm10;
    displayedOverallAqi = pm25Aqi >= pm10Aqi ? pm25Aqi : pm10Aqi;
    displayedMainPollutant = pm25Aqi >= pm10Aqi ? 'PM2.5' : 'PM10';
  }

  // ============================================
  // SUDDEN TEMPERATURE INCREASE DETECTION
  // ============================================

  double previousTemperature = 0;

  bool detectSuddenTemperatureIncrease(double currentTemperature) {
    if (previousTemperature == 0) {
      previousTemperature = currentTemperature;
      return false;
    }

    final increase = currentTemperature - previousTemperature;

    // Prototype threshold: alert when temperature rises by 3.0 °C
    // between consecutive Firebase readings.
    return increase >= 3.0;
  }

  // ============================================
  // SUDDEN PM2.5 SPIKE DETECTION
  // ============================================

  int previousPm25 = 0;

  bool detectSuddenPm25Spike(int currentPm25) {
    if (previousPm25 == 0) {
      previousPm25 = currentPm25;
      return false;
    }

    final increase = currentPm25 - previousPm25;
    return increase >= 30;
  }

  String lastForecastCategory = '';
  String lastOverallAqiCategory = '';
  bool isOverallAqiExpanded = false;

  void checkForecastNotification() {
    if (forecastAqiHour1 <= 0) {
      return;
    }

    final String currentCategory = getAqiCategory(forecastAqiHour1);

    if (currentCategory != lastForecastCategory) {
      sendAlertRequest(
        type: 'forecast_update',
        currentPm25: pm25,
        predictedAqi: forecastAqiHour1,
        trend: forecastTrend,
        forecastCategory: currentCategory,
      );

      lastForecastCategory = currentCategory;
    }
  }
  // ============================================
  // BASELINE VALUES
  // ============================================
  String getBaselineStatus(double value, double baseline) {
    if (value <= baseline) {
      return 'Normal';
    }

    final deviation = ((value - baseline) / baseline) * 100;

    if (deviation > 25) {
      return 'Abnormal';
    } else if (deviation > 10) {
      return 'Elevated';
    } else {
      return 'Normal';
    }
  }

  static const double coBaseline = 519;
  static const double o3Baseline = 854;

  // ============================================
  // AI FORECAST VALUES
  // ============================================

  double predictedAqi = 0;

  double forecastAqiHour1 = 0;
  double forecastAqiHour2 = 0;
  double forecastAqiHour3 = 0;
  double forecastAqiHour4 = 0;

  String forecastTrend = 'Unknown';

  String forecastHorizon = '1 hour';

  int aiTimestamp = 0;

  // ============================================
  // GENERATIVE AI RECOMMENDATION
  // ============================================

  String aiRecommendation = 'Generating recommendation...';

  String recommendationStatus = '';

  // ============================================
  // FIREBASE REFERENCES
  // ============================================

  DatabaseReference? get notificationSettingsRef {
    final user =
        FirebaseAuth.instance.currentUser;

    if (user == null) {
      return null;
    }

    return FirebaseDatabase.instance.ref(
      'users/${user.uid}/notificationSettings',
    );
  }

  final DatabaseReference databaseRef = FirebaseDatabase.instance.ref(
    'environment',
  );

  final DatabaseReference aiResultRef = FirebaseDatabase.instance.ref(
    'ai_result',
  );

  final DatabaseReference aiRecommendationRef = FirebaseDatabase.instance.ref(
    'ai_recommendation',
  );

  final DatabaseReference alertRequestRef = FirebaseDatabase.instance.ref(
    'alert_request',
  );

  final DatabaseReference aiAlertRef = FirebaseDatabase.instance.ref(
    'ai_alert',
  );

  // ============================================
  // REUSABLE GROUPED CARD
  // ============================================

  Widget groupedCard({
    required String title,
    required List<Widget> children,
    VoidCallback? onTap,
  }) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                if (onTap != null)
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 24),
                    onPressed: onTap,
                  ),
              ],
            ),

            const SizedBox(height: 8),

            ...children,
          ],
        ),
      ),
    );
  }

  // ============================================
  // SENSOR ROW
  // ============================================

  Widget groupedSensorRow(
    String title,
    String value,
    IconData icon,
    Color iconColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 24, color: iconColor),

          const SizedBox(width: 12),

          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),

          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // ============================================
  // ENVIRONMENT COLUMN
  // ============================================

  Widget groupedSensorStatusRow(
    String title,
    String value,
    String status,
    IconData icon,
    Color iconColor,
  ) {
    Color statusColor;

    if (status == 'Bad' || status == 'Abnormal') {
      statusColor = Colors.red;
    } else if (status == 'Average' || status == 'Elevated') {
      statusColor = Colors.orange;
    } else {
      statusColor = Colors.green;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 24, color: iconColor),

          const SizedBox(width: 12),

          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),

          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),

          const SizedBox(width: 8),

          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  Widget groupedSensorColumn(
    String title,
    String value,
    IconData icon,
    Color iconColor,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 26, color: iconColor),

        const SizedBox(height: 8),

        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 5),

        Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14),
        ),
      ],
    );
  }

  // ============================================
  // BASELINE DEVIATION
  // ============================================

  double getCoDeviation() {
    return ((co - coBaseline).abs() / coBaseline) * 100;
  }

  double getO3Deviation() {
    return ((o3 - o3Baseline).abs() / o3Baseline) * 100;
  }

  String getDeviationStatus(double deviation) {
    if (deviation > 25) {
      return 'Abnormal';
    } else if (deviation > 10) {
      return 'Elevated';
    } else {
      return 'Normal';
    }
  }

  // PM2.5 status
  String getPm25Status() {
    if (pm25 > 100) {
      return 'Bad';
    } else if (pm25 > 50) {
      return 'Average';
    } else {
      return 'Good';
    }
  }

  String getPm1Status() {
    if (pm1 > 100) {
      return 'Bad';
    } else if (pm1 > 50) {
      return 'Average';
    } else {
      return 'Good';
    }
  }

  String getPm10Status() {
    if (pm10 > 150) {
      return 'Bad';
    } else if (pm10 > 75) {
      return 'Average';
    } else {
      return 'Good';
    }
  }

  double calculatePm25Aqi(double concentration) {
    if (concentration <= 9.0) {
      return calculateAqi(concentration, 0.0, 9.0, 0, 50);
    } else if (concentration <= 35.4) {
      return calculateAqi(concentration, 9.1, 35.4, 51, 100);
    } else if (concentration <= 55.4) {
      return calculateAqi(concentration, 35.5, 55.4, 101, 150);
    } else if (concentration <= 125.4) {
      return calculateAqi(concentration, 55.5, 125.4, 151, 200);
    } else if (concentration <= 225.4) {
      return calculateAqi(concentration, 125.5, 225.4, 201, 300);
    } else if (concentration <= 325.4) {
      return calculateAqi(concentration, 225.5, 325.4, 301, 500);
    }

    return 500;
  }

  double getPredictedAqi() {
    return predictedAqi;
  }

  double calculatePm10Aqi(double concentration) {
    if (concentration <= 54) {
      return calculateAqi(concentration, 0, 54, 0, 50);
    } else if (concentration <= 154) {
      return calculateAqi(concentration, 55, 154, 51, 100);
    } else if (concentration <= 254) {
      return calculateAqi(concentration, 155, 254, 101, 150);
    } else if (concentration <= 354) {
      return calculateAqi(concentration, 255, 354, 151, 200);
    } else if (concentration <= 424) {
      return calculateAqi(concentration, 355, 424, 201, 300);
    } else if (concentration <= 604) {
      return calculateAqi(concentration, 425, 604, 301, 500);
    }

    return 500;
  }

  double getOverallAqi() {
    if (displayedOverallAqi > 0) {
      return displayedOverallAqi;
    }

    final double pm25Aqi = calculatePm25Aqi(pm25.toDouble());
    final double pm10Aqi = calculatePm10Aqi(pm10.toDouble());

    return pm25Aqi > pm10Aqi ? pm25Aqi : pm10Aqi;
  }

  String getMainPollutant() {
    if (displayedOverallAqi > 0) {
      return displayedMainPollutant;
    }

    final double pm25Aqi = calculatePm25Aqi(pm25.toDouble());
    final double pm10Aqi = calculatePm10Aqi(pm10.toDouble());

    return pm25Aqi >= pm10Aqi ? 'PM2.5' : 'PM10';
  }

  double calculateAqi(
    double concentration,
    double cLow,
    double cHigh,
    int iLow,
    int iHigh,
  ) {
    return ((iHigh - iLow) / (cHigh - cLow)) * (concentration - cLow) + iLow;
  }

  String getAqiCategory(double aqi) {
    if (aqi <= 50) {
      return 'Good';
    } else if (aqi <= 100) {
      return 'Moderate';
    } else if (aqi <= 150) {
      return 'Poor';
    } else if (aqi <= 200) {
      return 'Unhealthy';
    } else if (aqi <= 300) {
      return 'Very Unhealthy';
    } else {
      return 'Hazardous';
    }
  }

  String getNotificationAqiCategory(double aqi) {
    if (lastOverallAqiCategory.isEmpty) {
      return getAqiCategory(aqi);
    }

    switch (lastOverallAqiCategory) {
      case 'Good':
        if (aqi >= 55) return 'Moderate';
        return 'Good';

      case 'Moderate':
        if (aqi <= 45) return 'Good';
        if (aqi >= 105) return 'Poor';
        return 'Moderate';

      case 'Poor':
        if (aqi <= 95) return 'Moderate';
        if (aqi >= 155) return 'Unhealthy';
        return 'Poor';

      case 'Unhealthy':
        if (aqi <= 145) return 'Poor';
        if (aqi >= 205) return 'Very Unhealthy';
        return 'Unhealthy';

      case 'Very Unhealthy':
        if (aqi <= 195) return 'Unhealthy';
        if (aqi >= 305) return 'Hazardous';
        return 'Very Unhealthy';

      case 'Hazardous':
        if (aqi <= 295) return 'Very Unhealthy';
        return 'Hazardous';

      default:
        return getAqiCategory(aqi);
    }
  }

  Color getAqiColor(double aqi) {
    if (aqi <= 50) {
      return Colors.green;
    } else if (aqi <= 100) {
      return Colors.orange;
    } else if (aqi <= 150) {
      return Colors.deepOrange;
    } else if (aqi <= 200) {
      return Colors.red;
    } else if (aqi <= 300) {
      return Colors.purple;
    } else {
      return Colors.brown;
    }
  }

  Color getAqiBackgroundColor(double aqi) {
    final baseColor = getAqiColor(aqi);

    // Mix AQI color with white to make it soft/pastel
    return Color.lerp(Colors.white, baseColor, 0.10)!;
  }

  // ============================================
  // CURRENT OVERALL AIR QUALITY
  // ============================================

  String getAirQualityStatus() {
    final double coDeviation = getCoDeviation();

    final double o3Deviation = getO3Deviation();

    final pm25ForStatus = rollingPm25 > 0 ? rollingPm25 : pm25.toDouble();

    if (pm25ForStatus > 100 || coDeviation > 25 || o3Deviation > 25) {
      return 'Bad';
    } else if (pm25ForStatus > 50 || coDeviation > 10 || o3Deviation > 10) {
      return 'Average';
    } else {
      return 'Good';
    }
  }

  // ============================================
  // CURRENT STATUS COLOR
  // ============================================

  Color getStatusColor() {
    final status = getAirQualityStatus();

    if (status == 'Bad') {
      return Colors.red;
    } else if (status == 'Average') {
      return Colors.orange;
    } else {
      return Colors.green;
    }
  }

  // ============================================
  // AI FORECAST STATUS
  // ============================================

  String getForecastStatus() {
    if (forecastAqiHour1 <= 0) {
      return 'Waiting';
    }

    return getAqiCategory(forecastAqiHour1);
  }

  // ============================================
  // FORECAST STATUS COLOR
  // ============================================

  Color getForecastStatusColor() {
    if (forecastAqiHour1 <= 0) {
      return Colors.grey;
    }

    return getAqiColor(forecastAqiHour1);
  }

  // ============================================
  // FORECAST TREND ICON
  // ============================================

  IconData getForecastTrendIcon() {
    if (forecastTrend == 'Increasing') {
      return Icons.trending_up;
    } else if (forecastTrend == 'Decreasing') {
      return Icons.trending_down;
    } else {
      return Icons.trending_flat;
    }
  }

  String getForecastTime(int hoursAhead) {
    final DateTime now = DateTime.now();

    // Start from the beginning of the next hour
    final DateTime nextHour = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour + 1,
    );

    final DateTime time = nextHour.add(Duration(hours: hoursAhead - 1));

    final int hour12 = time.hour == 0
        ? 12
        : (time.hour > 12 ? time.hour - 12 : time.hour);

    final String period = time.hour >= 12 ? 'PM' : 'AM';

    return '$hour12:00 $period';
  }

  Widget forecastBox({required String label, required double aqi}) {
    return SizedBox(
      width: 92,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: getAqiColor(aqi).withOpacity(0.15),
            ),
            child: Text(
              aqi.round().toString(),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: getAqiColor(aqi),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            getAqiCategory(aqi),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: getAqiColor(aqi),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // CURRENT OVERALL AQI NOTIFICATION
  // ============================================

  Future<void> checkOverallAqiNotification() async {
    final double overallAqi = getOverallAqi();

    if (overallAqi <= 0) {
      return;
    }

    final String currentCategory = getNotificationAqiCategory(overallAqi);

    // Notify on first valid AQI reading and whenever the category changes
    if (currentCategory != lastOverallAqiCategory) {
      final int timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      String title;
      String message;

      if (currentCategory == 'Good') {
        title = 'Current Air Quality: Good';
        message =
            'Estimated overall AQI is ${overallAqi.round()}. '
            'Current air quality is Good.';
      } else if (currentCategory == 'Moderate') {
        title = 'Current Air Quality: Moderate';
        message =
            'Estimated overall AQI is ${overallAqi.round()}. '
            'Current air quality is Moderate.';
      } else {
        title = 'Current Air Quality: $currentCategory';
        message =
            'Estimated overall AQI is ${overallAqi.round()}. '
            'Current air quality is $currentCategory.';
      }

      await NotificationService.showAiAlert(
        title: title,
        message: message,
        type: 'current_aqi',
        timestamp: timestamp,
      );

      lastOverallAqiCategory = currentCategory;
    }
  }

  // ============================================
  // CURRENT BAD AIR NOTIFICATION
  // ============================================

  Future<void> checkAirQualityNotification() async {
    final ref = notificationSettingsRef;

    if (ref == null) {
      return;
    }

    final snapshot = await ref.get();

    bool airQualityAlerts = true;

    if (snapshot.exists) {
      final data =
      Map<String, dynamic>.from(snapshot.value as Map);

      airQualityAlerts =
          data['airQualityAlerts'] ?? true;
    }

    if (!airQualityAlerts) {
      return;
    }

    final double coDeviation = getCoDeviation();
    final double o3Deviation = getO3Deviation();

    final double pm25ForStatus =
    rollingPm25 > 0 ? rollingPm25 : pm25.toDouble();

    final bool isBad =
        pm25ForStatus > 100 ||
            coDeviation > 25 ||
            o3Deviation > 25;

    if (isBad && !wasBad) {
      await sendAlertRequest(
        type: 'current_bad',
        currentPm25: pm25,
      );

      wasBad = true;
    }

    if (!isBad) {
      wasBad = false;
    }
  }

  // ============================================
  // FIREBASE LISTENERS
  // ============================================

  Future<void> sendAlertRequest({
    required String type,
    required int currentPm25,
    int? previousPm25,
    double? predictedAqi,
    String? trend,
    String? forecastCategory,
  }) async {
    final Map<String, dynamic> data = {
      'type': type,
      'current_pm25': currentPm25,
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    };

    if (previousPm25 != null) {
      data['previous_pm25'] = previousPm25;
    }

    if (predictedAqi != null) {
      data['predicted_aqi'] = predictedAqi;
    }

    if (trend != null) {
      data['trend'] = trend;
    }

    if (forecastCategory != null) {
      data['forecast_category'] = forecastCategory;
    }

    await alertRequestRef.set(data);
  }

  @override
  void initState() {
    super.initState();

    // ============================================
    // 1. LIVE ENVIRONMENT SENSOR DATA
    // ============================================

    databaseRef.onValue.listen((DatabaseEvent event) async {
      final data = event.snapshot.value;

      if (data != null) {
        final sensorData = Map<String, dynamic>.from(data as Map);

        final newTemperature =
            double.tryParse(sensorData['temperature'].toString()) ?? 0;

        final newHumidity =
            double.tryParse(sensorData['humidity'].toString()) ?? 0;

        final newPressure =
            double.tryParse(sensorData['pressure'].toString()) ?? 0;

        final newPm1 = int.tryParse(sensorData['pm1'].toString()) ?? 0;

        final newPm25 = int.tryParse(sensorData['pm25'].toString()) ?? 0;

        final newPm10 = int.tryParse(sensorData['pm10'].toString()) ?? 0;

        addPmReading(newPm25, newPm10);

        final newCo = int.tryParse(sensorData['co_adc'].toString()) ?? 0;

        final newO3 = int.tryParse(sensorData['o3_adc'].toString()) ?? 0;

        if (!mounted) return;

        setState(() {
          temperature = newTemperature;
          humidity = newHumidity;
          pressure = newPressure;

          pm1 = newPm1;
          pm25 = newPm25;
          pm10 = newPm10;

          co = newCo;
          o3 = newO3;
        });

        // ============================================
        // SUDDEN TEMPERATURE INCREASE ALERT
        // ============================================

        final oldTemperature = previousTemperature;

        final suddenTemperatureIncrease = detectSuddenTemperatureIncrease(
          newTemperature,
        );

        if (suddenTemperatureIncrease) {
          final int temperatureAlertTimestamp =
              DateTime.now().millisecondsSinceEpoch ~/ 1000;

          await NotificationService.showAiAlert(
            title: 'Sudden Temperature Increase',
            message:
                'Temperature increased suddenly from '
                '${oldTemperature.toStringAsFixed(1)} °C to '
                '${newTemperature.toStringAsFixed(1)} °C. Please check the environment.',
            type: 'temperature_spike',
            timestamp: temperatureAlertTimestamp,
          );

          print(
            'Sudden temperature increase detected: '
            '${oldTemperature.toStringAsFixed(1)} °C -> '
            '${newTemperature.toStringAsFixed(1)} °C',
          );
        }

        previousTemperature = newTemperature;

        // ============================================
        // SUDDEN PM2.5 SPIKE ALERT
        // ============================================

        final oldPm25 = previousPm25;

        print('Previous PM2.5: $previousPm25');
        print('Current PM2.5: $newPm25');

        final suddenSpike = detectSuddenPm25Spike(newPm25);

        print('Increase: ${newPm25 - oldPm25}');
        print('Sudden spike detected: $suddenSpike');

        if (suddenSpike) {
          print('SUDDEN SPIKE DETECTED');

          await sendAlertRequest(
            type: 'sudden_spike',
            currentPm25: newPm25,
            previousPm25: oldPm25,
          );

          print('Sudden spike alert request sent to Firebase');
        }

        previousPm25 = newPm25;

        // Avoid duplicate notifications for the same sudden PM2.5 event
        // If a sudden spike is detected, send only the sudden-spike alert.
        if (!suddenSpike) {
          checkOverallAqiNotification();
        }
      }
    });

    // ============================================
    // 2. LSTM AI FORECAST
    // ============================================

    aiResultRef.onValue.listen((DatabaseEvent event) {
      final data = event.snapshot.value;

      if (data != null) {
        final aiData = Map<String, dynamic>.from(data as Map);

        final newPrediction =
            double.tryParse(aiData['predicted_aqi'].toString()) ?? 0;

        final forecastData = aiData['forecast_aqi'] is Map
            ? Map<String, dynamic>.from(aiData['forecast_aqi'] as Map)
            : <String, dynamic>{};

        final newHour1 =
            double.tryParse(forecastData['hour_1']?.toString() ?? '') ??
            newPrediction;

        final newHour2 =
            double.tryParse(forecastData['hour_2']?.toString() ?? '') ?? 0;

        final newHour3 =
            double.tryParse(forecastData['hour_3']?.toString() ?? '') ?? 0;

        final newHour4 =
            double.tryParse(forecastData['hour_4']?.toString() ?? '') ?? 0;

        final newTrend = aiData['trend']?.toString() ?? 'Unknown';

        final newHorizon = aiData['forecast_horizon']?.toString() ?? '1 hour';

        final newTimestamp = int.tryParse(aiData['timestamp'].toString()) ?? 0;

        if (!mounted) return;

        setState(() {
          predictedAqi = newPrediction;

          forecastAqiHour1 = newHour1;
          forecastAqiHour2 = newHour2;
          forecastAqiHour3 = newHour3;
          forecastAqiHour4 = newHour4;

          forecastTrend = newTrend;
          forecastHorizon = newHorizon;
          aiTimestamp = newTimestamp;
        });

        checkForecastNotification();
      }
    });

    aiAlertRef.onValue.listen((DatabaseEvent event) async {
      final data = event.snapshot.value;

      if (data == null) return;

      final alertData = Map<String, dynamic>.from(data as Map);

      final title = alertData['title']?.toString() ?? 'Air Quality Alert';

      final message = alertData['message']?.toString() ?? '';

      final type = alertData['type']?.toString() ?? 'ai_alert';

      final timestamp = int.tryParse(alertData['timestamp'].toString()) ?? 0;

      if (message.isEmpty) return;

      // Prevent duplicate notification
      if (timestamp == lastAiAlertTimestamp) {
        return;
      }

      lastAiAlertTimestamp = timestamp;

      await NotificationService.showAiAlert(
        title: title,
        message: message,
        type: type,
        timestamp: timestamp,
      );
    });

    // ============================================
    // 3. GENERATIVE AI RECOMMENDATION
    // ============================================

    aiRecommendationRef.onValue.listen((DatabaseEvent event) {
      final data = event.snapshot.value;

      if (data != null) {
        final recommendationData = Map<String, dynamic>.from(data as Map);

        final newRecommendation =
            recommendationData['recommendation']?.toString() ??
            'No recommendation available.';

        final newStatus = recommendationData['status']?.toString() ?? '';

        if (!mounted) return;

        setState(() {
          aiRecommendation = newRecommendation;

          recommendationStatus = newStatus;
        });
      }
    });
  }

  // ============================================
  // BUILD UI
  // ============================================

  @override
  Widget build(BuildContext context) {
    final double overallAqi = getOverallAqi();
    final String aqiCategory = getAqiCategory(overallAqi);
    final String mainPollutant = getMainPollutant();

    final pages = [
      SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ============================================
            // OVERALL AIR QUALITY
            // ============================================
            Card(
              elevation: 3,
              color: Colors.transparent,
              shadowColor: getAqiColor(overallAqi).withOpacity(0.18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: getAqiBackgroundColor(overallAqi),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: getAqiColor(overallAqi).withOpacity(0.18),
                    width: 1.2,
                  ),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ============================================
                        // LEFT SIDE - ESTIMATED AQI
                        // ============================================
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: getAqiColor(overallAqi),
                                      shape: BoxShape.circle,
                                    ),
                                  ),

                                  const SizedBox(width: 8),

                                  const Text(
                                    'Estimated AQI',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 8),

                              Text(
                                overallAqi.round().toString(),
                                style: TextStyle(
                                  fontSize: 58,
                                  fontWeight: FontWeight.bold,
                                  height: 1,
                                  color: getAqiColor(overallAqi),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // ============================================
                        // RIGHT SIDE - AIR QUALITY CATEGORY
                        // ============================================
                        Expanded(
                          child: Column(
                            children: [
                              const Text(
                                'Air Quality is',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),

                              const SizedBox(height: 12),

                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: Color.lerp(
                                    Colors.white,
                                    getAqiColor(overallAqi),
                                    0.18,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: getAqiColor(
                                      overallAqi,
                                    ).withOpacity(0.12),
                                  ),
                                ),
                                child: Text(
                                  aqiCategory,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: getAqiColor(overallAqi),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 30),

                    // ============================================
                    // AQI COLOUR SCALE
                    // ============================================
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final double totalWidth = constraints.maxWidth;
                        final double clampedAqi = overallAqi
                            .clamp(0, 500)
                            .toDouble();

                        final double pointerPosition =
                            (clampedAqi / 500) * totalWidth;

                        return Column(
                          children: [
                            SizedBox(
                              height: 34,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  // Small pointer above the bar
                                  Positioned(
                                    left: (pointerPosition - 10).clamp(
                                      0.0,
                                      totalWidth - 20,
                                    ),
                                    top: 0,
                                    child: Icon(
                                      Icons.arrow_drop_down,
                                      size: 22,
                                      color: getAqiColor(clampedAqi),
                                    ),
                                  ),

                                  // AQI color bar
                                  Positioned(
                                    top: 18,
                                    left: 0,
                                    right: 0,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            flex: 50,
                                            child: Container(
                                              height: 10,
                                              color: Colors.green,
                                            ),
                                          ),
                                          Expanded(
                                            flex: 50,
                                            child: Container(
                                              height: 10,
                                              color: Colors.orange,
                                            ),
                                          ),
                                          Expanded(
                                            flex: 50,
                                            child: Container(
                                              height: 10,
                                              color: Colors.deepOrange,
                                            ),
                                          ),
                                          Expanded(
                                            flex: 50,
                                            child: Container(
                                              height: 10,
                                              color: Colors.red,
                                            ),
                                          ),
                                          Expanded(
                                            flex: 100,
                                            child: Container(
                                              height: 10,
                                              color: Colors.purple,
                                            ),
                                          ),
                                          Expanded(
                                            flex: 200,
                                            child: Container(
                                              height: 10,
                                              color: Colors.brown,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 8),
                          ],
                        );
                      },
                    ),

                    // ============================================
                    // AQI SCALE NUMBERS
                    // ============================================
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '0',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        Text(
                          '50',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        Text(
                          '100',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        Text(
                          '150',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        Text(
                          '200',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        Text(
                          '300',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        Text(
                          '500',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // ============================================
                    // FORECAST EXPAND BUTTON
                    // ============================================
                    IconButton(
                      onPressed: () {
                        setState(() {
                          isOverallAqiExpanded = !isOverallAqiExpanded;
                        });
                      },
                      icon: Icon(
                        isOverallAqiExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                      ),
                    ),

                    // ============================================
                    // EXISTING FORECAST
                    // ============================================
                    if (isOverallAqiExpanded) ...[
                      const Divider(),

                      const SizedBox(height: 8),

                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Air Quality Forecast',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      if (forecastAqiHour1 > 0)
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              forecastBox(label: 'Now', aqi: overallAqi),

                              const SizedBox(width: 8),

                              forecastBox(
                                label: getForecastTime(1),
                                aqi: forecastAqiHour1,
                              ),

                              const SizedBox(width: 8),

                              forecastBox(
                                label: getForecastTime(2),
                                aqi: forecastAqiHour2,
                              ),

                              const SizedBox(width: 8),

                              forecastBox(
                                label: getForecastTime(3),
                                aqi: forecastAqiHour3,
                              ),

                              const SizedBox(width: 8),

                              forecastBox(
                                label: getForecastTime(4),
                                aqi: forecastAqiHour4,
                              ),
                            ],
                          ),
                        )
                      else
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Waiting for forecast data...',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ============================================
            // ENVIRONMENT
            // ============================================
            groupedCard(
              title: 'Environment',
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Center(
                          child: groupedSensorColumn(
                            'Temperature',
                            '${temperature.toStringAsFixed(1)} °C',
                            Icons.thermostat,
                            const Color(0xFFFF6B4A),
                          ),
                        ),
                      ),

                      const VerticalDivider(),

                      Expanded(
                        child: Center(
                          child: groupedSensorColumn(
                            'Humidity',
                            '${humidity.toStringAsFixed(1)} %',
                            Icons.water_drop,
                            const Color(0xFF42A5F5),
                          ),
                        ),
                      ),

                      const VerticalDivider(),

                      Expanded(
                        child: Center(
                          child: groupedSensorColumn(
                            'Pressure',
                            '${pressure.toStringAsFixed(1)} hPa',
                            Icons.speed,
                            const Color(0xFF26A69A),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ============================================
            // AIR QUALITY PARAMETERS
            // ============================================
            groupedCard(
              title: 'Air Quality Parameters',

              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AqiDetailsPage(),
                  ),
                );
              },

              children: [
                groupedSensorStatusRow(
                  'PM1.0',
                  '$pm1 µg/m³',
                  getPm1Status(),
                  Icons.air,
                  const Color(0xFF2196F3),
                ),

                const Divider(),

                groupedSensorStatusRow(
                  'PM2.5',
                  '$pm25 µg/m³',
                  getPm25Status(),
                  Icons.air,
                  const Color(0xFF2196F3),
                ),

                const Divider(),

                groupedSensorStatusRow(
                  'PM10',
                  '$pm10 µg/m³',
                  getPm10Status(),
                  Icons.air,
                  const Color(0xFF2196F3),
                ),

                const Divider(),

                groupedSensorStatusRow(
                  'CO',
                  '$co ADC',
                  getBaselineStatus(co.toDouble(), coBaseline),
                  Icons.cloud,
                  const Color(0xFFFF9800),
                ),

                const Divider(),

                groupedSensorStatusRow(
                  'O₃',
                  '$o3 ADC',
                  getBaselineStatus(o3.toDouble(), o3Baseline),
                  Icons.cloud,
                  const Color(0xFF9C27B0),
                ),
              ],
            ),

            const SizedBox(height: 12),
            // ============================================
            // AI RECOMMENDATION
            // ============================================
            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.psychology_outlined),

                        SizedBox(width: 8),

                        Text(
                          'Recommendation',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    Text(
                      aiRecommendation,
                      textAlign: TextAlign.justify,
                      style: const TextStyle(fontSize: 16, height: 1.4),
                    ),

                    if (recommendationStatus.isNotEmpty) ...[
                      const SizedBox(height: 12),

                      Text(
                        'Based on current air quality: $recommendationStatus',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      const HistoryPage(),

      const NotificationPage(),

      const UserPage(),
    ];

    return Scaffold(
      appBar: currentIndex == 0 ? AppBar(title: Text(widget.title)) : null,

      body: currentIndex == 0
          ? pages[currentIndex]
          : SafeArea(child: pages[currentIndex]),

      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              currentIndex: currentIndex,
              backgroundColor: Colors.white,
              selectedItemColor: const Color(0xFF3977B8),
              unselectedItemColor: Colors.grey,
              elevation: 0,

              onTap: (index) {
                setState(() {
                  currentIndex = index;
                });
              },

              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.dashboard),
                  label: 'Dashboard',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.show_chart),
                  label: 'History',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.notifications),
                  label: 'Alerts',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline),
                  label: 'Profile',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
