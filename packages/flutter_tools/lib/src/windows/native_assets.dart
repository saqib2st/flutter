// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io' as io;

import 'package:logging/logging.dart' as logging;
import 'package:native_assets_builder/native_assets_builder.dart';
import 'package:native_assets_cli/native_assets_cli.dart';
import 'package:package_config/package_config.dart';

import '../base/file_system.dart';
import '../base/logger.dart';
import '../build_info.dart';
import '../cache.dart';
import '../globals.dart' as globals;

Future<Uri?> buildNativeAssetsWindows({
  required TargetPlatform targetPlatform,
  required Uri projectUri,
  PackageConfig? packageConfig,
}) async {
  // TODO(dacoharkes): Use packageConfig instead of reparsing it.

  final Logger logger = globals.logger;

  final Uri flutterDartUri =
      globals.fs.directory(Cache.flutterRoot).uri.resolve('bin/dart.bat');

  final Target target = _getNativeTarget(targetPlatform);
  final Uri buildUri = projectUri.resolve('build/native_assets/$target/');

  logger.printStatus('Building native assets for $target.');
  final List<Asset> nativeAssets = await NativeAssetsBuildRunner(
    logger: loggingLogger,
    dartExecutable: flutterDartUri,
  ).build(
    linkModePreference: LinkModePreference.dynamic,
    target: target,
    workingDirectory: projectUri,
    includeParentEnvironment: true,
  );
  logger.printStatus('Building native assets for $target done.');

  // Installing is done in CMake for windows, so we can only combine all
  // native assets in a folder such that we don't have to worry about
  // the actual list of files in the native build.
  final Map<Asset, Asset> assetTargetLocations = <Asset, Asset>{
    for (final Asset asset in nativeAssets)
      asset: _targetLocationWindows(asset),
  };
  if (nativeAssets.isNotEmpty) {
    logger.printStatus('Copying native assets to ${buildUri.toFilePath()}.');
    for (final MapEntry<Asset, Asset> assetMapping
        in assetTargetLocations.entries) {
      if (assetMapping.key != assetMapping.value) {
        final io.File file =
            io.File.fromUri((assetMapping.key.path as AssetAbsolutePath).uri);
        await file.copy(buildUri
            .resolveUri((assetMapping.value.path as AssetAbsolutePath).uri)
            .toFilePath());
      }
    }
    logger.printStatus('Copying native assets done.');
  }

  logger.printStatus('Writing native_assets.yaml.');
  final Iterable<Asset> nativeAssetsMappingUsed =
      assetTargetLocations.values;
  final String nativeAssetsDartContents =
      nativeAssetsMappingUsed.toNativeAssetsFile();
  final Directory nativeAssetsDirectory = globals.fs.directory(buildUri);
  await nativeAssetsDirectory.create(recursive: true);
  final Uri nativeAssetsUri = buildUri.resolve('native_assets.yaml');
  final File nativeAssetsFile =
      globals.fs.file(buildUri.resolve('native_assets.yaml'));
  await nativeAssetsFile.writeAsString(nativeAssetsDartContents);
  logger.printStatus('Writing ${nativeAssetsFile.path} done.');

  return nativeAssetsUri;
}

/// Extract the [Target] from a [TargetPlatform].
Target _getNativeTarget(TargetPlatform targetPlatform) {
  switch (targetPlatform) {
    case TargetPlatform.windows_x64:
      return Target.windowsX64;
    case TargetPlatform.android_arm:
    case TargetPlatform.android_arm64:
    case TargetPlatform.android_x64:
    case TargetPlatform.android_x86:
    case TargetPlatform.android:
    case TargetPlatform.darwin:
    case TargetPlatform.fuchsia_arm64:
    case TargetPlatform.fuchsia_x64:
    case TargetPlatform.ios:
    case TargetPlatform.linux_arm64:
    case TargetPlatform.linux_x64:
    case TargetPlatform.tester:
    case TargetPlatform.web_javascript:
      throw Exception('Unknown targetPlatform: $targetPlatform.');
  }
}

Asset _targetLocationWindows(Asset asset) {
  final AssetPath path = asset.path;
  switch (path.runtimeType) {
    case AssetSystemPath:
    case AssetInExecutable:
    case AssetInProcess:
      return asset;
    case AssetAbsolutePath:
      final String fileName =
          (path as AssetAbsolutePath).uri.pathSegments.last;
      return asset.copyWith(path: AssetAbsolutePath(Uri(path: fileName))
      );
  }
  throw Exception(
      'Unsupported asset path type ${path.runtimeType} in asset $asset');
}

final Logger logger = globals.logger;

final logging.Logger loggingLogger = logging.Logger('')
  ..onRecord.listen((logging.LogRecord record) {
    final int levelValue = record.level.value;
    final String message = record.message;
    if (levelValue >= logging.Level.SEVERE.value) {
      logger.printError(message);
    } else if (levelValue >= logging.Level.WARNING.value) {
      logger.printWarning(message);
    } else if (levelValue >= logging.Level.INFO.value) {
      logger.printStatus(message);
    } else {
      logger.printTrace(message);
    }
  });
