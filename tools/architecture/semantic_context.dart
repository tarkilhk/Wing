import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/src/dart/analysis/file_byte_store.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:crypto/crypto.dart';

var _storeSequence = 0;

/// Standard analyzer summary storage, never rule results. Source, dependency,
/// language/options and summary-version validation remain analyzer-owned.
/// The installed analyzer's public collection API has no byteStore parameter.
AnalysisContextCollectionImpl semanticContextCollection({
  required String root,
  required String sdk,
  required List<String> includedPaths,
  required String cacheNamespace,
}) {
  root = Directory(root).resolveSymbolicLinksSync();
  final config = File('$root/.dart_tool/package_config.json');
  final binding = sha256.convert(
    utf8.encode(
      jsonEncode([
        root,
        Directory(sdk).resolveSymbolicLinksSync(),
        File('$sdk/version').readAsStringSync(),
        File('$sdk/lib/libraries.json').readAsStringSync(),
        config.existsSync() ? config.readAsStringSync() : null,
        if (File('$root/analysis_options.yaml').existsSync())
          File('$root/analysis_options.yaml').readAsStringSync(),
      ]),
    ),
  );
  final cache = Directory(
    '$root/.dart_tool/architecture/$cacheNamespace/$binding',
  );
  cache.createSync(recursive: true);
  // The pinned analyzer ignores collection enabledExperiments when discovering
  // options normally. Preserve that discovery and all physical options bytes.
  final provider = OverlayResourceProvider(PhysicalResourceProvider.INSTANCE);
  final optionsPath = '$root/analysis_options.yaml';
  var options = File(optionsPath).existsSync()
      ? File(optionsPath).readAsStringSync()
      : '';
  if (options.contains('enable-experiment:')) {
    throw const FormatException('Explicit experiment review required');
  }
  const header = 'analyzer:\n';
  const flags = '  enable-experiment:\n    - private-named-parameters\n';
  if (options.startsWith(header)) {
    options = '$header$flags${options.substring(header.length)}';
  } else if (options.contains('\n$header')) {
    options = options.replaceFirst('\n$header', '\n$header$flags');
  } else {
    options = '$options\n$header$flags';
  }
  provider.setOverlay(optionsPath, content: options, modificationStamp: 0);
  return AnalysisContextCollectionImpl(
    includedPaths: includedPaths,
    resourceProvider: provider,
    sdkPath: sdk,
    byteStore: FileByteStore(
      cache.path,
      tempNameSuffix: '$pid-${Isolate.current.hashCode}-${_storeSequence++}',
    ),
  );
}
