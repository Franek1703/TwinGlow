import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_glow/core/models/asset_model.dart';
import 'package:twin_glow/services/firebase/asset_document.dart';

void main() {
  List<List<int>> grid(Map<int, int> pixels) {
    final g = AnimationFrameModel.emptyGrid();
    pixels.forEach((i, c) {
      g[i ~/ 16][i % 16] = 0xff000000 | c;
    });
    return g;
  }

  for (final animation in [false, true]) {
    test(
      '${animation ? 'animation' : 'image'} fixture matches Flutter writer and native firmware decoder',
      () {
        final asset = animation
            ? AssetModel(
                id: 'a',
                name: 'a',
                type: AssetType.animation,
                frames: [
                  AnimationFrameModel(
                    pixels: grid({0: 0xff0000}),
                    durationMs: 100,
                  ),
                  AnimationFrameModel(
                    pixels: grid({17: 0x00ff00}),
                    durationMs: 250,
                  ),
                ],
              )
            : AssetModel(
                id: 'a',
                name: 'a',
                type: AssetType.image,
                pixelData: grid({0: 0xff0000, 17: 0x00ff00}),
              );
        final written = {
          'type': animation ? 'ANIMATION' : 'IMAGE',
          ...buildAssetPixelFields(asset).values,
        };
        final fixture = jsonDecode(
          File(
            '../tests/fixtures/pairing-${animation ? 'animation' : 'image'}.json',
          ).readAsStringSync(),
        );
        expect(written, fixture);
      },
    );
  }
}
