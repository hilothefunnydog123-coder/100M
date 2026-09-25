import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:spotcheck_core/photo_pipeline.dart';

enum PhotoOrigin { camera, library }

abstract interface class PhotoSource {
  /// Returns image bytes, or null if the person cancelled.
  Future<Uint8List?> pick(PhotoOrigin origin);
}

class ImagePickerPhotoSource implements PhotoSource {
  final _picker = ImagePicker();

  @override
  Future<Uint8List?> pick(PhotoOrigin origin) async {
    final file = await _picker.pickImage(
      source: origin == PhotoOrigin.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      // Let the platform downscale first; it is much faster than Dart.
      maxWidth: 2560,
      maxHeight: 2560,
      imageQuality: 92,
      // Avoids asking for full photo-library access on iOS.
      requestFullMetadata: false,
    );
    return file?.readAsBytes();
  }
}

/// Synthetic sample photos bundled for demo mode.
enum SamplePhoto {
  mole('assets/samples/mole.jpg', 'Sample: a mole'),
  rash('assets/samples/rash.jpg', 'Sample: a rash');

  const SamplePhoto(this.asset, this.label);

  final String asset;
  final String label;

  Future<Uint8List> load() async =>
      (await rootBundle.load(asset)).buffer.asUint8List();
}

/// Resizes, re-encodes, and scores a photo off the UI thread, using the same
/// pipeline the accuracy harness uses.
Future<PreparedPhoto> processPhoto(Uint8List bytes) =>
    compute(_prepare, bytes, debugLabel: 'preparePhoto');

PreparedPhoto _prepare(Uint8List bytes) => preparePhoto(bytes);

/// Web storage is small, so the web build keeps a lighter copy for history.
Future<Uint8List> historyCopy(Uint8List jpeg) async {
  if (!kIsWeb) return jpeg;
  final small = await compute(_preview, jpeg, debugLabel: 'preview');
  return small;
}

Uint8List _preview(Uint8List bytes) =>
    preparePhoto(bytes, maxDimension: 640, jpegQuality: 80).jpeg;
