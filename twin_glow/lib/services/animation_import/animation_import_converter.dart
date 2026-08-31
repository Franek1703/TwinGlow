import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../core/models/asset_model.dart';
import '../image_import/editor_image_converter.dart';
import 'animation_crop.dart';
import 'animation_frame_timeline.dart';

/// What a decoded source animation looks like before anything is converted.
class AnimationSourceInfo {
  final int width;
  final int height;
  final int frameCount;
  final img.ImageFormat format;

  const AnimationSourceInfo({
    required this.width,
    required this.height,
    required this.frameCount,
    required this.format,
  });
}

/// The still shown in the crop view: the first fully composed frame, shrunk to
/// something a widget can hold, plus the canvas it was taken from.
class AnimationPreviewSource {
  final Uint8List previewPng;
  final int sourceWidth;
  final int sourceHeight;
  final int sourceFrameCount;

  const AnimationPreviewSource({
    required this.previewPng,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.sourceFrameCount,
  });
}

/// Both conversion modes for one crop, so switching modes in the preview never
/// re-decodes.
class AnimationConversionResult {
  final OptimizedTimeline pixelArt;
  final OptimizedTimeline photo;
  final ImageConversionMode suggestedMode;
  final int sourceWidth;
  final int sourceHeight;
  final int cropSize;

  const AnimationConversionResult({
    required this.pixelArt,
    required this.photo,
    required this.suggestedMode,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.cropSize,
  });

  OptimizedTimeline timelineFor(ImageConversionMode mode) =>
      mode == ImageConversionMode.pixelArt ? pixelArt : photo;

  List<AnimationFrameModel> framesFor(ImageConversionMode mode) =>
      timelineFor(mode).frames;
}

/// Decodes GIF, animated WebP, and APNG files into editor frames.
///
/// Everything here is pure Dart over bytes so the whole pass can run in
/// [Isolate.run]; only the bounded preview and the finished 16x16 frames come
/// back to the UI isolate.
class AnimationImportConverter {
  const AnimationImportConverter._();

  static const int maxFileBytes = 50 * 1024 * 1024;

  /// Canvas ceiling. Tighter than still import's 50MP because every frame pays
  /// this cost again.
  static const int maxCanvasPixels = 16000000;

  static const int maxSourceFrames = 500;

  /// Canvas pixels summed across frames - the real predictor of decode time.
  static const int maxDecodedPixels = 32000000;

  /// Longest edge of the crop-view still.
  static const int previewMaxEdge = 512;

  /// Frames sampled when deciding whether a source is pixel art.
  static const int _modeSampleFrames = 4;

  /// Reads the header only, so an unusable file is rejected before the
  /// expensive decode.
  static AnimationSourceInfo inspectSource(Uint8List bytes) {
    final format = img.findFormatForData(bytes);
    if (format != img.ImageFormat.gif &&
        format != img.ImageFormat.png &&
        format != img.ImageFormat.webp) {
      throw const ImageImportFailure(
        'Unsupported format. Choose an animated GIF, WebP, or APNG file.',
      );
    }

    final decoder = img.createDecoderForFormat(format);
    final info = decoder?.startDecode(bytes);
    if (info == null || info.width <= 0 || info.height <= 0) {
      throw const ImageImportFailure(
        'This file is corrupted or could not be decoded.',
      );
    }

    if (info.width * info.height > maxCanvasPixels) {
      throw const ImageImportFailure(
        'This animation is too large. Choose one smaller than 16 megapixels '
        'per frame.',
      );
    }

    final frameCount = info.numFrames;
    if (frameCount < 2) {
      throw const ImageImportFailure(
        'This file holds a single frame. Choose an animated GIF, WebP, or '
        'APNG - picking a still from the photo library can flatten one.',
      );
    }
    if (frameCount > maxSourceFrames) {
      throw const ImageImportFailure(
        'This animation has more than $maxSourceFrames frames. Choose a '
        'shorter clip.',
      );
    }
    if (info.width * info.height * frameCount > maxDecodedPixels) {
      throw const ImageImportFailure(
        'This animation is too big to decode on device. Choose a smaller or '
        'shorter one.',
      );
    }

    return AnimationSourceInfo(
      width: info.width,
      height: info.height,
      frameCount: frameCount,
      format: format,
    );
  }

