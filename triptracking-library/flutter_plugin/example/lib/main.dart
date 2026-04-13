import 'dart:async';
import 'package:flutter/material.dart';
import 'package:triptracking/triptracker.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TripTracker Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const TripTrackerPage(),
    );
  }
}

class TripTrackerPage extends StatefulWidget {
  const TripTrackerPage({super.key});

  @override
  State<TripTrackerPage> createState() => _TripTrackerPageState();
}

class _TripTrackerPageState extends State<TripTrackerPage> {
  TrackingStatus? _status;
  TripTrackerSettings? _settings;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refreshStatus());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    await _refreshStatus();
    await _refreshSettings();
  }

  Future<void> _refreshStatus() async {
    final status = await TripTracker.getTrackingStatus();
    if (mounted) setState(() => _status = status);
  }

  Future<void> _refreshSettings() async {
    final settings = await TripTracker.getSettings();
    if (mounted) setState(() => _settings = settings);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TripTracker'),
        backgroundColor: const Color.fromRGBO(115, 204, 242, 1),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await TripTracker.openSettings();
              _refreshSettings();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Status Card ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _status?.isTracking == true ? Icons.directions_car : Icons.hourglass_empty,
                        color: _status?.isTracking == true ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _status?.isTracking == true
                            ? 'Recording Trip #${_status!.tripId}'
                            : 'Waiting for vehicle speed',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _statColumn('${_status?.speedKmh.toStringAsFixed(0) ?? '0'}', 'km/h'),
                      _statColumn(_formatDistance(_status?.distance ?? 0), 'distance'),
                      _statColumn(_formatDuration(_status?.duration ?? 0), 'duration'),
                      _statColumn('${_status?.steps ?? 0}', 'steps'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Native Pages ──
          const Text('Native Pages', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),

          _actionTile(Icons.map, 'Main View', 'Full map + tracking UI', () async {
            await TripTracker.openMainView();
          }),
          _actionTile(Icons.settings, 'Settings', 'Thresholds, web monitor, CarPlay', () async {
            await TripTracker.openSettings();
            _refreshSettings();
          }),
          _actionTile(Icons.notifications, 'Notifications & Voice', 'Per-type toggles', () async {
            await TripTracker.openNotificationSettings();
          }),
          _actionTile(Icons.location_on, 'Geofence Zones', 'Map + zone management', () async {
            await TripTracker.openGeofenceManager();
          }),
          _actionTile(Icons.history, 'Trip History', 'View past trips', () async {
            await TripTracker.openHistory();
          }),
          _actionTile(Icons.calendar_today, 'Daily Locations', 'Day-by-day locations', () async {
            await TripTracker.openDailyLocations();
          }),

          const SizedBox(height: 16),

          // ── Quick Toggles ──
          const Text('Quick Toggles', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),

          SwitchListTile(
            title: const Text('Web Monitor'),
            subtitle: const Text('HTTP server on :8080'),
            value: _settings?.webMonitorEnabled ?? false,
            onChanged: (v) async {
              await TripTracker.updateSetting('webMonitorEnabled', v);
              _refreshSettings();
            },
          ),
          SwitchListTile(
            title: const Text('Voice Feedback'),
            subtitle: const Text('Speak trip events'),
            value: _settings?.voiceFeedbackEnabled ?? true,
            onChanged: (v) async {
              await TripTracker.updateSetting('voiceFeedbackEnabled', v);
              _refreshSettings();
            },
          ),
          SwitchListTile(
            title: const Text('Geofencing'),
            subtitle: const Text('Monitor enter/exit zones'),
            value: _settings?.geofencingEnabled ?? false,
            onChanged: (v) async {
              await TripTracker.updateSetting('geofencingEnabled', v);
              _refreshSettings();
            },
          ),

          const SizedBox(height: 16),

          // ── Logs ──
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.today),
                  label: const Text("Today's Log"),
                  onPressed: () => TripTracker.sendTodayLog(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.archive),
                  label: const Text('All Logs'),
                  onPressed: () => TripTracker.sendAllLogs(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statColumn(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _actionTile(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.blue),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
