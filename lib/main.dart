import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';

// ═══════════════════════════════════════════════════════════════════════════
// VOICE ALERTS FEATURE
// ═══════════════════════════════════════════════════════════════════════════
// The app now includes text-to-speech voice announcements for:
//   1. Navigation start/stop - "Navigation started" / "Navigation stopped"
//   2. Route calculation - Announces total cameras/accidents/traffic on route
//   3. Proximity alerts - "Attention. Speed camera ahead." (within 150m)
//   4. Report confirmation - "Speed camera reported and saved."
//
// Voice settings: English (US), rate 0.5 (slower for clarity), volume 1.0
// Package required: flutter_tts (add to pubspec.yaml)
// ═══════════════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────
// CUSTOM MARKER ICON PAINTER
// Draws shaped icons to bytes so Google Maps can render them as markers.
// ─────────────────────────────────────────────

class MarkerIconPainter {
  /// Draws a camera body shape: rectangle body + small lens circle on top-left,
  /// viewfinder bump on top-centre. Returns a BitmapDescriptor.
  static Future<BitmapDescriptor> cameraIcon({
    Color bodyColor = const Color(0xFF7B1FA2),
    double size = 80,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final w = size;
    final h = size;

    // Shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(4, 6, w - 8, h * 0.65),
        const Radius.circular(10),
      ),
      shadowPaint,
    );

    // Camera body
    final bodyPaint = Paint()..color = bodyColor;
    final bodyRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(2, 4, w - 4, h * 0.62), const Radius.circular(9));
    canvas.drawRRect(bodyRect, bodyPaint);

    // Viewfinder bump (top centre)
    final bumpPaint = Paint()..color = bodyColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.33, 0, w * 0.34, 8),
        const Radius.circular(4),
      ),
      bumpPaint,
    );

    // Lens outer ring (white)
    final lensOuterPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(w / 2, h * 0.34), w * 0.23, lensOuterPaint);

    // Lens inner (dark)
    final lensInnerPaint = Paint()..color = const Color(0xFF1A1A2E);
    canvas.drawCircle(Offset(w / 2, h * 0.34), w * 0.165, lensInnerPaint);

    // Lens shine
    final shinePaint = Paint()..color = Colors.white.withOpacity(0.45);
    canvas.drawCircle(Offset(w / 2 - w * 0.07, h * 0.26), w * 0.06, shinePaint);

    // Flash dot (top-left corner of body)
    final flashPaint = Paint()..color = Colors.white.withOpacity(0.8);
    canvas.drawCircle(Offset(w * 0.18, h * 0.15), w * 0.065, flashPaint);

    // Triangle pointer at bottom centre
    final triPaint = Paint()..color = bodyColor;
    final triPath = Path()
      ..moveTo(w / 2 - 8, h * 0.66)
      ..lineTo(w / 2 + 8, h * 0.66)
      ..lineTo(w / 2, h * 0.82)
      ..close();
    canvas.drawPath(triPath, triPaint);

    final picture = recorder.endRecording();
    final img = await picture.toImage(w.toInt(), (h * 0.85).toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    return BitmapDescriptor.fromBytes(bytes);
  }

  /// Warning triangle icon for accidents.
  static Future<BitmapDescriptor> warningIcon({
    Color color = const Color(0xFFE65100),
    double size = 80,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final w = size;
    final h = size;

    // Shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3);
    final shadowPath = Path()
      ..moveTo(w / 2, 6)
      ..lineTo(w - 4, h * 0.72)
      ..lineTo(4, h * 0.72)
      ..close();
    canvas.drawPath(shadowPath, shadowPaint);

    // Triangle body
    final bodyPaint = Paint()..color = color;
    final triPath = Path()
      ..moveTo(w / 2, 4)
      ..lineTo(w - 4, h * 0.68)
      ..lineTo(4, h * 0.68)
      ..close();
    canvas.drawPath(triPath, bodyPaint);

    // White border inside
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final borderPath = Path()
      ..moveTo(w / 2, 12)
      ..lineTo(w - 12, h * 0.62)
      ..lineTo(12, h * 0.62)
      ..close();
    canvas.drawPath(borderPath, borderPaint);

    // Exclamation mark
    final textPainter = TextPainter(
      text: TextSpan(
        text: '!',
        style: TextStyle(
          color: Colors.white,
          fontSize: w * 0.35,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, Offset(w / 2 - textPainter.width / 2, h * 0.25));

    // Triangle pointer bottom
    final triPointer = Paint()..color = color;
    final ptr = Path()
      ..moveTo(w / 2 - 8, h * 0.68)
      ..lineTo(w / 2 + 8, h * 0.68)
      ..lineTo(w / 2, h * 0.84)
      ..close();
    canvas.drawPath(ptr, triPointer);

    final picture = recorder.endRecording();
    final img = await picture.toImage(w.toInt(), (h * 0.88).toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    return BitmapDescriptor.fromBytes(bytes);
  }

  /// Traffic light icon for traffic jams.
  static Future<BitmapDescriptor> trafficIcon({
    double size = 80,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final w = size;
    final h = size;

    // Shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.28, 5, w * 0.44, h * 0.65),
          const Radius.circular(8)),
      shadowPaint,
    );

    // Traffic light body
    final bodyPaint = Paint()..color = const Color(0xFF212121);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.26, 3, w * 0.48, h * 0.62),
          const Radius.circular(8)),
      bodyPaint,
    );

    // Red light
    canvas.drawCircle(
        Offset(w / 2, h * 0.14), w * 0.1, Paint()..color = Colors.red);
    // Amber light
    canvas.drawCircle(
        Offset(w / 2, h * 0.32), w * 0.1, Paint()..color = Colors.amber);
    // Green light (brightest — traffic jam just started)
    canvas.drawCircle(Offset(w / 2, h * 0.5), w * 0.1,
        Paint()..color = const Color(0xFF66BB6A));

    // Pole
    final polePaint = Paint()..color = const Color(0xFF424242);
    canvas.drawRect(Rect.fromLTWH(w / 2 - 3, h * 0.64, 6, h * 0.18), polePaint);

    // Base
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.28, h * 0.8, w * 0.44, h * 0.06),
          const Radius.circular(3)),
      polePaint,
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(w.toInt(), (h * 0.9).toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    return BitmapDescriptor.fromBytes(bytes);
  }
}

