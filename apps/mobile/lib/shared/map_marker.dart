import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Loads an asset PNG and returns a [BitmapDescriptor] at the given
/// logical-pixel width/height for Google Maps markers.
/// The PNG should already be at @3x resolution (e.g. 104×128 for a 35×43 pt marker).
Future<BitmapDescriptor> assetToBitmapDescriptor(
  String assetPath, {
  required double width,
  required double height,
}) async {
  final bytes = await rootBundle.load(assetPath);
  return BitmapDescriptor.bytes(
    bytes.buffer.asUint8List(),
    width: width,
    height: height,
  );
}
