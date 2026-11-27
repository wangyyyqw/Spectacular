import 'dart:convert';

import '../library/library_store.dart';
import 'dictionary_rule.dart';
import 'local_dictionary_store.dart';

class DictionaryApi {
  const DictionaryApi({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.enabled = true,
  });
  final String id, name, baseUrl, apiKey, model;
  final bool enabled;
  String get label => name.isEmpty ? model : name;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': model,
    'enabled': enabled,
  };
  factory DictionaryApi.fromJson(Map<String, dynamic> json) => DictionaryApi(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    baseUrl: json['baseUrl'] as String,
    apiKey: json['apiKey'] as String,
    model: json['model'] as String,
    enabled: json['enabled'] != false,
  );
}

class DictionaryPreset {
  const DictionaryPreset(
    this.id,
    this.name,
    this.prompt, {
    this.builtIn = false,
  });
  final String id, name, prompt;
  final bool builtIn;
  Map<String, Object?> toJson() => {'id': id, 'name': name, 'prompt': prompt};
  String render(String text) => prompt.contains('{{text}}')
      ? prompt.trim().replaceAll('{{text}}', text.trim())
      : '${prompt.trim()}\n\n「${text.trim()}」';
}

const dictionaryBuiltInPresets = [
  DictionaryPreset(
    'dictionary_short',
    '词典释义',
    '请简洁地解释「{{text}}」的含义。',
    builtIn: true,
  ),
  DictionaryPreset(
    'dictionary_encyclopedia',
    '详细百科',
    '请详细介绍「{{text}}」，包括定义、背景、相关知识。',
    builtIn: true,
  ),
  DictionaryPreset(
    'dictionary_classical',
    '文言文/古诗词',
    '请解释「{{text}}」在古文中的含义，包括出处和用法。',
    builtIn: true,
  ),
];

class DictionarySettings {
  const DictionarySettings({
    this.apiId = '',
    this.presetId = 'dictionary_short',
    this.disableThinking = true,
    this.singleUsePreset = true,
    this.sourceId = '',
  });
  final String apiId, presetId, sourceId;
  final bool disableThinking, singleUsePreset;
  DictionarySettings copyWith({
    String? apiId,
    String? presetId,
    bool? disableThinking,
    bool? singleUsePreset,
    String? sourceId,
  }) => DictionarySettings(
    apiId: apiId ?? this.apiId,
    presetId: presetId ?? this.presetId,
    disableThinking: disableThinking ?? this.disableThinking,
    singleUsePreset: singleUsePreset ?? this.singleUsePreset,
    sourceId: sourceId ?? this.sourceId,
  );
  Map<String, Object?> toJson() => {
    'apiId': apiId,
    'presetId': presetId,
    'disableThinking': disableThinking,
    'singleUsePreset': singleUsePreset,
    'sourceId': sourceId,
  };
}

class DictionaryState {
  const DictionaryState({
    this.apis = const [],
    this.customPresets = const [],
    this.rules = const [],
    this.settings = const DictionarySettings(),
  });
  final List<DictionaryApi> apis;
  final List<DictionaryPreset> customPresets;
  final List<DictionaryRule> rules;
  final DictionarySettings settings;
  List<DictionaryPreset> get presets => [
    ...dictionaryBuiltInPresets,
    ...customPresets,
  ];
  DictionaryPreset get preset =>
      presets.where((p) => p.id == settings.presetId).firstOrNull ??
      presets.first;
  DictionaryApi? get api =>
      apis.where((a) => a.id == settings.apiId && a.enabled).firstOrNull ??
      apis.where((a) => a.enabled).firstOrNull;
  DictionaryState copyWith({
    List<DictionaryApi>? apis,
    List<DictionaryPreset>? customPresets,
    List<DictionaryRule>? rules,
    DictionarySettings? settings,
  }) => DictionaryState(
    apis: apis ?? this.apis,
    customPresets: customPresets ?? this.customPresets,
    rules: rules ?? this.rules,
    settings: settings ?? this.settings,
  );
}

/// 复用本机应用设置，不把密钥写入诊断或阅读同步记录。
class DictionaryStore {
  DictionaryStore(this.library, {LocalDictionaryStore? localDictionaries})
    : locals = localDictionaries ?? LocalDictionaryStore(library);
  final LibraryStore library;
  final LocalDictionaryStore locals;
  static const settingKey = 'dictionary.v1';
  static const _removedBuiltInRuleIds = {
    'builtin-baike',
    'builtin-zdic-cidian',
    'builtin-xinhua',
    'builtin-hanyuguoxue',
    'builtin-hao86',
  };
  static final _queues = Expando<Future<void>>();
  Future<void> get _writes => _queues[library] ?? Future<void>.value();

  Future<DictionaryState> load() async {
    await _writes;
    return _read();
  }

  Future<DictionaryState> _read() async {
    final raw = await library.getSetting(settingKey);
    if (raw == null || raw.isEmpty) {
      return DictionaryState(rules: _mergeBuiltInRules(const []));
    }
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final settings = json['settings'] as Map<String, dynamic>? ?? {};
    final sourceId = settings['sourceId'] as String? ?? '';
    return DictionaryState(
      apis: [
        for (final item in json['apis'] as List? ?? [])
          DictionaryApi.fromJson(item as Map<String, dynamic>),
      ],
      customPresets: [
        for (final item
            in (json['presets'] as List? ?? []).cast<Map<String, Object?>>())
          DictionaryPreset(
            item['id'] as String,
            item['name'] as String,
            item['prompt'] as String,
          ),
      ],
      rules: _mergeBuiltInRules([
        for (final item in json['rules'] as List? ?? [])
          DictionaryRule.fromJson(Map<String, dynamic>.from(item as Map)),
      ]),
      settings: DictionarySettings(
        apiId: settings['apiId'] as String? ?? '',
        presetId: settings['presetId'] as String? ?? 'dictionary_short',
        disableThinking: settings['disableThinking'] != false,
        singleUsePreset: settings['singleUsePreset'] != false,
        sourceId: _removedBuiltInRuleIds.any((id) => sourceId == 'rule:$id')
            ? ''
            : sourceId,
      ),
    );
  }

