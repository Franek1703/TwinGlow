import 'package:flutter_test/flutter_test.dart';
import 'package:twin_glow/features/image_import/cubit/image_import_cubit.dart';
import 'package:twin_glow/services/image_import/image_import_converter.dart';
import 'package:twin_glow/services/image_import/image_import_service.dart';

void main() {
  test('converts the selected crop rather than the original non-square image',
      () async {
    final service = _FakeImageImportService(
      cropResults: ['selected-square.png'],
    );
    final cubit = ImageImportCubit(service);
    addTearDown(cubit.close);

    await cubit.start(ImageImportSource.files);

    expect(service.convertedPaths, ['selected-square.png']);
    expect(cubit.state.status, ImageImportStatus.ready);
    expect(cubit.state.pixelData![0][0], 0xFFFF0000);
  });

  test('mode changes choose the matching precomputed preview', () async {
    final service = _FakeImageImportService(cropResults: ['crop.png']);
    final cubit = ImageImportCubit(service);
    addTearDown(cubit.close);

    await cubit.start(ImageImportSource.photoLibrary);
    expect(cubit.state.mode, ImageConversionMode.pixelArt);
    expect(cubit.state.pixelData![0][0], 0xFFFF0000);

    cubit.setMode(ImageConversionMode.photo);
    expect(cubit.state.pixelData![0][0], 0xFF0000FF);
  });

  test('picker cancellation ends cleanly', () async {
    final service = _FakeImageImportService(
      selection: null,
      cropResults: const [],
    );
    final cubit = ImageImportCubit(service);
    addTearDown(cubit.close);

    await cubit.start(ImageImportSource.photoLibrary);

    expect(cubit.state.status, ImageImportStatus.cancelled);
    expect(service.convertedPaths, isEmpty);
  });

  test('recrop cancellation preserves the existing preview', () async {
    final service = _FakeImageImportService(
      cropResults: ['first-crop.png', null],
    );
    final cubit = ImageImportCubit(service);
    addTearDown(cubit.close);

    await cubit.start(ImageImportSource.files);
    final previous = cubit.state.conversion;
    await cubit.changeCrop();

    expect(cubit.state.status, ImageImportStatus.ready);
    expect(cubit.state.conversion, same(previous));
    expect(service.convertedPaths, ['first-crop.png']);
  });

  test('import failures become recoverable failure state', () async {
    final service = _FakeImageImportService(
      cropResults: const [],
      selectFailure: const ImageImportFailure('Unsupported image format.'),
    );
    final cubit = ImageImportCubit(service);
    addTearDown(cubit.close);

    await cubit.start(ImageImportSource.files);

    expect(cubit.state.status, ImageImportStatus.failure);
    expect(cubit.state.error, 'Unsupported image format.');
  });
}

class _FakeImageImportService implements ImageImportService {
  final SelectedImportImage? selection;
  final List<String?> cropResults;
  final ImageImportFailure? selectFailure;
  final List<String> convertedPaths = [];
  int _cropIndex = 0;

  _FakeImageImportService({
    this.selection = const SelectedImportImage(
      path: 'original-wide.png',
      name: 'original-wide.png',
    ),
    required this.cropResults,
    this.selectFailure,
  });

  @override
  Future<SelectedImportImage?> selectImage(ImageImportSource source) async {
    if (selectFailure != null) throw selectFailure!;
    return selection;
  }

  @override
  Future<String?> cropToSquare(String sourcePath) async {
    return cropResults[_cropIndex++];
  }

  @override
  Future<ImageConversionResult> convertCroppedImage(String croppedPath) async {
    convertedPaths.add(croppedPath);
    return ImageConversionResult(
      pixelArtData: _grid(0xFFFF0000),
      photoData: _grid(0xFF0000FF),
      suggestedMode: ImageConversionMode.pixelArt,
      sourceWidth: 32,
      sourceHeight: 32,
    );
  }

  List<List<int>> _grid(int color) {
    return List.generate(16, (_) => List.filled(16, color));
  }
}
