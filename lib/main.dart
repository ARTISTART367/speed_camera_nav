import 'dart:async';
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
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
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
  // Map State
  GoogleMapController? _mapController;
  Position? _currentPosition;
  final Set<Marker> _markers = {};

  // App Logic State
  int _currentSpeed = 0;
  final int _safeLimit = 100;
  final List<Map<String, dynamic>> _communityReports = [];
  final List<String> _notifications = [];

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
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Destination'),
        ),
      );
    });
  }

  void _addReport(String type) async {
    String reportEntry = "$type reported nearby";

    setState(() {
      _communityReports.insert(0, {"text": reportEntry, "time": "Just now"});
      _notifications.add("$type detected on your route!");
    });

    // Remove notification after 4 seconds (Auto-fade)
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _notifications.isNotEmpty) {
        setState(() => _notifications.removeAt(0));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // Simulated Speed Input for testing
          Container(
            margin: const EdgeInsets.only(right: 10, top: 10),
            width: 70,
            height: 40,
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(8)),
            child: TextField(
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                  hintText: 'km/h', border: InputBorder.none),
              onChanged: (val) =>
                  setState(() => _currentSpeed = int.tryParse(val) ?? 0),
            ),
          )
        ],
      ),
      drawer: Drawer(
        child: ListView(
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.blue),
              child: Text('Menu',
                  style: TextStyle(color: Colors.white, fontSize: 24)),
            ),
            ListTile(
              leading: const Icon(Icons.people),
              title: const Text('Community Reports'),
              onTap: () {
                Navigator.pop(context);
                _showCommunityDialog();
              },
            ),
            const ListTile(
                leading: Icon(Icons.settings), title: Text('Settings')),
          ],
        ),
      ),
      body: Stack(
        children: [
          // 1. THE MAP BACKGROUND
          _currentPosition == null
              ? const Center(child: CircularProgressIndicator())
              : GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(_currentPosition!.latitude,
                        _currentPosition!.longitude),
                    zoom: 15,
                  ),
                  markers: _markers,
                  myLocationEnabled: true,
                  onTap: _onMapTapped,
                  onMapCreated: (controller) => _mapController = controller,
                ),

          // 2. RED NOTIFICATIONS (Top Right)
          Positioned(
            top: 100,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _notifications
                  .map((n) => LiveNotification(message: n))
                  .toList(),
            ),
          ),

          // 3. SPEED GAUGE (Bottom Left)
          Positioned(
            bottom: 30,
            left: 16,
            child: SpeedGauge(speed: _currentSpeed, limit: _safeLimit),
          ),

          // 4. EXPANDABLE REPORT BUTTON (Bottom Right)
          Positioned(
            bottom: 30,
            right: 16,
            child: ExpandableReportButton(onReport: _addReport),
          ),
        ],
      ),
    );
  }

  void _showCommunityDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Community Updates"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _communityReports.length,
            itemBuilder: (context, i) => ListTile(
              title: Text(_communityReports[i]['text']),
              subtitle: Text(_communityReports[i]['time']),
            ),
          ),
        ),
      ),
    );
  }
}

//////////////////////////////////////////////////////////
/// CUSTOM COMPONENTS
//////////////////////////////////////////////////////////

class SpeedGauge extends StatefulWidget {
  final int speed;
  final int limit;
  const SpeedGauge({super.key, required this.speed, required this.limit});

  @override
  State<SpeedGauge> createState() => _SpeedGaugeState();
}

class _SpeedGaugeState extends State<SpeedGauge>
    with SingleTickerProviderStateMixin {
  late AnimationController _blinkController;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  Color get _gaugeColor {
    if (widget.speed > widget.limit + 40) return Colors.red;
    if (widget.speed > widget.limit) return Colors.red;
    if (widget.speed > widget.limit - 20) return Colors.yellow;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    bool isDanger = widget.speed > (widget.limit + 40);
    return AnimatedBuilder(
      animation: _blinkController,
      builder: (context, child) {
        return Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (isDanger && _blinkController.value > 0.5)
                ? Colors.black
                : _gaugeColor,
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black26)],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${widget.speed}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 24)),
              const Divider(
                  color: Colors.white, height: 4, indent: 20, endIndent: 20),
              Text('LIMIT ${widget.limit}',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        );
      },
    );
  }
}

class LiveNotification extends StatelessWidget {
  final String message;
  const LiveNotification({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.85),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
      ),
      child: Text(
        message,
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );
  }
}

class ExpandableReportButton extends StatefulWidget {
  final Function(String) onReport;
  const ExpandableReportButton({super.key, required this.onReport});

  @override
  State<ExpandableReportButton> createState() => _ExpandableReportButtonState();
}

class _ExpandableReportButtonState extends State<ExpandableReportButton> {
  bool _isOpen = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isOpen) ...[
          _reportIcon(Icons.camera_alt, "Speed Camera", Colors.red),
          _reportIcon(Icons.car_crash, "Accident", Colors.orange),
          _reportIcon(Icons.traffic, "Traffic Jam", Colors.amber),
        ],
        FloatingActionButton(
          backgroundColor: Colors.blue,
          child: Icon(_isOpen ? Icons.close : Icons.report),
          onPressed: () => setState(() => _isOpen = !_isOpen),
        ),
      ],
    );
  }

  Widget _reportIcon(IconData icon, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FloatingActionButton.small(
        backgroundColor: color,
        onPressed: () {
          widget.onReport(label);
          setState(() => _isOpen = false);
        },
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}
