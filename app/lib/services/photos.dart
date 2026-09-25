import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jobwalk_core/jobwalk_core.dart';
import 'package:jobwalk_core/photo_pipeline.dart';

enum PhotoOrigin { camera, library }

abstract interface class PhotoSource {
  /// Picked image bytes; empty if the person cancelled.
  Future<List<Uint8List>> pick(PhotoOrigin origin, {int max = 8});
}

class ImagePickerPhotoSource implements PhotoSource {
  final _picker = ImagePicker();

  @override
  Future<List<Uint8List>> pick(PhotoOrigin origin, {int max = 8}) async {
    // Let the platform downscale first; it is much faster than Dart.
    const maxSide = 2560.0;
    const quality = 90;
    if (origin == PhotoOrigin.camera) {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: maxSide,
        maxHeight: maxSide,
        imageQuality: quality,
        requestFullMetadata: false,
      );
      return file == null ? const [] : [await file.readAsBytes()];
    }
    final files = await _picker.pickMultiImage(
      maxWidth: maxSide,
      maxHeight: maxSide,
      imageQuality: quality,
      limit: max < 2 ? null : max,
      requestFullMetadata: false,
    );
    return [for (final f in files.take(max)) await f.readAsBytes()];
  }
}

/// A job photo ready to send, plus a small copy to keep with the quote.
class JobPhotoFile {
  const JobPhotoFile({
    required this.jpeg,
    required this.preview,
    this.problems = const [],
  });

  final Uint8List jpeg;
  final Uint8List preview;
  final List<PhotoProblem> problems;
}

typedef PhotoProcessor = Future<JobPhotoFile> Function(Uint8List bytes);

/// Resizes, re-encodes, and checks a photo off the UI thread, with the same
/// pipeline the accuracy harness uses.
Future<JobPhotoFile> processPhoto(Uint8List bytes) =>
    compute(_process, bytes, debugLabel: 'processPhoto');

JobPhotoFile _process(Uint8List bytes) {
  final full = preparePhoto(bytes);
  // Web storage is small, so the web build keeps a lighter copy.
  final preview = preparePhoto(
    full.jpeg,
    maxDimension: kIsWeb ? 640 : 1024,
    jpegQuality: 78,
  );
  return JobPhotoFile(
    jpeg: full.jpeg,
    preview: preview.jpeg,
    problems: full.problems,
  );
}

/// Bundled photos for the sample jobs.
List<String> sampleAssets(SampleJob job) => [
  for (var i = 1; i <= job.photoCount; i++) 'assets/samples/${job.id}_$i.jpg',
];

Future<List<Uint8List>> loadSamplePhotos(SampleJob job) async => [
  for (final asset in sampleAssets(job))
    (await rootBundle.load(asset)).buffer.asUint8List(),
];

/// What a sample job's walkthrough note and customer would be.
({String note, String customer}) sampleContext(SampleJob job) => switch (job) {
  SampleJob.livingRoom => (
    note: 'Two coats on the walls. She asked about doing the trim too.',
    customer: 'Dana Ortiz',
  ),
  SampleJob.fence => (
    note: 'Replace the whole run on the same line. He is leaning cedar.',
    customer: 'Marcus Webb',
  ),
  SampleJob.driveway => (
    note: 'Driveway and the front walk. Ask about sealing.',
    customer: 'Priya Shah',
  ),
};
