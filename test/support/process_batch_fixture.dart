import 'dart:convert';
import 'dart:io';

final processBatchFixture =
    jsonDecode(File('test/fixtures/process_batch.json').readAsStringSync())
        as Map<String, dynamic>;
final processBatchEnvelope = processBatchFixture['batch'] as String;