void main() {
  runApp(const SpeedCameraApp());
}

class SpeedCameraApp extends StatelessWidget {
  const SpeedCameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Navigation App',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const MainHomeScreen(),
    );
  }
}

// ─────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────

/// Persistence strategy:
///   - SpeedCamera  → permanent (SharedPreferences key: 'speed_cameras')
///   - Accident     → temporary, 2-hour TTL (key: 'temp_reports')
///   - Traffic Jam  → temporary, 2-hour TTL (key: 'temp_reports')
class ReportedLocation {
  final String id;
  final String type; // 'Speed Camera' | 'Accident' | 'Traffic Jam'
  final double lat;
  final double lng;
  final DateTime reportedAt;
  final bool isPermanent; // true only for Speed Camera

  ReportedLocation({
    required this.id,
    required this.type,
    required this.lat,
    required this.lng,
    required this.reportedAt,
    required this.isPermanent,
  });

  bool get isExpired {
    if (isPermanent) return false;
    return DateTime.now().difference(reportedAt).inHours >= 2;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'lat': lat,
        'lng': lng,
        'reportedAt': reportedAt.toIso8601String(),
        'isPermanent': isPermanent,
      };

  factory ReportedLocation.fromJson(Map<String, dynamic> json) =>
      ReportedLocation(
        id: json['id'],
        type: json['type'],
        lat: json['lat'],
        lng: json['lng'],
        reportedAt: DateTime.parse(json['reportedAt']),
        isPermanent: json['isPermanent'] ?? false,
      );

  LatLng get latLng => LatLng(lat, lng);
}

// ─────────────────────────────────────────────
// REPORT DATABASE SERVICE
// ─────────────────────────────────────────────

class ReportDatabase {
  static const String _permanentKey = 'speed_cameras';
  static const String _tempKey = 'temp_reports';

  /// Load all non-expired reports from storage.
  static Future<List<ReportedLocation>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final List<ReportedLocation> all = [];

    // Load permanent speed cameras
    final String? permanentJson = prefs.getString(_permanentKey);
    if (permanentJson != null) {
      final List<dynamic> decoded = json.decode(permanentJson);
      all.addAll(decoded.map((e) => ReportedLocation.fromJson(e)));
    }

    // Load temporary reports (and purge expired ones)
    final String? tempJson = prefs.getString(_tempKey);
    if (tempJson != null) {
      final List<dynamic> decoded = json.decode(tempJson);
      final List<ReportedLocation> tempReports =
          decoded.map((e) => ReportedLocation.fromJson(e)).toList();

      // Filter out expired
      final active = tempReports.where((r) => !r.isExpired).toList();

      // If we pruned any, save the cleaned list back
      if (active.length != tempReports.length) {
        await prefs.setString(
            _tempKey, json.encode(active.map((e) => e.toJson()).toList()));
      }

      all.addAll(active);
    }

    return all;
  }

  /// Save a new report. Permanent reports go to their own bucket; temp to theirs.
  static Future<void> save(ReportedLocation report) async {
    final prefs = await SharedPreferences.getInstance();

    if (report.isPermanent) {
      final String? existing = prefs.getString(_permanentKey);
      final List<dynamic> decoded =
          existing != null ? json.decode(existing) : [];
      final List<ReportedLocation> list =
          decoded.map((e) => ReportedLocation.fromJson(e)).toList();
      list.add(report);
      await prefs.setString(
          _permanentKey, json.encode(list.map((e) => e.toJson()).toList()));
    } else {
      final String? existing = prefs.getString(_tempKey);
      final List<dynamic> decoded =
          existing != null ? json.decode(existing) : [];
      final List<ReportedLocation> list = decoded
          .map((e) => ReportedLocation.fromJson(e))
          .where((r) => !r.isExpired)
          .toList();
      list.add(report);
      await prefs.setString(
          _tempKey, json.encode(list.map((e) => e.toJson()).toList()));
    }
  }

  /// Delete a permanent speed camera by id.
  static Future<void> deletePermanent(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final String? existing = prefs.getString(_permanentKey);
    if (existing == null) return;
    final List<dynamic> decoded = json.decode(existing);
    final List<ReportedLocation> list = decoded
        .map((e) => ReportedLocation.fromJson(e))
        .where((r) => r.id != id)
        .toList();
    await prefs.setString(
        _permanentKey, json.encode(list.map((e) => e.toJson()).toList()));
  }

  /// Returns reports within [radiusMeters] of a given point.
  static List<ReportedLocation> nearby(
      List<ReportedLocation> reports, LatLng center, double radiusMeters) {
    return reports.where((r) {
      final dist = Geolocator.distanceBetween(
          center.latitude, center.longitude, r.lat, r.lng);
      return dist <= radiusMeters;
    }).toList();
  }
}

// ─────────────────────────────────────────────
// MAIN HOME SCREEN
// ─────────────────────────────────────────────