  /// Decodes far enough to show the crop view its first composed frame.
  static AnimationPreviewSource loadPreview(Uint8List bytes) {
    final info = inspectSource(bytes);
    final composed = _composeFrames(bytes, info);
    final first = composed.first.image;

    final scale = math.min(
      1.0,
      previewMaxEdge / math.max(first.width, first.height),
    );
    final flattened = first.convert(numChannels: 4, noAnimation: true);
    final preview = scale >= 1.0
        ? flattened
        : img.copyResize(
            flattened,
            width: math.max(1, (first.width * scale).round()),
            height: math.max(1, (first.height * scale).round()),
            interpolation: img.Interpolation.average,
          );

    return AnimationPreviewSource(
      previewPng: img.encodePng(preview),
      sourceWidth: info.width,
      sourceHeight: info.height,
      sourceFrameCount: composed.length,
    );
  }

  /// Applies one crop to every composed frame and reduces the result to both
  /// conversion modes.
  static AnimationConversionResult convert(
    Uint8List bytes,
    NormalizedCrop crop,
  ) {
    final info = inspectSource(bytes);
    final frames = _composeFrames(bytes, info);

    final rect = crop.toRect(info.width, info.height);

    final pixelArt = <TimedGrid>[];
    final photo = <TimedGrid>[];
    final modeVotes = <ImageConversionMode>[];
    final sampleStride = math.max(1, frames.length ~/ _modeSampleFrames);

    for (var i = 0; i < frames.length; i++) {
      // Cropped one frame at a time, never once over a whole animation:
      // copyCrop clones frame 0's palette onto every destination frame, so a
      // paletted animation would come back remapped through the wrong table.
      //
      // Converting after the crop matters too - copyResize refuses to
      // interpolate palette indices, so a paletted frame would silently drop
      // Photo mode back to nearest-neighbour.
      final source = img
          .copyCrop(
            frames[i].image,
            x: rect.x,
            y: rect.y,
            width: rect.size,
            height: rect.size,
          )
          .convert(numChannels: 4, noAnimation: true);
      final duration = frames[i].durationMs;

      pixelArt.add(
        TimedGrid(
          pixels: EditorImageConverter.toPixelArt(source),
          durationMs: duration,
        ),
      );
      photo.add(
        TimedGrid(
          pixels: EditorImageConverter.toPhoto(source),
          durationMs: duration,
        ),
      );
      if (i % sampleStride == 0) {
        modeVotes.add(EditorImageConverter.suggestMode(source));
      }
    }

    return AnimationConversionResult(
      pixelArt: AnimationFrameTimeline.build(pixelArt),
      photo: AnimationFrameTimeline.build(photo),
      // Pixel art only wins if every sampled frame looks like pixel art; one
      // photographic frame is enough to make the smooth pass the better bet.
      suggestedMode: modeVotes.every((m) => m == ImageConversionMode.pixelArt)
          ? ImageConversionMode.pixelArt
          : ImageConversionMode.photo,
      sourceWidth: info.width,
      sourceHeight: info.height,
      cropSize: rect.size,
    );
  }

  /// Complete canvas-sized frames in playback order, each with the duration
  /// the source asked for.
  ///
  /// `image` 4.9.2 does not get this right on its own for two of the three
  /// formats, so each one takes the shortest correct path rather than a single
  /// shared call - see [_composeGif] and [_composeWebP].
  static List<ComposedFrame> _composeFrames(
    Uint8List bytes,
    AnimationSourceInfo info,
  ) {
    final frames = switch (info.format) {
      img.ImageFormat.gif => _composeGif(bytes),
      img.ImageFormat.webp => _composeWebP(bytes),
      img.ImageFormat.png => _composeApng(bytes),
      _ => const <ComposedFrame>[],
    };

    if (frames.isEmpty) {
      throw const ImageImportFailure(
        'This file is corrupted or could not be decoded.',
      );
    }
    if (frames.length < 2) {
      throw const ImageImportFailure(
        'This file holds a single frame. Choose an animated GIF, WebP, or '
        'APNG - picking a still from the photo library can flatten one.',
      );
    }
    return frames;
  }

