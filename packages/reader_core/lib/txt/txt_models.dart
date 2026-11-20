import 'dart:io';

const txtMetadataPath = 'OEBPS/spectacular-txt.json';
const txtMetadataManifestId = 'spectacular-txt-info';
const txtIdentifierPrefix = 'urn:spectacular:txt:sha256:';

/// 正则只决定目录边界，不修改命中的原文。
class ChapterRule {
  const ChapterRule({
    required this.id,
    required this.name,
    required this.pattern,
    this.volumePattern,
    this.caseSensitive = true,
    this.autoEnabled = false,
  });

  final String id;
  final String name;
  final String pattern;
  final String? volumePattern;
  final bool caseSensitive;
  final bool autoEnabled;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'pattern': pattern,
    'volumePattern': volumePattern,
    'caseSensitive': caseSensitive,
    'autoEnabled': autoEnabled,
  };

  factory ChapterRule.fromJson(Map<String, dynamic> json) => ChapterRule(
    id: json['id'] as String,
    name: json['name'] as String,
    pattern: json['pattern'] as String,
    volumePattern: json['volumePattern'] as String?,
    caseSensitive: json['caseSensitive'] as bool? ?? true,
    autoEnabled: json['autoEnabled'] as bool? ?? false,
  );
}

enum ChapterDetectionMode { auto, custom, length }

class ChapterDetectionOptions {
  const ChapterDetectionOptions({
    this.mode = ChapterDetectionMode.auto,
    this.rule,
    this.autoRules = const [],
  });

  final ChapterDetectionMode mode;
  final ChapterRule? rule;
  final List<ChapterRule> autoRules;

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'rule': rule?.toJson(),
    'autoRules': autoRules.map((rule) => rule.toJson()).toList(),
  };

  factory ChapterDetectionOptions.fromJson(Map<String, dynamic> json) =>
      ChapterDetectionOptions(
        mode: ChapterDetectionMode.values.byName(json['mode'] as String),
        rule: json['rule'] == null
            ? null
            : ChapterRule.fromJson(json['rule'] as Map<String, dynamic>),
        autoRules: [
          for (final rule in json['autoRules'] as List? ?? const [])
            ChapterRule.fromJson(rule as Map<String, dynamic>),
        ],
      );
}

/// [blockIndex] 指向调用方提供的逻辑块；长度切分不拆开块内部结构。
class ChapterBoundary {
  const ChapterBoundary({
    required this.blockIndex,
    required this.title,
    this.isVolume = false,
    this.synthetic = false,
  });

  final int blockIndex;
  final String title;
  final bool isVolume;
  final bool synthetic;
}

class ChapterDetectionResult {
  const ChapterDetectionResult({
    required this.boundaries,
    required this.warnings,
    required this.blockCount,
    required this.totalLength,
  });

  final List<ChapterBoundary> boundaries;
  final List<String> warnings;
  final int blockCount;
  final int totalLength;
}

class TxtEncodingCandidate {
  const TxtEncodingCandidate({required this.name, required this.sample});
  final String name;
  final String sample;
}

class TxtConversionException implements Exception {
  const TxtConversionException(
    this.code,
    this.message, {
    this.encodingCandidates = const [],
  });

  final String code;
  final String message;
  final List<TxtEncodingCandidate> encodingCandidates;

  @override
  String toString() => message;
}

class TxtConversionResult {
  const TxtConversionResult({
    required this.filePath,
    required this.sourceDigest,
    required this.encoding,
    required this.detection,
  });

  final String filePath;
  File get file => File(filePath);
  final String sourceDigest;
  final String encoding;
  String get identifier => '$txtIdentifierPrefix$sourceDigest';
  final ChapterDetectionResult detection;
}
