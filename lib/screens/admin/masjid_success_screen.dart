import 'package:flutter/material.dart';
import 'masjid_time_settings_screen.dart';

class MasjidSuccessScreen extends StatelessWidget {
  final String ownerMobile;

  const MasjidSuccessScreen({super.key, required this.ownerMobile});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Success")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 100),
              const SizedBox(height: 20),
              const Text(
                "Your masjid is registered successfully",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () {
                  // Navigate to time settings screen so the admin can set timings immediately
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          MasjidTimeSettingsScreen(ownerMobile: ownerMobile),
                    ),
                  );
                },
                child: const Text("Set Prayer Times"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
