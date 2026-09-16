import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  final DatabaseReference notificationRef = FirebaseDatabase.instance.ref(
    'notifications',
  );

  List<Map<String, dynamic>> notificationsList = [];

  @override
  void initState() {
    super.initState();
    loadNotifications();
  }

  void loadNotifications() {
    notificationRef.onValue.listen((DatabaseEvent event) {
      final data = event.snapshot.value;

      if (data == null) {
        if (!mounted) return;

        setState(() {
          notificationsList = [];
        });

        return;
      }

      final notificationData = Map<dynamic, dynamic>.from(data as Map);

      List<Map<String, dynamic>> tempList = [];

      for (final entry in notificationData.entries) {
        final notification = Map<dynamic, dynamic>.from(entry.value as Map);

        tempList.add({
          'id': entry.key.toString(),

          'title': notification['title']?.toString() ?? 'Alert',

          'message': notification['message']?.toString() ?? '',

          'timestamp': int.tryParse(notification['timestamp'].toString()) ?? 0,
        });
      }

      // Newest alert first
      tempList.sort(
        (a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int),
      );

      if (!mounted) return;

      setState(() {
        notificationsList = tempList;
      });
    });
  }

  String formatTime(int timestamp) {
    if (timestamp == 0) {
      return '';
    }

    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);

    final day = dateTime.day.toString().padLeft(2, '0');

    final month = dateTime.month.toString().padLeft(2, '0');

    final year = dateTime.year;

    final hour = dateTime.hour.toString().padLeft(2, '0');

    final minute = dateTime.minute.toString().padLeft(2, '0');

    return '$day/$month/$year  $hour:$minute';
  }

  Future<void> clearAllNotifications() async {
    await notificationRef.remove();
  }

  Future<void> deleteNotification(String id) async {
    await notificationRef.child(id).remove();
  }

  Future<void> showClearAllDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Clear all alerts?'),

          content: const Text(
            'This will permanently remove all saved alert messages.',
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),

            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Clear'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await clearAllNotifications();
    }
  }

  Future<void> showDeleteDialog(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete alert?'),

          content: const Text('Do you want to remove this alert?'),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),

            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await deleteNotification(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,

        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,

            children: [
              const Text(
                'Alerts',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),

              IconButton(
                tooltip: 'Clear all alerts',
                icon: const Icon(Icons.delete_sweep_outlined),

                onPressed: notificationsList.isEmpty
                    ? null
                    : showClearAllDialog,
              ),
            ],
          ),

          const SizedBox(height: 12),

          Expanded(
            child: notificationsList.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,

                      children: [
                        Icon(
                          Icons.notifications_none,
                          size: 60,
                          color: Colors.grey,
                        ),

                        SizedBox(height: 12),

                        Text(
                          'No alerts yet',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        SizedBox(height: 5),

                        Text(
                          'Air quality alerts will appear here.',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: notificationsList.length,

                    itemBuilder: (context, index) {
                      final notification = notificationsList[index];

                      return Card(
                        elevation: 3,

                        margin: const EdgeInsets.only(bottom: 12),

                        child: Padding(
                          padding: const EdgeInsets.all(16),

                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,

                            children: [
                              const Icon(Icons.warning_amber_rounded, size: 30),

                              const SizedBox(width: 12),

                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,

                                  children: [
                                    Text(
                                      notification['title'],
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),

                                    const SizedBox(height: 6),

                                    Text(
                                      notification['message'],
                                      style: const TextStyle(fontSize: 14),
                                    ),

                                    const SizedBox(height: 8),

                                    Text(
                                      formatTime(notification['timestamp']),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              IconButton(
                                tooltip: 'Delete alert',

                                icon: const Icon(Icons.delete_outline),

                                onPressed: () {
                                  showDeleteDialog(notification['id']);
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
