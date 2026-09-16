import 'package:flutter/material.dart';

class AqiDetailsPage extends StatelessWidget {
  const AqiDetailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Air Quality Parameters'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Card(
            child: ListTile(
              leading: Icon(Icons.air),
              title: Text('PM1.0'),
              subtitle: Text(
                'Fine particulate matter with a diameter of 1 micrometre or smaller. These particles can penetrate deep into lung tissue and pass directly into the bloodstream, potentially causing systematic health effects.',
              ),
            ),
          ),

          Card(
            child: ListTile(
              leading: Icon(Icons.air),
              title: Text('PM2.5'),
              subtitle: Text(
                'Fine particulate matter with a diameter of 2.5 micrometres or smaller. These particles can remain suspended in the air and may affect air quality. It reduces the visibility and causes respiratory problems.',
              ),
            ),
          ),

          Card(
            child: ListTile(
              leading: Icon(Icons.air),
              title: Text('PM10'),
              subtitle: Text(
                'Particulate matter with a diameter of 10 micrometres or smaller. Exposure can cause eye and throat irritation, coughing or breathing difficulties, and the aggravation of asthma.',
              ),
            ),
          ),

          Card(
            child: ListTile(
              leading: Icon(Icons.cloud),
              title: Text('CO'),
              subtitle: Text(
                'Carbon monoxide is a colourless and odorless gas. Inhaling large amount can cause headaches, nausea, dizziness, and vomiting. Repeated, long-term exposure can lead to heart disease.',
              ),
            ),
          ),

          Card(
            child: ListTile(
              leading: Icon(Icons.cloud),
              title: Text('O₃'),
              subtitle: Text(
                'Ground-level ozone can aggravate existing respiratory conditions and also cause throat irritation, headaches, and chest pain.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}