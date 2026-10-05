# ARCH_DOWNLOAD_FILE_VALUE

The canonical RemoteFileDownload is final; its final Uint8List bytes are captured
by the single unnamed constructor using
`Uint8List.fromList(bytes).asUnmodifiableView()`. The previous copied list still
allowed consumers to modify published file facts. Copies isolate producer edits;
the read-only view prevents consumer edits. The ordinary file client regression
checks both across the public constructor.

This finite AST construction contract accepts the current explicit SDK spelling,
not arbitrary equivalent factories/aliases or inferred immutability. Renaming or
changing the value requires updating this contract. It does not resolve arbitrary
SDK symbol shadowing, analyze all DTOs or establish remote/native resource safety;
ordinary analysis validates actual names/types, and the public behavior test is
required. Missing/ambiguous/parts/conditional scope exits2, findings1, valid0.
Run `dart run tools/architecture/rules/download_file_value.dart --json`.