  /// Composes GIF frames onto a persistent canvas.
  ///
  /// `decodeGif` cannot be used for this: it only carries the previous frame
  /// forward when a frame ships its own local colour table, so an optimised
  /// GIF that shares the global table comes back as a stack of disconnected
  /// patches on black. Composing here also keeps disposal honest - restore to
  /// background clears just the frame's own rectangle, and restore to previous
  /// rewinds to the canvas as it stood before the frame was drawn.
  static List<ComposedFrame> _composeGif(Uint8List bytes) {
    final decoder = img.GifDecoder();
    final info = decoder.startDecode(bytes);
    if (info == null) return const [];

    var canvas = img.Image(
      width: info.width,
      height: info.height,
      numChannels: 4,
    );
    final composed = <ComposedFrame>[];

    for (var i = 0; i < info.numFrames; i++) {
      final desc = info.frames[i];
      final raw = decoder.decodeFrame(i);
      if (raw == null) return const [];

      final restorePoint = desc.disposal == 3
          ? img.Image.from(canvas, noAnimation: true)
          : null;

      for (final pixel in raw) {
        if (pixel.a == 0) continue; // transparent index leaves the canvas be
        final x = pixel.x + desc.x;
        final y = pixel.y + desc.y;
        if (x < 0 || y < 0 || x >= canvas.width || y >= canvas.height) continue;
        canvas.setPixelRgba(x, y, pixel.r, pixel.g, pixel.b, pixel.a);
      }

      composed.add(
        ComposedFrame(
          image: img.Image.from(canvas, noAnimation: true),
          // GIF stores delays in hundredths of a second.
          durationMs: desc.duration * 10,
        ),
      );

      if (desc.disposal == 2) {
        _clearRect(canvas, desc.x, desc.y, desc.width, desc.height);
      } else if (restorePoint != null) {
        canvas = restorePoint;
      }
    }

    return composed;
  }

  /// WebP composition is correct in the library; the per-frame durations are
  /// not - every composed frame ends up carrying frame 0's duration - so the
  /// timings are read back off the frame table instead.
  static List<ComposedFrame> _composeWebP(Uint8List bytes) {
    final decoder = img.WebPDecoder();
    final decoded = decoder.decode(bytes);
    final info = decoder.info;
    if (decoded == null || info == null) return const [];

    return [
      for (var i = 0; i < decoded.numFrames; i++)
        ComposedFrame(
          image: decoded.frames[i],
          durationMs: i < info.frames.length
              ? info.frames[i].duration
              : decoded.frames[i].frameDuration,
        ),
    ];
  }

  static List<ComposedFrame> _composeApng(Uint8List bytes) {
    final decoded = img.decodePng(bytes);
    if (decoded == null) return const [];
    return [
      for (final frame in decoded.frames)
        ComposedFrame(image: frame, durationMs: frame.frameDuration),
    ];
  }

  static void _clearRect(
    img.Image canvas,
    int x,
    int y,
    int width,
    int height,
  ) {
    for (var row = y; row < y + height; row++) {
      if (row < 0 || row >= canvas.height) continue;
      for (var column = x; column < x + width; column++) {
        if (column < 0 || column >= canvas.width) continue;
        canvas.setPixelRgba(column, row, 0, 0, 0, 0);
      }
    }
  }
}

/// One fully composed source frame and how long it stays on screen.
class ComposedFrame {
  final img.Image image;
  final int durationMs;

  const ComposedFrame({required this.image, required this.durationMs});
}