class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  static const String _openRouteApiKey =
      "Put your api key here and let the inverted commas be that way";

  GoogleMapController? _mapController;
  Position? _currentPosition;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  LatLng? _startLocation;
  LatLng? _destinationLocation;
  String _startAddress = "Current Location";
  String _destinationAddress = "Select Destination";
  List<LatLng> _routePoints = [];

  final TextEditingController _sourceController = TextEditingController();
  final TextEditingController _destController = TextEditingController();
  bool _useCurrentLocation = true;

  int _currentSpeed = 0;
  final int _safeLimit = 100;
  final List<Map<String, dynamic>> _communityReports = [];
  final List<String> _notifications = [];

  List<SavedRoute> _savedRoutes = [];

  // Reported locations (cameras + temp incidents)
  List<ReportedLocation> _reportedLocations = [];

  // Proximity alert tracking (avoid repeat alerts for same report)
  final Set<String> _alertedReportIds = {};

  // Custom marker icons (generated once at startup)
  BitmapDescriptor? _cameraIcon;
  BitmapDescriptor? _accidentIcon;
  BitmapDescriptor? _trafficIcon;

  // Text-to-Speech for voice alerts
  final FlutterTts _tts = FlutterTts();

  // Live Location Tracking
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _isNavigating = false;
  bool _followUserLocation = true;

  @override
  void initState() {
    super.initState();
    _requestLocation();
    _loadSavedRoutes();
    _loadReportedLocations();
    _generateMarkerIcons();
    _initializeTts();
  }

  Future<void> _initializeTts() async {
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.5); // Slightly slower for clarity
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  Future<void> _generateMarkerIcons() async {
    _cameraIcon = await MarkerIconPainter.cameraIcon();
    _accidentIcon = await MarkerIconPainter.warningIcon();
    _trafficIcon = await MarkerIconPainter.trafficIcon();
    // Re-draw markers now that icons are ready
    if (mounted) _refreshReportMarkers();
  }

  @override
  void dispose() {
    _sourceController.dispose();
    _destController.dispose();
    _positionStreamSubscription?.cancel();
    _tts.stop();
    super.dispose();
  }

  // ── Location Permission & Init ──────────────

  Future<void> _requestLocation() async {
    final status = await Permission.location.request();
    if (!status.isGranted) return;

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    setState(() {
      _currentPosition = position;
      _startLocation = LatLng(position.latitude, position.longitude);
      _markers.add(
        Marker(
          markerId: const MarkerId('start'),
          position: LatLng(position.latitude, position.longitude),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: 'Your Location'),
        ),
      );
    });
  }

  // ── Report DB ───────────────────────────────

  Future<void> _loadReportedLocations() async {
    final reports = await ReportDatabase.loadAll();
    setState(() {
      _reportedLocations = reports;
    });
    _refreshReportMarkers();
  }

  /// Builds map markers for all stored reports using custom shaped icons.
  void _refreshReportMarkers() {
    // Remove old report markers
    _markers.removeWhere((m) => m.markerId.value.startsWith('report_'));

    for (final report in _reportedLocations) {
      if (report.isExpired) continue;

      BitmapDescriptor icon;
      switch (report.type) {
        case 'Speed Camera':
          icon = _cameraIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
          break;
        case 'Accident':
          icon = _accidentIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
          break;
        case 'Traffic Jam':
          icon = _trafficIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
          break;
        default:
          icon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
      }

      final expiryText = report.isPermanent
          ? 'Permanent'
          : 'Expires in ${_remainingMinutes(report)} min';

      _markers.add(
        Marker(
          markerId: MarkerId('report_${report.id}'),
          position: report.latLng,
          icon: icon,
          anchor: const Offset(0.5, 1.0),
          infoWindow: InfoWindow(
            title: '${_emojiFor(report.type)} ${report.type}',
            snippet: expiryText,
          ),
          onTap: () => _onReportMarkerTapped(report),
        ),
      );
    }

    if (mounted) setState(() {});
  }

  int _remainingMinutes(ReportedLocation report) {
    if (report.isPermanent) return -1;
    final elapsed = DateTime.now().difference(report.reportedAt).inMinutes;
    return (120 - elapsed).clamp(0, 120);
  }

  void _onReportMarkerTapped(ReportedLocation report) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${_emojiFor(report.type)} ${report.type}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reported: ${_formatTime(report.reportedAt)}'),
            const SizedBox(height: 4),
            Text(
              report.isPermanent
                  ? 'Permanent record'
                  : 'Expires in ${_remainingMinutes(report)} minutes',
              style: TextStyle(
                  color: report.isPermanent ? Colors.purple : Colors.orange),
            ),
          ],
        ),
        actions: [
          if (report.isPermanent)
            TextButton(
              onPressed: () async {
                await ReportDatabase.deletePermanent(report.id);
                setState(() {
                  _reportedLocations.removeWhere((r) => r.id == report.id);
                });
                _refreshReportMarkers();
                if (mounted) Navigator.pop(ctx);
                _showSnackBar('Speed camera removed');
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Remove'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _emojiFor(String type) {
    switch (type) {
      case 'Speed Camera':
        return '📷';
      case 'Accident':
        return '🚨';
      case 'Traffic Jam':
        return '🚦';
      default:
        return '⚠️';
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  // ── Map Tap ─────────────────────────────────

  void _onMapTapped(LatLng position) {
    setState(() {
      _destinationLocation = position;
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
    _getDirections();
  }

  // ── Directions ──────────────────────────────

  Future<void> _getDirections() async {
    if (_startLocation == null || _destinationLocation == null) return;

    final String url =
        'https://api.openrouteservice.org/v2/directions/driving-car?'
        'api_key=$_openRouteApiKey&'
        'start=${_startLocation!.longitude},${_startLocation!.latitude}&'
        'end=${_destinationLocation!.longitude},${_destinationLocation!.latitude}';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['features'] != null && data['features'].isNotEmpty) {
          final route = data['features'][0];
          final coordinates = route['geometry']['coordinates'] as List;
          final properties = route['properties'];
          final summary = properties['summary'];

          List<LatLng> routePoints = coordinates.map((coord) {
            return LatLng(coord[1], coord[0]);
          }).toList();

          double distanceKm = summary['distance'] / 1000;
          double durationMin = summary['duration'] / 60;

          setState(() {
            _routePoints = routePoints;
            _polylines.clear();
            _polylines.add(
              Polyline(
                polylineId: const PolylineId('route'),
                points: _routePoints,
                color: Colors.blue,
                width: 5,
              ),
            );

            if (_destinationAddress == "Select Destination") {
              _destinationAddress =
                  "Destination (${distanceKm.toStringAsFixed(1)} km, ${durationMin.toStringAsFixed(0)} min)";
            }
          });

          _fitMapToRoute();

          // Show how many alerts are on the route
          _announceRouteAlerts();
        }
      } else if (response.statusCode == 401) {
        _showSnackBar(
            'Invalid API key. Get free key from openrouteservice.org');
      } else {
        _showSnackBar('Error getting route: ${response.statusCode}');
      }
    } catch (e) {
      _showSnackBar('Error getting route. Check internet and API key.');
    }
  }

  /// After loading a route, notify the user of any saved alerts on it.
  void _announceRouteAlerts() {
    final alerts = _reportedLocations.where((r) {
      if (r.isExpired) return false;
      // Check if this report is within 200m of any route point
      return _routePoints.any((pt) {
        final dist =
            Geolocator.distanceBetween(pt.latitude, pt.longitude, r.lat, r.lng);
        return dist <= 200;
      });
    }).toList();

    if (alerts.isEmpty) return;

    final cameras = alerts.where((a) => a.type == 'Speed Camera').length;
    final accidents = alerts.where((a) => a.type == 'Accident').length;
    final traffic = alerts.where((a) => a.type == 'Traffic Jam').length;

    final parts = <String>[];
    if (cameras > 0)
      parts.add('$cameras speed camera${cameras > 1 ? 's' : ''}');
    if (accidents > 0)
      parts.add('$accidents accident${accidents > 1 ? 's' : ''}');
    if (traffic > 0) parts.add('$traffic traffic jam${traffic > 1 ? 's' : ''}');

    final message = 'Route has: ${parts.join(', ')}';
    _showSnackBar('⚠️ $message');

    // Voice announcement for route summary
    if (cameras > 0 || accidents > 0 || traffic > 0) {
      final voiceParts = <String>[];
      if (cameras > 0)
        voiceParts.add('$cameras speed camera${cameras > 1 ? 's' : ''}');
      if (accidents > 0)
        voiceParts.add('$accidents accident${accidents > 1 ? 's' : ''}');
      if (traffic > 0)
        voiceParts.add('$traffic traffic jam${traffic > 1 ? 's' : ''}');

      _tts.speak('Route alert. Your route has ${voiceParts.join(', and ')}.');
    }
  }

  // ── Geocoding / Search ──────────────────────

  Future<LatLng?> _searchLocation(String query) async {
    if (query.trim().isEmpty) return null;

    final String url1 = 'https://api.openrouteservice.org/geocode/search?'
        'api_key=$_openRouteApiKey&'
        'text=${Uri.encodeComponent(query)}&'
        'size=1';

    try {
      final response1 = await http.get(Uri.parse(url1));
      if (response1.statusCode == 200) {
        final data1 = json.decode(response1.body);
        if (data1['features'] != null && data1['features'].isNotEmpty) {
          final coords = data1['features'][0]['geometry']['coordinates'];
          return LatLng(coords[1], coords[0]);
        }
      }

      if (!query.toLowerCase().contains('india') &&
          !query.toLowerCase().contains('mumbai') &&
          !query.toLowerCase().contains('delhi')) {
        final String url2 = 'https://api.openrouteservice.org/geocode/search?'
            'api_key=$_openRouteApiKey&'
            'text=${Uri.encodeComponent("$query India")}&'
            'size=1';
        final response2 = await http.get(Uri.parse(url2));
        if (response2.statusCode == 200) {
          final data2 = json.decode(response2.body);
          if (data2['features'] != null && data2['features'].isNotEmpty) {
            final coords = data2['features'][0]['geometry']['coordinates'];
            _showSnackBar('Found: $query, India');
            return LatLng(coords[1], coords[0]);
          }
        }
      }

      final mumbaiSuburbs = [
        'dombivli',
        'kurla',
        'andheri',
        'borivali',
        'thane',
        'mulund',
        'ghatkopar',
        'bandra',
        'dadar',
        'kalyan'
      ];
      if (mumbaiSuburbs.any((s) => query.toLowerCase().contains(s))) {
        final String url3 = 'https://api.openrouteservice.org/geocode/search?'
            'api_key=$_openRouteApiKey&'
            'text=${Uri.encodeComponent("$query Mumbai India")}&'
            'size=1';
        final response3 = await http.get(Uri.parse(url3));
        if (response3.statusCode == 200) {
          final data3 = json.decode(response3.body);
          if (data3['features'] != null && data3['features'].isNotEmpty) {
            final coords = data3['features'][0]['geometry']['coordinates'];
            _showSnackBar('Found: $query, Mumbai');
            return LatLng(coords[1], coords[0]);
          }
        }
      }
    } catch (e) {
      // silent
    }
    return null;
  }

  Future<void> _searchAndSetSource(String query) async {
    if (query.isEmpty) return;
    _showSnackBar('Searching for source location...');
    final location = await _searchLocation(query);
    if (location != null) {
      setState(() {
        _startLocation = location;
        _startAddress = query;
        _useCurrentLocation = false;
        _markers.removeWhere((m) => m.markerId.value == 'start');
        _markers.add(
          Marker(
            markerId: const MarkerId('start'),
            position: location,
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen),
            infoWindow: InfoWindow(title: 'Start: $query'),
          ),
        );
      });
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(location, 14));
      _showSnackBar('Source location set!');
      if (_destinationLocation != null) _getDirections();
    } else {
      _showSnackBar(
          'Location not found. Try: "$query Mumbai" or "$query India"');
    }
  }

  Future<void> _searchAndSetDestination(String query) async {
    if (query.isEmpty) return;
    _showSnackBar('Searching for destination...');
    final location = await _searchLocation(query);
    if (location != null) {
      setState(() {
        _destinationLocation = location;
        _destinationAddress = query;
        _markers.removeWhere((m) => m.markerId.value == 'destination');
        _markers.add(
          Marker(
            markerId: const MarkerId('destination'),
            position: location,
            icon:
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(title: 'Destination: $query'),
          ),
        );
      });
      _showSnackBar('Destination set!');
      if (_startLocation != null) _getDirections();
    } else {
      _showSnackBar(
          'Location not found. Try: "$query Mumbai" or "$query India"');
    }
  }

  void _useMyLocation() {
    if (_currentPosition != null) {
      setState(() {
        _startLocation =
            LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
        _startAddress = "Current Location";
        _useCurrentLocation = true;
        _sourceController.clear();
        _markers.removeWhere((m) => m.markerId.value == 'start');
        _markers.add(
          Marker(
            markerId: const MarkerId('start'),
            position: _startLocation!,
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen),
            infoWindow: const InfoWindow(title: 'Your Location'),
          ),
        );
      });
      _mapController
          ?.animateCamera(CameraUpdate.newLatLngZoom(_startLocation!, 14));
      if (_destinationLocation != null) _getDirections();
    }
  }

  // ── Live Tracking ───────────────────────────

  void _startLiveTracking() {
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      setState(() {
        _currentPosition = position;
        if (position.speed > 0) {
          _currentSpeed = (position.speed * 3.6).round();
        }

        _markers.removeWhere((m) => m.markerId.value == 'current');
        _markers.add(
          Marker(
            markerId: const MarkerId('current'),
            position: LatLng(position.latitude, position.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueAzure),
            infoWindow: InfoWindow(title: 'You ($_currentSpeed km/h)'),
            anchor: const Offset(0.5, 0.5),
            rotation: position.heading,
          ),
        );

        if (_followUserLocation && _mapController != null) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLng(
                LatLng(position.latitude, position.longitude)),
          );
        }
      });

      // Check proximity to saved reports while navigating
      _checkProximityAlerts(LatLng(position.latitude, position.longitude));
    });

    setState(() {
      _isNavigating = true;
    });
  }

  /// Alert the user if they are within 150m of a saved report they haven't been alerted about yet.
  void _checkProximityAlerts(LatLng currentPos) {
    final nearby = ReportDatabase.nearby(_reportedLocations, currentPos, 150);
    for (final report in nearby) {
      if (_alertedReportIds.contains(report.id)) continue;
      _alertedReportIds.add(report.id);

      final msg = '${_emojiFor(report.type)} ${report.type} ahead in ~150m!';
      setState(() {
        _notifications.insert(0, msg);
      });

      // Voice alert
      _speakAlert(report.type);

      Future.delayed(const Duration(seconds: 6), () {
        if (mounted && _notifications.isNotEmpty) {
          setState(() => _notifications.remove(msg));
        }
      });
    }
  }

  /// Speaks the alert message using text-to-speech.
  Future<void> _speakAlert(String reportType) async {
    String message;
    switch (reportType) {
      case 'Speed Camera':
        message = 'Attention. Speed camera ahead.';
        break;
      case 'Accident':
        message = 'Warning. Accident ahead.';
        break;
      case 'Traffic Jam':
        message = 'Alert. Traffic jam ahead.';
        break;
      default:
        message = 'Warning ahead.';
    }

    await _tts.speak(message);
  }

  void _stopLiveTracking() {
    _positionStreamSubscription?.cancel();
    _alertedReportIds.clear();
    setState(() {
      _isNavigating = false;
      _markers.removeWhere((m) => m.markerId.value == 'current');
    });
  }

  void _toggleNavigation() {
    if (_isNavigating) {
      _stopLiveTracking();
      _tts.speak('Navigation stopped.');
      _showSnackBar('Navigation stopped');
    } else {
      if (_routePoints.isEmpty) {
        _showSnackBar('Please set a destination first');
        return;
      }
      _startLiveTracking();

      // Zoom into user's current location with a driving-style view
      // so they can see which direction they need to go
      if (_currentPosition != null && _mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(
                _currentPosition!.latitude,
                _currentPosition!.longitude,
              ),
              zoom: 17.5,
              tilt: 45,
              bearing:
                  _currentPosition!.heading, // face the direction of travel
            ),
          ),
        );
      }

      _tts.speak('Navigation started.');
      _showSnackBar('Navigation started – zoom out anytime to see full route');
    }
  }

  // ── Map Fit ─────────────────────────────────

  void _fitMapToRoute() {
    if (_routePoints.isEmpty || _mapController == null) return;

    double minLat = _routePoints[0].latitude;
    double maxLat = _routePoints[0].latitude;
    double minLng = _routePoints[0].longitude;
    double maxLng = _routePoints[0].longitude;

    for (var point in _routePoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        100,
      ),
    );
  }

  // ── Report Submission ───────────────────────

  Future<void> _addReport(String type) async {
    if (_currentPosition == null) {
      _showSnackBar('Waiting for GPS location...');
      await _tts.speak('Waiting for GPS location.');
      return;
    }

    final bool isPermanent = (type == 'Speed Camera');
    final report = ReportedLocation(
      id: '${type}_${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      lat: _currentPosition!.latitude,
      lng: _currentPosition!.longitude,
      reportedAt: DateTime.now(),
      isPermanent: isPermanent,
    );

    await ReportDatabase.save(report);

    setState(() {
      _reportedLocations.add(report);
      _communityReports.insert(0, {
        "text": "$type reported nearby",
        "time": "Just now",
        "type": type,
      });
      _notifications.insert(
          0, '${_emojiFor(type)} $type saved at your location!');
    });

    _refreshReportMarkers();

    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _notifications.isNotEmpty) {
        setState(() => _notifications.removeAt(0));
      }
    });

    final persist = isPermanent ? 'Saved permanently' : 'Saved for 2 hours';
    _showSnackBar('$type reported. $persist.');

    // Voice confirmation
    String voiceMsg;
    switch (type) {
      case 'Speed Camera':
        voiceMsg = 'Speed camera reported and saved.';
        break;
      case 'Accident':
        voiceMsg = 'Accident reported.';
        break;
      case 'Traffic Jam':
        voiceMsg = 'Traffic jam reported.';
        break;
      default:
        voiceMsg = 'Report saved.';
    }
    await _tts.speak(voiceMsg);
  }

  // ── Saved Routes ────────────────────────────

  Future<void> _loadSavedRoutes() async {
    final prefs = await SharedPreferences.getInstance();
    final String? routesJson = prefs.getString('saved_routes');
    if (routesJson != null) {
      final List<dynamic> decoded = json.decode(routesJson);
      setState(() {
        _savedRoutes = decoded.map((e) => SavedRoute.fromJson(e)).toList();
      });
    }
  }

  Future<void> _saveRoute(String name) async {
    if (_startLocation == null || _destinationLocation == null) {
      _showSnackBar('Please select both start and destination locations');
      return;
    }

    final route = SavedRoute(
      name: name,
      startLat: _startLocation!.latitude,
      startLng: _startLocation!.longitude,
      destLat: _destinationLocation!.latitude,
      destLng: _destinationLocation!.longitude,
      startAddress: _startAddress,
      destAddress: _destinationAddress,
    );

    setState(() {
      _savedRoutes.add(route);
    });

    final prefs = await SharedPreferences.getInstance();
    final String encoded =
        json.encode(_savedRoutes.map((e) => e.toJson()).toList());
    await prefs.setString('saved_routes', encoded);
    _showSnackBar('Route saved as "$name"');
  }

  Future<void> _loadRoute(SavedRoute route) async {
    setState(() {
      _startLocation = LatLng(route.startLat, route.startLng);
      _destinationLocation = LatLng(route.destLat, route.destLng);
      _startAddress = route.startAddress;
      _destinationAddress = route.destAddress;

      _markers.removeWhere((m) =>
          m.markerId.value == 'start' || m.markerId.value == 'destination');
      _markers.add(
        Marker(
          markerId: const MarkerId('start'),
          position: _startLocation!,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: 'Start Location'),
        ),
      );
      _markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: _destinationLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Destination'),
        ),
      );
    });

    await _getDirections();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _deleteRoute(int index) async {
    setState(() {
      _savedRoutes.removeAt(index);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_routes',
        json.encode(_savedRoutes.map((e) => e.toJson()).toList()));
    _showSnackBar('Route deleted');
  }

  void _showSaveRouteDialog() {
    if (_startLocation == null || _destinationLocation == null) {
      _showSnackBar('Please select both start and destination locations');
      return;
    }
    String routeName = '';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Route'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter route name (e.g., Home to Office)',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => routeName = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (routeName.trim().isNotEmpty) {
                _saveRoute(routeName.trim());
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ── Snack Bar / Modals ──────────────────────

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  void _showSearchModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SearchModal(
        sourceController: _sourceController,
        destController: _destController,
        useCurrentLocation: _useCurrentLocation,
        currentAddress: _startAddress,
        onUseMyLocation: () {
          _useMyLocation();
          Navigator.pop(context);
        },
        onSearchSource: (query) {
          _searchAndSetSource(query);
          Navigator.pop(context);
        },
        onSearchDestination: (query) {
          _searchAndSetDestination(query);
          Navigator.pop(context);
        },
        onToggleCurrentLocation: (value) {
          setState(() {
            _useCurrentLocation = value;
            if (value) _useMyLocation();
          });
        },
      ),
    );
  }

  // ── Build ───────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.blue),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.navigation, color: Colors.white, size: 48),
                  SizedBox(height: 8),
                  Text('Navigation Menu',
                      style: TextStyle(color: Colors.white, fontSize: 24)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.route, color: Colors.blue),
              title: const Text('Saved Routes'),
              trailing: Badge(
                label: Text('${_savedRoutes.length}'),
                child: const Icon(Icons.arrow_forward_ios, size: 16),
              ),
              onTap: () {
                Navigator.pop(context);
                _showSavedRoutesScreen();
              },
            ),
            ListTile(
              leading: const Icon(Icons.save, color: Colors.green),
              title: const Text('Save Current Route'),
              onTap: () {
                Navigator.pop(context);
                _showSaveRouteDialog();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.purple),
              title: const Text('Saved Speed Cameras'),
              trailing: Badge(
                label: Text(
                    '${_reportedLocations.where((r) => r.isPermanent).length}'),
                child: const Icon(Icons.arrow_forward_ios, size: 16),
              ),
              onTap: () {
                Navigator.pop(context);
                _showSavedCamerasScreen();
              },
            ),
            ListTile(
              leading: const Icon(Icons.people, color: Colors.orange),
              title: const Text('Community Reports'),
              onTap: () {
                Navigator.pop(context);
                _showCommunityDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          // FULL SCREEN MAP
          _currentPosition == null
              ? const Center(child: CircularProgressIndicator())
              : GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(_currentPosition!.latitude,
                        _currentPosition!.longitude),
                    zoom: 15,
                  ),
                  markers: _markers,
                  polylines: _polylines,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  onTap: _onMapTapped,
                  onMapCreated: (controller) {
                    _mapController = controller;
                    _refreshReportMarkers();
                  },
                ),

          // FLOATING MENU BUTTON
          Positioned(
            top: 50,
            left: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu, color: Colors.black87),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
            ),
          ),

          // FLOATING SEARCH BAR
          Positioned(
            top: 50,
            left: 70,
            right: 16,
            child: GestureDetector(
              onTap: _showSearchModal,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: Colors.grey, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _startAddress.isEmpty
                                ? "Search location..."
                                : _startAddress,
                            style: TextStyle(
                              fontSize: 14,
                              color: _startAddress.isEmpty
                                  ? Colors.grey[500]
                                  : Colors.black87,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (_destinationAddress != "Select Destination") ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.arrow_forward,
                                    size: 12, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    _destinationAddress,
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey[700]),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // MY LOCATION BUTTON
          Positioned(
            bottom: 180,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                icon: const Icon(Icons.my_location, color: Colors.blue),
                onPressed: () {
                  if (_currentPosition != null) {
                    _mapController?.animateCamera(
                      CameraUpdate.newLatLngZoom(
                        LatLng(_currentPosition!.latitude,
                            _currentPosition!.longitude),
                        15,
                      ),
                    );
                  }
                },
              ),
            ),
          ),

          // START/STOP NAVIGATION BUTTON
          if (_routePoints.isNotEmpty)
            Positioned(
              bottom: 240,
              right: 16,
              child: FloatingActionButton(
                heroTag: 'navigation',
                backgroundColor: _isNavigating ? Colors.red : Colors.green,
                onPressed: _toggleNavigation,
                child: Icon(
                  _isNavigating ? Icons.stop : Icons.navigation,
                  color: Colors.white,
                ),
              ),
            ),

          // ROUTE INFO CARD
          if (_routePoints.isNotEmpty)
            Positioned(
              top: 130,
              left: 16,
              right: 16,
              child: Column(
                children: [
                  RouteInfoCard(
                    startAddress: _startAddress,
                    destinationAddress: _destinationAddress,
                    onClear: () {
                      _stopLiveTracking();
                      setState(() {
                        _polylines.clear();
                        _routePoints.clear();
                        _markers.removeWhere(
                            (m) => m.markerId.value == 'destination');
                        _destinationLocation = null;
                        _destController.clear();
                        _destinationAddress = "Select Destination";
                      });
                    },
                  ),
                  if (_isNavigating)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.navigation,
                              color: Colors.white, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'Navigating • $_currentSpeed km/h',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

          // NOTIFICATIONS
          Positioned(
            top: _routePoints.isNotEmpty ? 270 : 130,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _notifications
                  .map((n) => LiveNotification(message: n))
                  .toList(),
            ),
          ),

          // SPEED GAUGE (Bottom Left)
          Positioned(
            bottom: 30,
            left: 16,
            child: SpeedGauge(speed: _currentSpeed, limit: _safeLimit),
          ),

          // SPEED INPUT (Bottom Right, above report button)
          Positioned(
            bottom: 100,
            right: 16,
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 50,
                    height: 30,
                    child: TextField(
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: '0',
                        hintStyle: TextStyle(fontSize: 16),
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (val) => setState(
                          () => _currentSpeed = int.tryParse(val) ?? 0),
                    ),
                  ),
                  Text(
                    'km/h',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // REPORT BUTTON
          Positioned(
            bottom: 30,
            right: 16,
            child: ExpandableReportButton(onReport: _addReport),
          ),
        ],
      ),
    );
  }

  // ── Community & Camera screens ──────────────

  void _showCommunityDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Community Updates"),
        content: SizedBox(
          width: double.maxFinite,
          child: _communityReports.isEmpty
              ? const Center(child: Text('No reports yet'))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _communityReports.length,
                  itemBuilder: (context, i) {
                    final r = _communityReports[i];
                    return ListTile(
                      leading: Text(_emojiFor(r['type'] ?? ''),
                          style: const TextStyle(fontSize: 22)),
                      title: Text(r['text']),
                      subtitle: Text(r['time']),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showSavedRoutesScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SavedRoutesScreen(
          savedRoutes: _savedRoutes,
          onLoadRoute: _loadRoute,
          onDeleteRoute: _deleteRoute,
        ),
      ),
    );
  }

  void _showSavedCamerasScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SavedCamerasScreen(
          reportedLocations: _reportedLocations,
          onDelete: (id) async {
            await ReportDatabase.deletePermanent(id);
            setState(() {
              _reportedLocations.removeWhere((r) => r.id == id);
            });
            _refreshReportMarkers();
          },
          onGoTo: (report) {
            _mapController?.animateCamera(
              CameraUpdate.newLatLngZoom(report.latLng, 16),
            );
            Navigator.pop(context);
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SAVED CAMERAS SCREEN
// ─────────────────────────────────────────────

class SavedCamerasScreen extends StatelessWidget {
  final List<ReportedLocation> reportedLocations;
  final Function(String id) onDelete;
  final Function(ReportedLocation) onGoTo;

  const SavedCamerasScreen({
    super.key,
    required this.reportedLocations,
    required this.onDelete,
    required this.onGoTo,
  });

  @override
  Widget build(BuildContext context) {
    final cameras = reportedLocations.where((r) => r.isPermanent).toList();
    final temp =
        reportedLocations.where((r) => !r.isPermanent && !r.isExpired).toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Saved Reports'),
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(icon: Icon(Icons.camera_alt), text: 'Speed Cameras'),
              Tab(icon: Icon(Icons.warning_amber), text: 'Temp Incidents'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildList(context, cameras, isPermanentTab: true),
            _buildList(context, temp, isPermanentTab: false),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, List<ReportedLocation> items,
      {required bool isPermanentTab}) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isPermanentTab ? Icons.camera_alt : Icons.warning_amber,
              size: 64,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 12),
            Text(
              isPermanentTab
                  ? 'No speed cameras saved yet'
                  : 'No active incidents',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 6),
            Text(
              isPermanentTab
                  ? 'Use the 📷 report button while driving'
                  : 'Accidents & traffic jams expire after 2 hours',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (ctx, index) {
        final r = items[index];
        final remaining =
            r.isPermanent ? 'Permanent' : 'Expires in ${_rem(r)} min';

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _colorFor(r.type),
              child:
                  Text(_emojiFor(r.type), style: const TextStyle(fontSize: 18)),
            ),
            title: Text(r.type,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Lat: ${r.lat.toStringAsFixed(5)}, Lng: ${r.lng.toStringAsFixed(5)}',
                    style: const TextStyle(fontSize: 11)),
                Text(remaining,
                    style: TextStyle(
                        fontSize: 11,
                        color: r.isPermanent ? Colors.purple : Colors.orange)),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.map, color: Colors.blue),
                  onPressed: () => onGoTo(r),
                  tooltip: 'Show on map',
                ),
                if (r.isPermanent)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      showDialog(
                        context: ctx,
                        builder: (dCtx) => AlertDialog(
                          title: const Text('Remove Speed Camera?'),
                          content: const Text(
                              'This will permanently delete this camera record.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dCtx),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red),
                              onPressed: () {
                                onDelete(r.id);
                                Navigator.pop(dCtx);
                              },
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                    },
                    tooltip: 'Delete',
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  int _rem(ReportedLocation r) {
    final elapsed = DateTime.now().difference(r.reportedAt).inMinutes;
    return (120 - elapsed).clamp(0, 120);
  }

  String _emojiFor(String type) {
    switch (type) {
      case 'Speed Camera':
        return '📷';
      case 'Accident':
        return '🚨';
      case 'Traffic Jam':
        return '🚦';
      default:
        return '⚠️';
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'Speed Camera':
        return Colors.purple.shade100;
      case 'Accident':
        return Colors.orange.shade100;
      case 'Traffic Jam':
        return Colors.amber.shade100;
      default:
        return Colors.grey.shade200;
    }
  }
}

// ─────────────────────────────────────────────
// SEARCH MODAL WIDGET
// ─────────────────────────────────────────────

class SearchModal extends StatefulWidget {
  final TextEditingController sourceController;
  final TextEditingController destController;
  final bool useCurrentLocation;
  final String currentAddress;
  final VoidCallback onUseMyLocation;
  final Function(String) onSearchSource;
  final Function(String) onSearchDestination;
  final Function(bool) onToggleCurrentLocation;

  const SearchModal({
    super.key,
    required this.sourceController,
    required this.destController,
    required this.useCurrentLocation,
    required this.currentAddress,
    required this.onUseMyLocation,
    required this.onSearchSource,
    required this.onSearchDestination,
    required this.onToggleCurrentLocation,
  });

  @override
  State<SearchModal> createState() => _SearchModalState();
}

class _SearchModalState extends State<SearchModal> {
  bool _useCurrentLoc = true;

  @override
  void initState() {
    super.initState();
    _useCurrentLoc = widget.useCurrentLocation;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(25),
          topRight: Radius.circular(25),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Set Your Route',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                const Text('Start Location',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87)),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _useCurrentLoc ? Icons.my_location : Icons.location_on,
                        color: Colors.green,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _useCurrentLoc
                              ? widget.currentAddress
                              : 'Search location',
                          style:
                              TextStyle(fontSize: 14, color: Colors.grey[800]),
                        ),
                      ),
                      Switch(
                        value: _useCurrentLoc,
                        activeColor: Colors.green,
                        onChanged: (value) {
                          setState(() => _useCurrentLoc = value);
                          widget.onToggleCurrentLocation(value);
                          if (value) widget.onUseMyLocation();
                        },
                      ),
                    ],
                  ),
                ),
                if (!_useCurrentLoc) ...[
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: TextField(
                      controller: widget.sourceController,
                      decoration: InputDecoration(
                        hintText: 'Enter source location',
                        prefixIcon:
                            const Icon(Icons.search, color: Colors.grey),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.send, color: Colors.blue),
                          onPressed: () {
                            if (widget.sourceController.text.isNotEmpty) {
                              widget
                                  .onSearchSource(widget.sourceController.text);
                            }
                          },
                        ),
                      ),
                      onSubmitted: (v) {
                        if (v.isNotEmpty) widget.onSearchSource(v);
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                const Text('Destination',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: TextField(
                    controller: widget.destController,
                    decoration: InputDecoration(
                      hintText: 'Enter destination',
                      prefixIcon:
                          const Icon(Icons.location_on, color: Colors.red),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.send, color: Colors.blue),
                        onPressed: () {
                          if (widget.destController.text.isNotEmpty) {
                            widget.onSearchDestination(
                                widget.destController.text);
                          }
                        },
                      ),
                    ),
                    onSubmitted: (v) {
                      if (v.isNotEmpty) widget.onSearchDestination(v);
                    },
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (widget.destController.text.isNotEmpty) {
                        if (!_useCurrentLoc &&
                            widget.sourceController.text.isNotEmpty) {
                          widget.onSearchSource(widget.sourceController.text);
                          Future.delayed(const Duration(milliseconds: 500), () {
                            widget.onSearchDestination(
                                widget.destController.text);
                          });
                        } else {
                          widget
                              .onSearchDestination(widget.destController.text);
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Search Route',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// DATA CLASS: SavedRoute
// ─────────────────────────────────────────────

class SavedRoute {
  final String name;
  final double startLat;
  final double startLng;
  final double destLat;
  final double destLng;
  final String startAddress;
  final String destAddress;

  SavedRoute({
    required this.name,
    required this.startLat,
    required this.startLng,
    required this.destLat,
    required this.destLng,
    required this.startAddress,
    required this.destAddress,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'startLat': startLat,
        'startLng': startLng,
        'destLat': destLat,
        'destLng': destLng,
        'startAddress': startAddress,
        'destAddress': destAddress,
      };

  factory SavedRoute.fromJson(Map<String, dynamic> json) => SavedRoute(
        name: json['name'],
        startLat: json['startLat'],
        startLng: json['startLng'],
        destLat: json['destLat'],
        destLng: json['destLng'],
        startAddress: json['startAddress'],
        destAddress: json['destAddress'],
      );
}

// ─────────────────────────────────────────────
// WIDGET: RouteInfoCard
// ─────────────────────────────────────────────

class RouteInfoCard extends StatelessWidget {
  final String startAddress;
  final String destinationAddress;
  final VoidCallback onClear;

  const RouteInfoCard({
    super.key,
    required this.startAddress,
    required this.destinationAddress,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.navigation, color: Colors.blue),
                const SizedBox(width: 8),
                const Text('Active Route',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: onClear,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const Divider(),
            Row(
              children: [
                const Icon(Icons.my_location, color: Colors.green, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(startAddress,
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.red, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(destinationAddress,
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// WIDGET: SpeedGauge
// ─────────────────────────────────────────────

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

// ─────────────────────────────────────────────
// WIDGET: LiveNotification
// ─────────────────────────────────────────────

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

// ─────────────────────────────────────────────
// WIDGET: ExpandableReportButton
// ─────────────────────────────────────────────

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
          _reportIcon(Icons.camera_alt, "Speed Camera", Colors.purple),
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
        heroTag: label,
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

// ─────────────────────────────────────────────
// SCREEN: SavedRoutesScreen
// ─────────────────────────────────────────────

class SavedRoutesScreen extends StatelessWidget {
  final List<SavedRoute> savedRoutes;
  final Function(SavedRoute) onLoadRoute;
  final Function(int) onDeleteRoute;

  const SavedRoutesScreen({
    super.key,
    required this.savedRoutes,
    required this.onLoadRoute,
    required this.onDeleteRoute,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Routes'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: savedRoutes.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.route, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text('No saved routes yet',
                      style: TextStyle(fontSize: 18, color: Colors.grey[600])),
                  const SizedBox(height: 8),
                  Text('Create a route and save it\nfrom the menu',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[500])),
                ],
              ),
            )
          : ListView.builder(
              itemCount: savedRoutes.length,
              itemBuilder: (context, index) {
                final route = savedRoutes[index];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue,
                      child: Text(route.name[0].toUpperCase(),
                          style: const TextStyle(color: Colors.white)),
                    ),
                    title: Text(route.name,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.my_location,
                                size: 14, color: Colors.green),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(route.startAddress,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.location_on,
                                size: 14, color: Colors.red),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(route.destAddress,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete Route'),
                            content: Text('Delete "${route.name}"?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red),
                                onPressed: () {
                                  onDeleteRoute(index);
                                  Navigator.pop(ctx);
                                },
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    onTap: () => onLoadRoute(route),
                  ),
                );
              },
            ),
    );
  }
}
