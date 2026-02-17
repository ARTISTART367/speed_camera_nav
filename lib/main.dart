import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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

  // Live Location Tracking
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _isNavigating = false;
  bool _followUserLocation = true;

  @override
  void initState() {
    super.initState();
    _requestLocation();
    _loadSavedRoutes();
  }

  @override
  void dispose() {
    _sourceController.dispose();
    _destController.dispose();
    _positionStreamSubscription?.cancel(); // Cancel location stream
    super.dispose();
  }

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
        }
      } else if (response.statusCode == 401) {
        _showSnackBar(
            'Invalid API key. Get free key from openrouteservice.org');
      } else {
        _showSnackBar('Error getting route: ${response.statusCode}');
      }
    } catch (e) {
      print('Error getting directions: $e');
      _showSnackBar('Error getting route. Check internet and API key.');
    }
  }

  Future<LatLng?> _searchLocation(String query) async {
    if (query.trim().isEmpty) return null;

    // First try: exact search
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

      // Second try: add "India" if not found
      if (!query.toLowerCase().contains('india') &&
          !query.toLowerCase().contains('mumbai') &&
          !query.toLowerCase().contains('delhi')) {
        final String url2 = 'https://api.openrouteservice.org/geocode/search?'
            'api_key=$_openRouteApiKey&'
            'text=${Uri.encodeComponent(query + " India")}&'
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

      // Third try: add "Mumbai India" for common Mumbai suburbs
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
            'text=${Uri.encodeComponent(query + " Mumbai India")}&'
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
      print('Error searching location: $e');
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

      if (_destinationLocation != null) {
        _getDirections();
      }
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

      if (_startLocation != null) {
        _getDirections();
      }
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

      if (_destinationLocation != null) {
        _getDirections();
      }
    }
  }

  // Start Live Location Tracking
  void _startLiveTracking() {
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Update every 10 meters
    );

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      setState(() {
        _currentPosition = position;

        // Calculate speed from GPS (m/s to km/h)
        if (position.speed > 0) {
          _currentSpeed = (position.speed * 3.6).round();
        }

        // Update current location marker
        _markers.removeWhere((m) => m.markerId.value == 'current');
        _markers.add(
          Marker(
            markerId: const MarkerId('current'),
            position: LatLng(position.latitude, position.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueAzure),
            infoWindow: InfoWindow(title: 'You (${_currentSpeed} km/h)'),
            anchor: const Offset(0.5, 0.5),
            rotation: position.heading, // Rotate marker based on direction
          ),
        );

        // Auto-follow user location if enabled
        if (_followUserLocation && _mapController != null) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLng(
              LatLng(position.latitude, position.longitude),
            ),
          );
        }
      });
    });

    setState(() {
      _isNavigating = true;
    });
  }

  // Stop Live Location Tracking
  void _stopLiveTracking() {
    _positionStreamSubscription?.cancel();
    setState(() {
      _isNavigating = false;
      _markers.removeWhere((m) => m.markerId.value == 'current');
    });
  }

  // Toggle navigation mode
  void _toggleNavigation() {
    if (_isNavigating) {
      _stopLiveTracking();
      _showSnackBar('Navigation stopped');
    } else {
      if (_routePoints.isEmpty) {
        _showSnackBar('Please set a destination first');
        return;
      }
      _startLiveTracking();
      _showSnackBar('Navigation started - Following your location');
    }
  }

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

  void _addReport(String type) async {
    String reportEntry = "$type reported nearby";

    setState(() {
      _communityReports.insert(0, {"text": reportEntry, "time": "Just now"});
      _notifications.add("$type detected on your route!");
    });

    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _notifications.isNotEmpty) {
        setState(() => _notifications.removeAt(0));
      }
    });
  }

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

      _markers.clear();
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
    Navigator.pop(context);
  }

  Future<void> _deleteRoute(int index) async {
    setState(() {
      _savedRoutes.removeAt(index);
    });

    final prefs = await SharedPreferences.getInstance();
    final String encoded =
        json.encode(_savedRoutes.map((e) => e.toJson()).toList());
    await prefs.setString('saved_routes', encoded);

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

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
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
            if (value) {
              _useMyLocation();
            }
          });
        },
      ),
    );
  }

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
              onTap: () {
                Navigator.pop(context);
              },
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
                  onMapCreated: (controller) => _mapController = controller,
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
                                      fontSize: 12,
                                      color: Colors.grey[700],
                                    ),
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
                      _stopLiveTracking(); // Stop tracking when route cleared
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
                  // Navigation Status Indicator
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
                            'Navigating • ${_currentSpeed} km/h',
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
                  itemBuilder: (context, i) => ListTile(
                    leading: const Icon(Icons.report, color: Colors.orange),
                    title: Text(_communityReports[i]['text']),
                    subtitle: Text(_communityReports[i]['time']),
                  ),
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
}

//////////////////////////////////////////////////////////
/// SEARCH MODAL WIDGET
//////////////////////////////////////////////////////////

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
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
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
          // Handle bar
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
                const Text(
                  'Set Your Route',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),

                // SOURCE LOCATION
                const Text(
                  'Start Location',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),

                // Toggle for current location
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
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[800],
                          ),
                        ),
                      ),
                      Switch(
                        value: _useCurrentLoc,
                        activeColor: Colors.green,
                        onChanged: (value) {
                          setState(() {
                            _useCurrentLoc = value;
                          });
                          widget.onToggleCurrentLocation(value);
                          if (value) {
                            widget.onUseMyLocation();
                          }
                        },
                      ),
                    ],
                  ),
                ),

                // SOURCE SEARCH (if not using current location)
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
                      onSubmitted: (value) {
                        if (value.isNotEmpty) {
                          widget.onSearchSource(value);
                        }
                      },
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // DESTINATION LOCATION
                const Text(
                  'Destination',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
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
                    onSubmitted: (value) {
                      if (value.isNotEmpty) {
                        widget.onSearchDestination(value);
                      }
                    },
                  ),
                ),

                const SizedBox(height: 20),

                // SEARCH BUTTON
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
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Search Route',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
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

// [Rest of the components - SavedRoute, RouteInfoCard, SpeedGauge, etc. remain the same]

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
                  Text(
                    'No saved routes yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create a route and save it\nfrom the menu',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[500]),
                  ),
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
                      child: Text(
                        route.name[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    title: Text(
                      route.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
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
                              child: Text(
                                route.startAddress,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
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
                              child: Text(
                                route.destAddress,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
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
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Route'),
                            content: Text('Delete "${route.name}"?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red),
                                onPressed: () {
                                  onDeleteRoute(index);
                                  Navigator.pop(context);
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
