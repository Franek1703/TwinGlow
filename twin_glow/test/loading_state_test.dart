import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:twin_glow/config/app_router.dart';
import 'package:twin_glow/core/models/asset_model.dart';
import 'package:twin_glow/core/models/device_model.dart';
import 'package:twin_glow/core/models/screen_model.dart';
import 'package:twin_glow/features/assets_library/cubit/assets_cubit.dart';
import 'package:twin_glow/features/device/cubit/devices_cubit.dart';
import 'package:twin_glow/features/pairing/cubit/pairing_cubit.dart';
import 'package:twin_glow/features/screens_playlist/cubit/screens_playlist_cubit.dart';

void main() {
  test('data states start in initial loading instead of an empty state', () {
    expect(DevicesState().isInitialLoading, isTrue);
    expect(AssetsState().isInitialLoading, isTrue);
    expect(ScreensPlaylistState().isInitialLoading, isTrue);
    expect(PairingState().isInitialLoading, isTrue);
  });

  test('loaded content remains available during a background refresh', () {
    final device = DeviceModel(
      id: 'device',
      name: 'TwinGlow',
      isOnline: true,
      hasSensor: true,
    );
    final screen = ScreenModel(id: 'screen', type: ScreenType.clock);
    final asset = AssetModel(id: 'asset', name: 'Heart', type: AssetType.image);

    final devices = DevicesState(
      devices: [device],
      activeDevice: device,
      hasLoaded: true,
    ).copyWith(isLoading: true);
    final screens = ScreensPlaylistState(
      screens: [screen],
      hasLoaded: true,
    ).copyWith(isLoading: true);
    final assets = AssetsState(
      myAssets: [asset],
      hasLoaded: true,
    ).copyWith(isLoading: true);

    expect(devices.isRefreshing, isTrue);
    expect(devices.activeDevice, same(device));
    expect(screens.isRefreshing, isTrue);
    expect(screens.screens, [screen]);
    expect(assets.isRefreshing, isTrue);
    expect(assets.myAssets, [asset]);
  });

  test('bottom tabs use persistent stateful navigation branches', () {
    final shellRoutes = appRouter.configuration.routes
        .whereType<StatefulShellRoute>()
        .toList();

    expect(shellRoutes, hasLength(1));
    expect(shellRoutes.single.branches, hasLength(3));
  });
}
