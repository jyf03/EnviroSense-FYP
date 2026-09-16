import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  final DatabaseReference settingsRef = FirebaseDatabase.instance.ref(
    'users/currentUser/notificationSettings',
  );

  bool airQualityAlerts = true;
  bool badOnly = true;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadSettings();
  }

  void loadSettings() {
    settingsRef.onValue.listen((DatabaseEvent event) {
      final data = event.snapshot.value;

      if (data != null) {
        final settings = Map<String, dynamic>.from(data as Map);

        if (!mounted) return;

        setState(() {
          airQualityAlerts = settings['airQualityAlerts'] ?? true;

          badOnly = settings['badOnly'] ?? true;

          isLoading = false;
        });
      } else {
        saveSettings();
        setState(() {
          isLoading = false;
        });
      }
    });
  }

  Future<void> saveSettings() async {
    await settingsRef.set({
      'airQualityAlerts': airQualityAlerts,
      'badOnly': badOnly,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notification Settings')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                SwitchListTile(
                  title: const Text('Air Quality Alerts'),
                  subtitle: const Text(
                    'Enable or disable air quality notifications.',
                  ),
                  value: airQualityAlerts,
                  onChanged: (value) async {
                    setState(() {
                      airQualityAlerts = value;
                    });

                    await saveSettings();
                  },
                ),

                SwitchListTile(
                  title: const Text('Bad Air Quality Only'),
                  subtitle: const Text(
                    'Only notify when the air quality status is Bad.',
                  ),
                  value: badOnly,
                  onChanged: airQualityAlerts
                      ? (value) async {
                          setState(() {
                            badOnly = value;
                          });

                          await saveSettings();
                        }
                      : null,
                ),
              ],
            ),
    );
  }
}
