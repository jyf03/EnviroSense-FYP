import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final DatabaseReference historyRef = FirebaseDatabase.instance.ref('history');

  List<Map<dynamic, dynamic>> allHistoryRecords = [];

  List<FlSpot> temperatureSpots = [];
  List<FlSpot> humiditySpots = [];
  List<FlSpot> pm25Spots = [];
  List<FlSpot> coSpots = [];
  List<FlSpot> o3Spots = [];

  String selectedRange = '6 Hours';

  @override
  void initState() {
    super.initState();
    loadHistory();
  }

  // =========================================================
  // LOAD FIREBASE HISTORY
  // =========================================================

  void loadHistory() {
    historyRef.onValue.listen((DatabaseEvent event) {
      final data = event.snapshot.value;

      if (data == null) {
        return;
      }

      final historyData = Map<dynamic, dynamic>.from(data as Map);

      final entries = historyData.entries.toList();

      // Sort oldest -> newest
      entries.sort((a, b) {
        final aKey = int.tryParse(a.key.toString()) ?? 0;

        final bKey = int.tryParse(b.key.toString()) ?? 0;

        return aKey.compareTo(bKey);
      });

      final records = <Map<dynamic, dynamic>>[];

      for (final entry in entries) {
        final record = Map<dynamic, dynamic>.from(entry.value as Map);

        final timestamp = int.tryParse(record['timestamp'].toString()) ?? 0;

        // Ignore invalid old records
        if (timestamp == 0) {
          continue;
        }

        records.add(record);
      }

      allHistoryRecords = records;

      filterHistory();
    });
  }

  // =========================================================
  // FILTER HISTORY BY SELECTED RANGE
  // =========================================================

  void filterHistory() {
    final currentTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final temperatureList = <FlSpot>[];
    final humidityList = <FlSpot>[];
    final pm25List = <FlSpot>[];
    final coList = <FlSpot>[];
    final o3List = <FlSpot>[];

    for (final record in allHistoryRecords) {
      final timestamp = int.tryParse(record['timestamp'].toString()) ?? 0;

      bool includeRecord = true;

      if (selectedRange == '6 Hours') {
        includeRecord = timestamp >= currentTimestamp - (6 * 3600);
      } else if (selectedRange == '12 Hours') {
        includeRecord = timestamp >= currentTimestamp - (12 * 3600);
      } else if (selectedRange == '24 Hours') {
        includeRecord = timestamp >= currentTimestamp - (24 * 3600);
      }

      if (!includeRecord) {
        continue;
      }

      final temperature =
          double.tryParse(record['temperature'].toString()) ?? 0;

      final humidity = double.tryParse(record['humidity'].toString()) ?? 0;

      final pm25 = double.tryParse(record['pm25'].toString()) ?? 0;

      final co = double.tryParse(record['co_adc'].toString()) ?? 0;

      final o3 = double.tryParse(record['o3_adc'].toString()) ?? 0;

      // Use the REAL timestamp as x-axis value
      final xValue = timestamp.toDouble();

      temperatureList.add(FlSpot(xValue, temperature));

      humidityList.add(FlSpot(xValue, humidity));

      pm25List.add(FlSpot(xValue, pm25));

      coList.add(FlSpot(xValue, co));

      o3List.add(FlSpot(xValue, o3));
    }

    if (!mounted) {
      return;
    }

    setState(() {
      temperatureSpots = temperatureList;
      humiditySpots = humidityList;
      pm25Spots = pm25List;
      coSpots = coList;
      o3Spots = o3List;
    });
  }

  // =========================================================
  // X-AXIS RANGE + INTERVAL
  // =========================================================

  double getMinX(List<FlSpot> spots) {
    final now = DateTime.now().millisecondsSinceEpoch / 1000;

    if (selectedRange == '6 Hours') {
      return now - (6 * 3600);
    }

    if (selectedRange == '12 Hours') {
      return now - (12 * 3600);
    }

    if (selectedRange == '24 Hours') {
      return now - (24 * 3600);
    }

    if (spots.isNotEmpty) {
      return spots.first.x;
    }

    return now - (24 * 3600);
  }

  double getMaxX(List<FlSpot> spots) {
    final now = DateTime.now().millisecondsSinceEpoch / 1000;

    if (selectedRange == 'All' && spots.isNotEmpty) {
      return spots.last.x;
    }

    return now;
  }

  double getTimeInterval(List<FlSpot> spots) {
    if (selectedRange == '6 Hours') {
      return 2 * 3600; // 3-4 labels
    }

    if (selectedRange == '12 Hours') {
      return 4 * 3600;
    }

    if (selectedRange == '24 Hours') {
      return 6 * 3600;
    }

    if (spots.length >= 2) {
      final range = spots.last.x - spots.first.x;

      if (range > 0) {
        return range / 4;
      }
    }

    return 3600;
  }

  // =========================================================
  // DATE / TIME FORMAT
  // =========================================================

  String formatDate(double timestamp) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(
      timestamp.toInt() * 1000,
    );

    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');

    return '$day/$month/${dateTime.year}';
  }

  Widget bottomTitleWidgets(double value, TitleMeta meta) {
    final timestamp = value.toInt();

    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);

    int hour = dateTime.hour;
    final period = hour >= 12 ? 'PM' : 'AM';

    hour = hour % 12;

    if (hour == 0) {
      hour = 12;
    }

    return SideTitleWidget(
      meta: meta,
      child: Text(
        '$hour$period',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 9),
      ),
    );
  }

  // =========================================================
  // HISTORY CHART
  // =========================================================

  Widget historyChart({
    required String title,
    required String description,
    required String unit,
    required List<FlSpot> spots,
  }) {
    final minX = getMinX(spots);
    final maxX = getMaxX(spots);

    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 5),

            Text(description, style: const TextStyle(fontSize: 13)),

            const SizedBox(height: 20),

            SizedBox(
              height: 280,
              child: spots.isEmpty
                  ? const Center(child: Text('No history data available'))
                  : LineChart(
                      LineChartData(
                        minX: minX,
                        maxX: maxX,

                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: true,
                          verticalInterval: getTimeInterval(spots),
                        ),

                        borderData: FlBorderData(show: true),

                        lineTouchData: LineTouchData(
                          enabled: true,
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipItems: (touchedSpots) {
                              return touchedSpots.map((spot) {
                                final dateTime =
                                    DateTime.fromMillisecondsSinceEpoch(
                                      spot.x.toInt() * 1000,
                                    );

                                final hour = dateTime.hour.toString().padLeft(
                                  2,
                                  '0',
                                );

                                final minute = dateTime.minute
                                    .toString()
                                    .padLeft(2, '0');

                                return LineTooltipItem(
                                  '$hour:$minute\n'
                                  '${spot.y.toStringAsFixed(1)} $unit',
                                  const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                );
                              }).toList();
                            },
                          ),
                        ),

                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),

                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),

                          leftTitles: AxisTitles(
                            axisNameWidget: Text(unit),
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 50,
                              getTitlesWidget: (value, meta) {
                                return SideTitleWidget(
                                  meta: meta,
                                  child: Text(
                                    value.toStringAsFixed(1),
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                );
                              },
                            ),
                          ),

                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 35,
                              interval: getTimeInterval(spots),
                              getTitlesWidget: bottomTitleWidgets,
                            ),
                          ),
                        ),

                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            curveSmoothness: 0.25,
                            barWidth: 3,
                            dotData: const FlDotData(show: true),
                            belowBarData: BarAreaData(show: true),
                            color: Colors.cyan,
                          ),
                        ],
                      ),
                    ),
            ),

            if (spots.isNotEmpty) ...[
              const SizedBox(height: 6),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(formatDate(minX), style: const TextStyle(fontSize: 11)),

                  const Text(
                    'Time',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),

                  Text(formatDate(maxX), style: const TextStyle(fontSize: 11)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // =========================================================
  // PAGE
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'History',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 12),

          LayoutBuilder(
            builder: (context, constraints) {
              return DropdownMenu<String>(
                width: constraints.maxWidth,

                initialSelection: selectedRange,

                label: const Text('Time Range'),

                leadingIcon: const Icon(
                  Icons.access_time,
                  size: 20,
                ),

                trailingIcon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                ),

                selectedTrailingIcon: const Icon(
                  Icons.keyboard_arrow_up_rounded,
                ),

                inputDecorationTheme: InputDecorationTheme(
                  filled: true,
                  fillColor: const Color(0xFFF8F3FB),

                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),

                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),

                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: Colors.deepPurple,
                      width: 1.2,
                    ),
                  ),

                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: Colors.deepPurple,
                      width: 2,
                    ),
                  ),
                ),

                menuStyle: MenuStyle(
                  minimumSize: WidgetStatePropertyAll(
                    Size(constraints.maxWidth, 0),
                  ),

                  maximumSize: WidgetStatePropertyAll(
                    Size(constraints.maxWidth, 260),
                  ),

                  backgroundColor: const WidgetStatePropertyAll(
                    Color(0xFFF8F3FB),
                  ),

                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),

                  elevation: const WidgetStatePropertyAll(6),
                ),

                dropdownMenuEntries: const [
                  DropdownMenuEntry(
                    value: '6 Hours',
                    label: 'Last 6 Hours',
                  ),

                  DropdownMenuEntry(
                    value: '12 Hours',
                    label: 'Last 12 Hours',
                  ),

                  DropdownMenuEntry(
                    value: '24 Hours',
                    label: 'Last 24 Hours',
                  ),

                  DropdownMenuEntry(
                    value: 'All',
                    label: 'All History',
                  ),
                ],

                onSelected: (value) {
                  if (value == null) return;

                  selectedRange = value;
                  filterHistory();
                },
              );
            },
          ),

          const SizedBox(height: 6),

          const SizedBox(height: 6),

          const SizedBox(height: 20),

          historyChart(
            title: 'Temperature History',
            description: 'Temperature variation over time',
            unit: '°C',
            spots: temperatureSpots,
          ),

          historyChart(
            title: 'Humidity History',
            description: 'Relative humidity over time',
            unit: '%',
            spots: humiditySpots,
          ),

          historyChart(
            title: 'PM2.5 History',
            description: 'PM2.5 concentration over time',
            unit: 'µg/m³',
            spots: pm25Spots,
          ),

          historyChart(
            title: 'CO History',
            description: 'Carbon monoxide sensor reading over time',
            unit: 'ADC',
            spots: coSpots,
          ),

          historyChart(
            title: 'O₃ History',
            description: 'Ozone sensor reading over time',
            unit: 'ADC',
            spots: o3Spots,
          ),
        ],
      ),
    );
  }
}