  static List<DictionaryRule> _mergeBuiltInRules(List<DictionaryRule> saved) {
    final byId = {for (final rule in saved) rule.id: rule};
    return [
      for (final rule in dictionaryBuiltInRules)
        rule.copyWith(enabled: byId[rule.id]?.enabled ?? rule.enabled),
      for (final rule in saved)
        if (!_removedBuiltInRuleIds.contains(rule.id) &&
            !dictionaryBuiltInRules.any((builtIn) => builtIn.id == rule.id))
          rule,
    ];
  }

  Future<void> _update(DictionaryState Function(DictionaryState) change) {
    final task = _writes.then((_) async {
      final next = change(await _read());
      await library.setSetting(
        settingKey,
        jsonEncode({
          'v': 1,
          'apis': next.apis.map((a) => a.toJson()).toList(),
          'presets': next.customPresets.map((p) => p.toJson()).toList(),
          'rules': next.rules.map((r) => r.toJson()).toList(),
          'settings': next.settings.toJson(),
        }),
      );
    });
    _queues[library] = task.catchError((Object _) {});
    return task;
  }

  Future<void> saveApi(DictionaryApi api) {
    final uri = Uri.tryParse(api.baseUrl.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty ||
        api.apiKey.trim().isEmpty ||
        api.model.trim().isEmpty) {
      throw const FormatException('请填写有效的服务地址、API Key 和模型');
    }
    return _update(
      (s) => s.copyWith(
        apis: [
          for (final a in s.apis)
            if (a.id != api.id) a,
          api,
        ],
      ),
    );
  }

  Future<void> removeApi(String id) => _update(
    (s) => s.copyWith(
      apis: s.apis.where((a) => a.id != id).toList(),
      settings: s.settings.apiId == id
          ? s.settings.copyWith(apiId: '')
          : s.settings,
    ),
  );

  Future<void> saveRule(DictionaryRule rule) async {
    if (dictionaryBuiltInRules.any((builtIn) => builtIn.id == rule.id)) {
      throw const FormatException('内置规则不可编辑，可复制后修改');
    }
    validateDictionaryRule(rule);
    await _update((s) {
      if (s.rules.any((r) => r.id != rule.id && r.name == rule.name)) {
        throw const FormatException('已有同名在线词典');
      }
      return s.copyWith(
        rules: [
          for (final r in s.rules)
            if (r.id != rule.id) r,
          rule,
        ],
      );
    });
  }

  Future<void> saveRules(Iterable<DictionaryRule> rules) => _update((s) {
    final next = [...s.rules];
    for (final rule in rules) {
      final builtIn = dictionaryBuiltInRules.any(
        (builtIn) => builtIn.id == rule.id,
      );
      if (builtIn) {
        final index = next.indexWhere((r) => r.id == rule.id);
        if (index >= 0) {
          next[index] = next[index].copyWith(enabled: rule.enabled);
        }
        continue;
      }
      validateDictionaryRule(rule);
      if (next.any((r) => r.id != rule.id && r.name == rule.name)) {
        throw FormatException('已有同名在线词典：${rule.name}');
      }
      final index = next.indexWhere((r) => r.id == rule.id);
      if (index < 0) {
        next.add(rule);
      } else {
        next[index] = rule;
      }
    }
    return s.copyWith(rules: next);
  });

  Future<void> setRuleEnabled(String id, bool enabled) => _update(
    (s) => s.copyWith(
      rules: [
        for (final rule in s.rules)
          rule.id == id ? rule.copyWith(enabled: enabled) : rule,
      ],
    ),
  );

  Future<void> removeRule(String id) async {
    if (dictionaryBuiltInRules.any((rule) => rule.id == id)) {
      throw const FormatException('内置规则不能删除，可停用或复制后修改');
    }
    await _update(
      (s) => s.copyWith(
        rules: s.rules.where((rule) => rule.id != id).toList(),
        settings: s.settings.sourceId == 'rule:$id'
            ? s.settings.copyWith(sourceId: '')
            : s.settings,
      ),
    );
  }

  Future<void> savePreset(DictionaryPreset preset) {
    if (preset.name.trim().isEmpty || preset.prompt.trim().isEmpty) {
      throw const FormatException('预设名称和提示词不能为空');
    }
    if (dictionaryBuiltInPresets.any((p) => p.id == preset.id)) {
      throw const FormatException('请复制内置预设后编辑');
    }
    return _update(
      (s) => s.copyWith(
        customPresets: [
          for (final p in s.customPresets)
            if (p.id != preset.id) p,
          preset,
        ],
      ),
    );
  }

  Future<void> removePreset(String id) => _update(
    (s) => s.copyWith(
      customPresets: s.customPresets.where((p) => p.id != id).toList(),
      settings: s.settings.presetId == id
          ? s.settings.copyWith(presetId: 'dictionary_short')
          : s.settings,
    ),
  );

  Future<void> changeSettings(
    DictionarySettings Function(DictionarySettings) change,
  ) => _update((s) => s.copyWith(settings: change(s.settings)));
}
