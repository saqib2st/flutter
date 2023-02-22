// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:logging/logging.dart' as logging;
import 'package:native_assets_builder/native_assets_builder.dart';
import 'package:native_assets_cli/native_assets_cli.dart';

import '../base/file_system.dart';
import '../base/logger.dart';
import '../cache.dart';
import '../globals.dart' as globals;

Future<Uri?> buildNativeAssetsHost({
  required Uri projectUri,
}) async {
  final Logger logger = globals.logger;

  final Uri flutterDartUri =
      globals.fs.directory(Cache.flutterRoot).uri.resolve('bin/dart');

  final Target target = Target.current;
  final List<Target> targets = <Target>[
    target,
    // We're running some executables on x64 mode currently.
    if (target == Target.macOSArm64) Target.macOSX64,
  ];
  final Uri buildUri = projectUri.resolve('build/native_assets/$target/');

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

  logger.printStatus('Writing native_assets.yaml.');
  final Iterable<Asset> nativeAssetsMappingUsed = nativeAssets;
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
