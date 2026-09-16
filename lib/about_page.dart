import 'package:flutter/material.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: const Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Environmental Monitoring System',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),

            SizedBox(height: 12),

            Text(
              'This application monitors environmental conditions in real time using IoT sensors and Firebase.',
            ),

            SizedBox(height: 12),

            Text('Sensors: BME280, PMS5003, MQ-7 and MQ-131.'),

            SizedBox(height: 12),

            Text('Version 1.0'),
          ],
        ),
      ),
    );
  }
}
