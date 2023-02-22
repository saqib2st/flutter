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

Future<NativeAssetsMacosResult?> buildNativeAssetsMacOS({
  required DarwinArch darwinArch,
  required Uri projectUri,
  PackageConfig? packageConfig,
}) async {
  // TODO(dacoharkes): Use packageConfig instead of reparsing it.

  final Logger logger = globals.logger;

  final Uri flutterDartUri =
      globals.fs.directory(Cache.flutterRoot).uri.resolve('bin/dart');

  final Target target = _getNativeTarget(darwinArch);
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

  // Installing is done in CMake for MacOS, so we can only combine all
  // native assets in a folder such that we don't have to worry about
  // the actual list of files in the native build.
  final Map<Asset, Asset> assetTargetLocations = <Asset, Asset>{
    for (final Asset asset in nativeAssets) asset: _targetLocationMacOS(asset),
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
  final Iterable<Asset> nativeAssetsMappingUsed = assetTargetLocations.values;
  final String nativeAssetsDartContents =
      nativeAssetsMappingUsed.toNativeAssetsFile();
  final Directory nativeAssetsDirectory = globals.fs.directory(buildUri);
  await nativeAssetsDirectory.create(recursive: true);
  final Uri nativeAssetsUri = buildUri.resolve('native_assets.yaml');
  final File nativeAssetsFile =
      globals.fs.file(buildUri.resolve('native_assets.yaml'));
  await nativeAssetsFile.writeAsString(nativeAssetsDartContents);
  logger.printStatus('Writing ${nativeAssetsFile.path} done.');

  logger.printStatus('Writing native_assets.podspec.');
  final String nativeAssetsPodspecContents = podspecContents(<Uri>[
    for (final Asset asset in nativeAssetsMappingUsed)
      if (asset.path is AssetAbsolutePath)
        (asset.path as AssetAbsolutePath).uri,
  ]);
  final Uri nativeAssetsPodspecUri = buildUri.resolve('native_assets.podspec');
  final File nativeAssetsPodspecFile =
      globals.fs.file(buildUri.resolve('native_assets.podspec'));
  await nativeAssetsPodspecFile.writeAsString(nativeAssetsPodspecContents);
  logger.printStatus('Writing ${nativeAssetsPodspecFile.path} done.');

  return NativeAssetsMacosResult(nativeAssetsUri, nativeAssetsPodspecUri);
}

class NativeAssetsMacosResult {
  NativeAssetsMacosResult(this.yamlUri, this.podspecUri);

  final Uri yamlUri;
  final Uri podspecUri;
}

/// Extract the [Target] from a [DarwinArch].
Target _getNativeTarget(DarwinArch darwinArch) {
  switch (darwinArch) {
    case DarwinArch.arm64:
      return Target.macOSArm64;
    case DarwinArch.x86_64:
      return Target.macOSX64;
    case DarwinArch.armv7:
      throw Exception('Unknown DarwinArch: $darwinArch.');
  }
}

Asset _targetLocationMacOS(Asset asset) {
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
  throw Exception(
      'Unsupported asset path type ${path.runtimeType} in asset $asset');
}

String podspecContents(List<Uri> vendoredLibraries) => '''
#
# NOTE: This podspec is NOT to be published. It is only used as a local source!
#       This is a generated file; do not edit or check into version control.
#

Pod::Spec.new do |s|
  s.name             = 'NativeAssets'
  s.version          = '1.0.0'
  s.summary          = 'A UI toolkit for beautiful and fast apps.'
  s.homepage         = 'https://flutter.dev'
  s.license          = { :type => 'BSD' }
  s.author           = { 'Flutter Dev Team' => 'flutter-dev@googlegroups.com' }
  s.source           = { :git => 'https://github.com/flutter/engine', :tag => s.version.to_s }
  s.osx.deployment_target = '10.14'
  s.vendored_libraries = ${vendoredLibraries.map((Uri l) => "'${l.path}'").join(', ')}
end
''';

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
