import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const SpeedCameraApp());
}

class SpeedCameraApp extends StatelessWidget {
  const SpeedCameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Speed Camera Navigator',
      theme: ThemeData(
        useMaterial3: true,
        primarySwatch: Colors.blue,
      ),
      home: const MainHomeScreen(),
    );
  }
}

class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    NavigationScreen(),
    SpeedAlertScreen(),
    ReportScreen(),
    CommunityScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          setState(() => _currentIndex = index);
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.navigation),
            label: 'Navigate',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.speed),
            label: 'Speed',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.report),
            label: 'Report',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'Community',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

//////////////////////////////////////////////////////////
/// 1️⃣ NAVIGATION SCREEN (MAP PLACEHOLDER)
//////////////////////////////////////////////////////////
class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  GoogleMapController? _mapController;
  Position? _currentPosition;
  final Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _requestLocation();
  }

  Future<void> _requestLocation() async {
    final status = await Permission.location.request();
    if (!status.isGranted) return;

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    setState(() {
      _currentPosition = position;
      _markers.add(
        Marker(
          markerId: const MarkerId('current'),
          position: LatLng(position.latitude, position.longitude),
          infoWindow: const InfoWindow(title: 'Your Location'),
        ),
      );
    });
  }

  void _onMapTapped(LatLng position) {
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'destination');
      _markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: position,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed,
          ),
          infoWindow: const InfoWindow(title: 'Destination'),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _currentPosition == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(
                      _currentPosition!.latitude,
                      _currentPosition!.longitude,
                    ),
                    zoom: 15,
                  ),
                  markers: _markers,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  onTap: _onMapTapped,
                  onMapCreated: (controller) {
                    _mapController = controller;
                  },
                ),

                // Top instruction panel (tap-through enabled)
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: IgnorePointer(
                    child: Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Tap on map to select destination',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ),

                // Waze-style alert buttons
                Positioned(
                  bottom: 20,
                  right: 16,
                  child: Column(
                    children: [
                      FloatingActionButton(
                        heroTag: 'speedCam',
                        backgroundColor: Colors.red,
                        onPressed: () {},
                        child: const Icon(Icons.camera_alt),
                      ),
                      const SizedBox(height: 12),
                      FloatingActionButton(
                        heroTag: 'hazard',
                        backgroundColor: Colors.orange,
                        onPressed: () {},
                        child: const Icon(Icons.warning),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

//////////////////////////////////////////////////////////
/// 2️⃣ SPEED & ALERTS SCREEN
//////////////////////////////////////////////////////////
class SpeedAlertScreen extends StatelessWidget {
  const SpeedAlertScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Speed & Alerts')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _infoCard(
              icon: Icons.speed,
              title: 'Current Speed',
              subtitle: '--- km/h',
            ),
            _infoCard(
              icon: Icons.traffic,
              title: 'Speed Limit',
              subtitle: '-- km/h',
            ),
            _infoCard(
              icon: Icons.notifications_active,
              title: 'Active Alerts',
              subtitle: 'No alerts',
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, size: 32),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }
}

//////////////////////////////////////////////////////////
/// 3️⃣ REPORT INCIDENT SCREEN
//////////////////////////////////////////////////////////
class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report Incident')),
      body: GridView.count(
        padding: const EdgeInsets.all(16),
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        children: const [
          ReportTile(icon: Icons.camera_alt, label: 'Speed Camera'),
          ReportTile(icon: Icons.car_crash, label: 'Accident'),
          ReportTile(icon: Icons.traffic, label: 'Traffic Jam'),
          ReportTile(icon: Icons.warning, label: 'Road Hazard'),
        ],
      ),
    );
  }
}

class ReportTile extends StatelessWidget {
  final IconData icon;
  final String label;

  const ReportTile({
    super.key,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      child: InkWell(
        onTap: () {},
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40),
            const SizedBox(height: 10),
            Text(label),
          ],
        ),
      ),
    );
  }
}

//////////////////////////////////////////////////////////
/// 4️⃣ COMMUNITY SCREEN
//////////////////////////////////////////////////////////
class CommunityScreen extends StatelessWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Community Updates')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          ListTile(
            leading: Icon(Icons.person),
            title: Text('User reported a speed camera'),
            subtitle: Text('2 minutes ago'),
          ),
          ListTile(
            leading: Icon(Icons.person),
            title: Text('Accident ahead'),
            subtitle: Text('5 minutes ago'),
          ),
        ],
      ),
    );
  }
}

//////////////////////////////////////////////////////////
/// 5️⃣ SETTINGS SCREEN
//////////////////////////////////////////////////////////
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: const [
          ListTile(
            leading: Icon(Icons.volume_up),
            title: Text('Audio Alerts'),
          ),
          ListTile(
            leading: Icon(Icons.map),
            title: Text('Map Preferences'),
          ),
          ListTile(
            leading: Icon(Icons.info),
            title: Text('About App'),
          ),
        ],
      ),
    );
  }
}
