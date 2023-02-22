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

Future<Uri?> buildNativeAssetsAndroid({
  required Iterable<AndroidArch> androidArchs,
  required Uri projectUri,
  PackageConfig? packageConfig,
}) async {
  // TODO(dacoharkes): Use packageConfig instead of reparsing it.

  final Uri flutterDartUri =
      globals.fs.directory(Cache.flutterRoot).uri.resolve('bin/dart');
  final List<Target> targets = androidArchs.map(_getNativeTarget).toList();

  logger.printStatus('Building native assets for $targets.');
  final List<Asset> nativeAssets = <Asset>[
    for (final Target target in targets)
      ...await NativeAssetsBuildRunner(
        logger: loggingLogger,
    dartExecutable: flutterDartUri,
      ).build(
        linkModePreference: LinkModePreference.dynamic,
        target: target,
        workingDirectory: projectUri,
        includeParentEnvironment: true,
      )
  ];
  logger.printStatus('Building native assets for $targets done.');
  // Installing is done in CMake for linux, so we can only combine all
  // native assets in a folder such that we don't have to worry about
  // the actual list of files in the native build.
  final Map<Asset, Asset> assetTargetLocations = <Asset, Asset>{
    for (final Asset asset in nativeAssets)
      asset: _targetLocationAndroid(asset),
  };
  if (nativeAssets.isNotEmpty) {
    // TODO(dacoharkes): Add output folder parameter to build instead.
    final Uri outputUri =
        projectUri.resolve('build/native_assets/jniLibs/lib/');
    logger.printStatus('Copying native assets to ${outputUri.toFilePath()}.');
    for (final MapEntry<Asset, Asset> assetMapping
        in assetTargetLocations.entries) {
      if (assetMapping.key != assetMapping.value) {
        final io.File file =
            io.File.fromUri((assetMapping.key.path as AssetAbsolutePath).uri);
        final String jniArchDir = _architectureStringsCMakeAndroid[
            assetMapping.value.target.architecture]!;
        await file.copy(outputUri
            .resolve(jniArchDir)
            .resolveUri((assetMapping.value.path as AssetAbsolutePath).uri)
            .toFilePath());
      }
    }

    logger.printStatus('Copying native assets done.');
  }
  logger.printStatus('Writing native_assets.yaml.');
  final Iterable<Asset> nativeAssetsMappingUsed = assetTargetLocations.values;
  final String nativeAssetsDartContents =
      nativeAssetsMappingUsed.toNativeAssetsFile();
  final Uri nativeAssetsParentUri = projectUri.resolve(
      'build/native_assets/android_${targets.map((Target t) => t.architecture.dartPlatform).join('_')}/');
  final Directory nativeAssetsDirectory =
      globals.fs.directory(nativeAssetsParentUri);
  await nativeAssetsDirectory.create(recursive: true);
  final Uri nativeAssetsUri =
      nativeAssetsParentUri.resolve('native_assets.yaml');
  final File nativeAssetsFile = globals.fs.file(nativeAssetsUri);
  await nativeAssetsFile.writeAsString(nativeAssetsDartContents);
  logger.printStatus('Writing ${nativeAssetsFile.path} done.');
  return nativeAssetsUri;
}

/// Extract the [Target] from an [AndroidArch].
Target _getNativeTarget(AndroidArch androidArch) {
  switch (androidArch) {
    case AndroidArch.armeabi_v7a:
      return Target.androidArm;
    case AndroidArch.arm64_v8a:
      return Target.androidArm64;
    case AndroidArch.x86:
      return Target.androidIA32;
    case AndroidArch.x86_64:
      return Target.androidX64;
  }
}

Asset _targetLocationAndroid(Asset asset) {
  final AssetPath path = asset.path;
  switch (path.runtimeType) {
    case AssetSystemPath:
    case AssetInExecutable:
    case AssetInProcess:
      return asset;
    case AssetAbsolutePath:
      final String fileName = (path as AssetAbsolutePath).uri.pathSegments.last;
      return asset.copyWith(path: AssetAbsolutePath(Uri(path: fileName)));
  }
  // ignore: only_throw_errors
  throw 'Unsupported asset path type ${path.runtimeType} in asset $asset';
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

const Map<Architecture, String> _architectureStringsCMakeAndroid =
    <Architecture, String>{
  Architecture.arm: 'armeabi-v7a',
  Architecture.arm64: 'arm64-v8a',
  Architecture.ia32: 'x86',
  Architecture.x64: 'x86_64',
};
