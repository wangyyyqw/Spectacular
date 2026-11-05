// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'db.dart';

// ignore_for_file: type=lint
class $BooksTable extends Books with TableInfo<$BooksTable, BookRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BooksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _uuidMeta = const VerificationMeta('uuid');
  @override
  late final GeneratedColumn<String> uuid = GeneratedColumn<String>(
    'uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _epubIdentifierMeta = const VerificationMeta(
    'epubIdentifier',
  );
  @override
  late final GeneratedColumn<String> epubIdentifier = GeneratedColumn<String>(
    'epub_identifier',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _identityVersionMeta = const VerificationMeta(
    'identityVersion',
  );
  @override
  late final GeneratedColumn<int> identityVersion = GeneratedColumn<int>(
    'identity_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _legacyUuidMeta = const VerificationMeta(
    'legacyUuid',
  );
  @override
  late final GeneratedColumn<String> legacyUuid = GeneratedColumn<String>(
    'legacy_uuid',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorMeta = const VerificationMeta('author');
  @override
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
    'author',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _languageMeta = const VerificationMeta(
    'language',
  );
  @override
  late final GeneratedColumn<String> language = GeneratedColumn<String>(
    'language',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contentDirMeta = const VerificationMeta(
    'contentDir',
  );
  @override
  late final GeneratedColumn<String> contentDir = GeneratedColumn<String>(
    'content_dir',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourcePathMeta = const VerificationMeta(
    'sourcePath',
  );
  @override
  late final GeneratedColumn<String> sourcePath = GeneratedColumn<String>(
    'source_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverPathMeta = const VerificationMeta(
    'coverPath',
  );
  @override
  late final GeneratedColumn<String> coverPath = GeneratedColumn<String>(
    'cover_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _spineCountMeta = const VerificationMeta(
    'spineCount',
  );
  @override
  late final GeneratedColumn<int> spineCount = GeneratedColumn<int>(
    'spine_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _charCountMeta = const VerificationMeta(
    'charCount',
  );
  @override
  late final GeneratedColumn<int> charCount = GeneratedColumn<int>(
    'char_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastReadAtMeta = const VerificationMeta(
    'lastReadAt',
  );
  @override
  late final GeneratedColumn<int> lastReadAt = GeneratedColumn<int>(
    'last_read_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _layoutVersionMeta = const VerificationMeta(
    'layoutVersion',
  );
  @override
  late final GeneratedColumn<int> layoutVersion = GeneratedColumn<int>(
    'layout_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _levelMeta = const VerificationMeta('level');
  @override
  late final GeneratedColumn<int> level = GeneratedColumn<int>(
    'level',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _warningsMeta = const VerificationMeta(
    'warnings',
  );
  @override
  late final GeneratedColumn<String> warnings = GeneratedColumn<String>(
    'warnings',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    uuid,
    epubIdentifier,
    identityVersion,
    legacyUuid,
    title,
    author,
    description,
    language,
    contentDir,
    sourcePath,
    coverPath,
    spineCount,
    charCount,
    createdAt,
    lastReadAt,
    layoutVersion,
    level,
    warnings,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'books';
  @override
  VerificationContext validateIntegrity(
    Insertable<BookRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('uuid')) {
      context.handle(
        _uuidMeta,
        uuid.isAcceptableOrUnknown(data['uuid']!, _uuidMeta),
      );
    } else if (isInserting) {
      context.missing(_uuidMeta);
    }
    if (data.containsKey('epub_identifier')) {
      context.handle(
        _epubIdentifierMeta,
        epubIdentifier.isAcceptableOrUnknown(
          data['epub_identifier']!,
          _epubIdentifierMeta,
        ),
      );
    }
    if (data.containsKey('identity_version')) {
      context.handle(
        _identityVersionMeta,
        identityVersion.isAcceptableOrUnknown(
          data['identity_version']!,
          _identityVersionMeta,
        ),
      );
    }
    if (data.containsKey('legacy_uuid')) {
      context.handle(
        _legacyUuidMeta,
        legacyUuid.isAcceptableOrUnknown(data['legacy_uuid']!, _legacyUuidMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('author')) {
      context.handle(
        _authorMeta,
        author.isAcceptableOrUnknown(data['author']!, _authorMeta),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('language')) {
      context.handle(
        _languageMeta,
        language.isAcceptableOrUnknown(data['language']!, _languageMeta),
      );
    }
    if (data.containsKey('content_dir')) {
      context.handle(
        _contentDirMeta,
        contentDir.isAcceptableOrUnknown(data['content_dir']!, _contentDirMeta),
      );
    } else if (isInserting) {
      context.missing(_contentDirMeta);
    }
    if (data.containsKey('source_path')) {
      context.handle(
        _sourcePathMeta,
        sourcePath.isAcceptableOrUnknown(data['source_path']!, _sourcePathMeta),
      );
    }
    if (data.containsKey('cover_path')) {
      context.handle(
        _coverPathMeta,
        coverPath.isAcceptableOrUnknown(data['cover_path']!, _coverPathMeta),
      );
    }
    if (data.containsKey('spine_count')) {
      context.handle(
        _spineCountMeta,
        spineCount.isAcceptableOrUnknown(data['spine_count']!, _spineCountMeta),
      );
    }
    if (data.containsKey('char_count')) {
      context.handle(
        _charCountMeta,
        charCount.isAcceptableOrUnknown(data['char_count']!, _charCountMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('last_read_at')) {
      context.handle(
        _lastReadAtMeta,
        lastReadAt.isAcceptableOrUnknown(
          data['last_read_at']!,
          _lastReadAtMeta,
        ),
      );
    }
    if (data.containsKey('layout_version')) {
      context.handle(
        _layoutVersionMeta,
        layoutVersion.isAcceptableOrUnknown(
          data['layout_version']!,
          _layoutVersionMeta,
        ),
      );
    }
    if (data.containsKey('level')) {
      context.handle(
        _levelMeta,
        level.isAcceptableOrUnknown(data['level']!, _levelMeta),
      );
    }
    if (data.containsKey('warnings')) {
      context.handle(
        _warningsMeta,
        warnings.isAcceptableOrUnknown(data['warnings']!, _warningsMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BookRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      uuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uuid'],
      )!,
      epubIdentifier: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}epub_identifier'],
      ),
      identityVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}identity_version'],
      )!,
      legacyUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}legacy_uuid'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      author: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author'],
      ),
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      language: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}language'],
      ),
      contentDir: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_dir'],
      )!,
      sourcePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_path'],
      ),
      coverPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_path'],
      ),
      spineCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}spine_count'],
      )!,
      charCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}char_count'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      lastReadAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_read_at'],
      ),
      layoutVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}layout_version'],
      )!,
      level: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}level'],
      )!,
      warnings: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}warnings'],
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $BooksTable createAlias(String alias) {
    return $BooksTable(attachedDatabase, alias);
  }
}

class BookRow extends DataClass implements Insertable<BookRow> {
  /// 主键。
  final int id;

  /// 固定算法生成的 32 位书籍标识；保留列名以兼容已有存储接口。
  final String uuid;

  /// EPUB 原始 unique-identifier，不使用书籍标识替换字体解混淆密钥。
  final String? epubIdentifier;

  /// 标识算法版本；0 表示等待从原书迁移，1 表示固定摘要算法。
  final int identityVersion;

  /// 迁移前标识，供旧进度文件解析及旧目录保护。
  final String? legacyUuid;

  /// 书名。
  final String title;

  /// 作者。
  final String? author;

  /// 用户可编辑的简介。
  final String? description;

  /// 语言。
  final String? language;

  /// 解包后的内容目录（`books/<uuid>/content`）。
  final String contentDir;

  /// 原始 EPUB 备份路径。
  final String? sourcePath;

  /// 封面缓存文件路径。
  final String? coverPath;

  /// spine 项数。
  final int spineCount;

  /// 全书字符数（进度算法用，§22.3）。
  final int charCount;

  /// 导入时间（毫秒）。
  final int createdAt;

  /// 最近阅读时间（毫秒）。
  final int? lastReadAt;

  /// 书级排版版本（§70.3）：算法变更时 +1，与 schema 版本无关。
  final int layoutVersion;

  /// 可读性分级 L0～L4（§55.2）。
  final int level;

  /// 导入修复与降级摘要（JSON 数组）。
  final String? warnings;

  /// 从书架移除的时间（毫秒）；非空时保留用户数据但不对书架展示。
  final int? deletedAt;
  const BookRow({
    required this.id,
    required this.uuid,
    this.epubIdentifier,
    required this.identityVersion,
    this.legacyUuid,
    required this.title,
    this.author,
    this.description,
    this.language,
    required this.contentDir,
    this.sourcePath,
    this.coverPath,
    required this.spineCount,
    required this.charCount,
    required this.createdAt,
    this.lastReadAt,
    required this.layoutVersion,
    required this.level,
    this.warnings,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['uuid'] = Variable<String>(uuid);
    if (!nullToAbsent || epubIdentifier != null) {
      map['epub_identifier'] = Variable<String>(epubIdentifier);
    }
    map['identity_version'] = Variable<int>(identityVersion);
    if (!nullToAbsent || legacyUuid != null) {
      map['legacy_uuid'] = Variable<String>(legacyUuid);
    }
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || author != null) {
      map['author'] = Variable<String>(author);
    }
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || language != null) {
      map['language'] = Variable<String>(language);
    }
    map['content_dir'] = Variable<String>(contentDir);
    if (!nullToAbsent || sourcePath != null) {
      map['source_path'] = Variable<String>(sourcePath);
    }
    if (!nullToAbsent || coverPath != null) {
      map['cover_path'] = Variable<String>(coverPath);
    }
    map['spine_count'] = Variable<int>(spineCount);
    map['char_count'] = Variable<int>(charCount);
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || lastReadAt != null) {
      map['last_read_at'] = Variable<int>(lastReadAt);
    }
    map['layout_version'] = Variable<int>(layoutVersion);
    map['level'] = Variable<int>(level);
    if (!nullToAbsent || warnings != null) {
      map['warnings'] = Variable<String>(warnings);
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    return map;
  }

  BooksCompanion toCompanion(bool nullToAbsent) {
    return BooksCompanion(
      id: Value(id),
      uuid: Value(uuid),
      epubIdentifier: epubIdentifier == null && nullToAbsent
          ? const Value.absent()
          : Value(epubIdentifier),
      identityVersion: Value(identityVersion),
      legacyUuid: legacyUuid == null && nullToAbsent
          ? const Value.absent()
          : Value(legacyUuid),
      title: Value(title),
      author: author == null && nullToAbsent
          ? const Value.absent()
          : Value(author),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      language: language == null && nullToAbsent
          ? const Value.absent()
          : Value(language),
      contentDir: Value(contentDir),
      sourcePath: sourcePath == null && nullToAbsent
          ? const Value.absent()
          : Value(sourcePath),
      coverPath: coverPath == null && nullToAbsent
          ? const Value.absent()
          : Value(coverPath),
      spineCount: Value(spineCount),
      charCount: Value(charCount),
      createdAt: Value(createdAt),
      lastReadAt: lastReadAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReadAt),
      layoutVersion: Value(layoutVersion),
      level: Value(level),
      warnings: warnings == null && nullToAbsent
          ? const Value.absent()
          : Value(warnings),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory BookRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BookRow(
      id: serializer.fromJson<int>(json['id']),
      uuid: serializer.fromJson<String>(json['uuid']),
      epubIdentifier: serializer.fromJson<String?>(json['epubIdentifier']),
      identityVersion: serializer.fromJson<int>(json['identityVersion']),
      legacyUuid: serializer.fromJson<String?>(json['legacyUuid']),
      title: serializer.fromJson<String>(json['title']),
      author: serializer.fromJson<String?>(json['author']),
      description: serializer.fromJson<String?>(json['description']),
      language: serializer.fromJson<String?>(json['language']),
      contentDir: serializer.fromJson<String>(json['contentDir']),
      sourcePath: serializer.fromJson<String?>(json['sourcePath']),
      coverPath: serializer.fromJson<String?>(json['coverPath']),
      spineCount: serializer.fromJson<int>(json['spineCount']),
      charCount: serializer.fromJson<int>(json['charCount']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      lastReadAt: serializer.fromJson<int?>(json['lastReadAt']),
      layoutVersion: serializer.fromJson<int>(json['layoutVersion']),
      level: serializer.fromJson<int>(json['level']),
      warnings: serializer.fromJson<String?>(json['warnings']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'uuid': serializer.toJson<String>(uuid),
      'epubIdentifier': serializer.toJson<String?>(epubIdentifier),
      'identityVersion': serializer.toJson<int>(identityVersion),
      'legacyUuid': serializer.toJson<String?>(legacyUuid),
      'title': serializer.toJson<String>(title),
      'author': serializer.toJson<String?>(author),
      'description': serializer.toJson<String?>(description),
      'language': serializer.toJson<String?>(language),
      'contentDir': serializer.toJson<String>(contentDir),
      'sourcePath': serializer.toJson<String?>(sourcePath),
      'coverPath': serializer.toJson<String?>(coverPath),
      'spineCount': serializer.toJson<int>(spineCount),
      'charCount': serializer.toJson<int>(charCount),
      'createdAt': serializer.toJson<int>(createdAt),
      'lastReadAt': serializer.toJson<int?>(lastReadAt),
      'layoutVersion': serializer.toJson<int>(layoutVersion),
      'level': serializer.toJson<int>(level),
      'warnings': serializer.toJson<String?>(warnings),
      'deletedAt': serializer.toJson<int?>(deletedAt),
    };
  }

  BookRow copyWith({
    int? id,
    String? uuid,
    Value<String?> epubIdentifier = const Value.absent(),
    int? identityVersion,
    Value<String?> legacyUuid = const Value.absent(),
    String? title,
    Value<String?> author = const Value.absent(),
    Value<String?> description = const Value.absent(),
    Value<String?> language = const Value.absent(),
    String? contentDir,
    Value<String?> sourcePath = const Value.absent(),
    Value<String?> coverPath = const Value.absent(),
    int? spineCount,
    int? charCount,
    int? createdAt,
    Value<int?> lastReadAt = const Value.absent(),
    int? layoutVersion,
    int? level,
    Value<String?> warnings = const Value.absent(),
    Value<int?> deletedAt = const Value.absent(),
  }) => BookRow(
    id: id ?? this.id,
    uuid: uuid ?? this.uuid,
    epubIdentifier: epubIdentifier.present
        ? epubIdentifier.value
        : this.epubIdentifier,
    identityVersion: identityVersion ?? this.identityVersion,
    legacyUuid: legacyUuid.present ? legacyUuid.value : this.legacyUuid,
    title: title ?? this.title,
    author: author.present ? author.value : this.author,
    description: description.present ? description.value : this.description,
    language: language.present ? language.value : this.language,
    contentDir: contentDir ?? this.contentDir,
    sourcePath: sourcePath.present ? sourcePath.value : this.sourcePath,
    coverPath: coverPath.present ? coverPath.value : this.coverPath,
    spineCount: spineCount ?? this.spineCount,
    charCount: charCount ?? this.charCount,
    createdAt: createdAt ?? this.createdAt,
    lastReadAt: lastReadAt.present ? lastReadAt.value : this.lastReadAt,
    layoutVersion: layoutVersion ?? this.layoutVersion,
    level: level ?? this.level,
    warnings: warnings.present ? warnings.value : this.warnings,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  BookRow copyWithCompanion(BooksCompanion data) {
    return BookRow(
      id: data.id.present ? data.id.value : this.id,
      uuid: data.uuid.present ? data.uuid.value : this.uuid,
      epubIdentifier: data.epubIdentifier.present
          ? data.epubIdentifier.value
          : this.epubIdentifier,
      identityVersion: data.identityVersion.present
          ? data.identityVersion.value
          : this.identityVersion,
      legacyUuid: data.legacyUuid.present
          ? data.legacyUuid.value
          : this.legacyUuid,
      title: data.title.present ? data.title.value : this.title,
      author: data.author.present ? data.author.value : this.author,
      description: data.description.present
          ? data.description.value
          : this.description,
      language: data.language.present ? data.language.value : this.language,
      contentDir: data.contentDir.present
          ? data.contentDir.value
          : this.contentDir,
      sourcePath: data.sourcePath.present
          ? data.sourcePath.value
          : this.sourcePath,
      coverPath: data.coverPath.present ? data.coverPath.value : this.coverPath,
      spineCount: data.spineCount.present
          ? data.spineCount.value
          : this.spineCount,
      charCount: data.charCount.present ? data.charCount.value : this.charCount,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastReadAt: data.lastReadAt.present
          ? data.lastReadAt.value
          : this.lastReadAt,
      layoutVersion: data.layoutVersion.present
          ? data.layoutVersion.value
          : this.layoutVersion,
      level: data.level.present ? data.level.value : this.level,
      warnings: data.warnings.present ? data.warnings.value : this.warnings,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BookRow(')
          ..write('id: $id, ')
          ..write('uuid: $uuid, ')
          ..write('epubIdentifier: $epubIdentifier, ')
          ..write('identityVersion: $identityVersion, ')
          ..write('legacyUuid: $legacyUuid, ')
          ..write('title: $title, ')
          ..write('author: $author, ')
          ..write('description: $description, ')
          ..write('language: $language, ')
          ..write('contentDir: $contentDir, ')
          ..write('sourcePath: $sourcePath, ')
          ..write('coverPath: $coverPath, ')
          ..write('spineCount: $spineCount, ')
          ..write('charCount: $charCount, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastReadAt: $lastReadAt, ')
          ..write('layoutVersion: $layoutVersion, ')
          ..write('level: $level, ')
          ..write('warnings: $warnings, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    uuid,
    epubIdentifier,
    identityVersion,
    legacyUuid,
    title,
    author,
    description,
    language,
    contentDir,
    sourcePath,
    coverPath,
    spineCount,
    charCount,
    createdAt,
    lastReadAt,
    layoutVersion,
    level,
    warnings,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookRow &&
          other.id == this.id &&
          other.uuid == this.uuid &&
          other.epubIdentifier == this.epubIdentifier &&
          other.identityVersion == this.identityVersion &&
          other.legacyUuid == this.legacyUuid &&
          other.title == this.title &&
          other.author == this.author &&
          other.description == this.description &&
          other.language == this.language &&
          other.contentDir == this.contentDir &&
          other.sourcePath == this.sourcePath &&
          other.coverPath == this.coverPath &&
          other.spineCount == this.spineCount &&
          other.charCount == this.charCount &&
          other.createdAt == this.createdAt &&
          other.lastReadAt == this.lastReadAt &&
          other.layoutVersion == this.layoutVersion &&
          other.level == this.level &&
          other.warnings == this.warnings &&
          other.deletedAt == this.deletedAt);
}

class BooksCompanion extends UpdateCompanion<BookRow> {
  final Value<int> id;
  final Value<String> uuid;
  final Value<String?> epubIdentifier;
  final Value<int> identityVersion;
  final Value<String?> legacyUuid;
  final Value<String> title;
  final Value<String?> author;
  final Value<String?> description;
  final Value<String?> language;
  final Value<String> contentDir;
  final Value<String?> sourcePath;
  final Value<String?> coverPath;
  final Value<int> spineCount;
  final Value<int> charCount;
  final Value<int> createdAt;
  final Value<int?> lastReadAt;
  final Value<int> layoutVersion;
  final Value<int> level;
  final Value<String?> warnings;
  final Value<int?> deletedAt;
  const BooksCompanion({
    this.id = const Value.absent(),
    this.uuid = const Value.absent(),
    this.epubIdentifier = const Value.absent(),
    this.identityVersion = const Value.absent(),
    this.legacyUuid = const Value.absent(),
    this.title = const Value.absent(),
    this.author = const Value.absent(),
    this.description = const Value.absent(),
    this.language = const Value.absent(),
    this.contentDir = const Value.absent(),
    this.sourcePath = const Value.absent(),
    this.coverPath = const Value.absent(),
    this.spineCount = const Value.absent(),
    this.charCount = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastReadAt = const Value.absent(),
    this.layoutVersion = const Value.absent(),
    this.level = const Value.absent(),
    this.warnings = const Value.absent(),
    this.deletedAt = const Value.absent(),
  });
  BooksCompanion.insert({
    this.id = const Value.absent(),
    required String uuid,
    this.epubIdentifier = const Value.absent(),
    this.identityVersion = const Value.absent(),
    this.legacyUuid = const Value.absent(),
    required String title,
    this.author = const Value.absent(),
    this.description = const Value.absent(),
    this.language = const Value.absent(),
    required String contentDir,
    this.sourcePath = const Value.absent(),
    this.coverPath = const Value.absent(),
    this.spineCount = const Value.absent(),
    this.charCount = const Value.absent(),
    required int createdAt,
    this.lastReadAt = const Value.absent(),
    this.layoutVersion = const Value.absent(),
    this.level = const Value.absent(),
    this.warnings = const Value.absent(),
    this.deletedAt = const Value.absent(),
  }) : uuid = Value(uuid),
       title = Value(title),
       contentDir = Value(contentDir),
       createdAt = Value(createdAt);
  static Insertable<BookRow> custom({
    Expression<int>? id,
    Expression<String>? uuid,
    Expression<String>? epubIdentifier,
    Expression<int>? identityVersion,
    Expression<String>? legacyUuid,
    Expression<String>? title,
    Expression<String>? author,
    Expression<String>? description,
    Expression<String>? language,
    Expression<String>? contentDir,
    Expression<String>? sourcePath,
    Expression<String>? coverPath,
    Expression<int>? spineCount,
    Expression<int>? charCount,
    Expression<int>? createdAt,
    Expression<int>? lastReadAt,
    Expression<int>? layoutVersion,
    Expression<int>? level,
    Expression<String>? warnings,
    Expression<int>? deletedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (uuid != null) 'uuid': uuid,
      if (epubIdentifier != null) 'epub_identifier': epubIdentifier,
      if (identityVersion != null) 'identity_version': identityVersion,
      if (legacyUuid != null) 'legacy_uuid': legacyUuid,
      if (title != null) 'title': title,
      if (author != null) 'author': author,
      if (description != null) 'description': description,
      if (language != null) 'language': language,
      if (contentDir != null) 'content_dir': contentDir,
      if (sourcePath != null) 'source_path': sourcePath,
      if (coverPath != null) 'cover_path': coverPath,
      if (spineCount != null) 'spine_count': spineCount,
      if (charCount != null) 'char_count': charCount,
      if (createdAt != null) 'created_at': createdAt,
      if (lastReadAt != null) 'last_read_at': lastReadAt,
      if (layoutVersion != null) 'layout_version': layoutVersion,
      if (level != null) 'level': level,
      if (warnings != null) 'warnings': warnings,
      if (deletedAt != null) 'deleted_at': deletedAt,
    });
  }

  BooksCompanion copyWith({
    Value<int>? id,
    Value<String>? uuid,
    Value<String?>? epubIdentifier,
    Value<int>? identityVersion,
    Value<String?>? legacyUuid,
    Value<String>? title,
    Value<String?>? author,
    Value<String?>? description,
    Value<String?>? language,
    Value<String>? contentDir,
    Value<String?>? sourcePath,
    Value<String?>? coverPath,
    Value<int>? spineCount,
    Value<int>? charCount,
    Value<int>? createdAt,
    Value<int?>? lastReadAt,
    Value<int>? layoutVersion,
    Value<int>? level,
    Value<String?>? warnings,
    Value<int?>? deletedAt,
  }) {
    return BooksCompanion(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      epubIdentifier: epubIdentifier ?? this.epubIdentifier,
      identityVersion: identityVersion ?? this.identityVersion,
      legacyUuid: legacyUuid ?? this.legacyUuid,
      title: title ?? this.title,
      author: author ?? this.author,
      description: description ?? this.description,
      language: language ?? this.language,
      contentDir: contentDir ?? this.contentDir,
      sourcePath: sourcePath ?? this.sourcePath,
      coverPath: coverPath ?? this.coverPath,
      spineCount: spineCount ?? this.spineCount,
      charCount: charCount ?? this.charCount,
      createdAt: createdAt ?? this.createdAt,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      layoutVersion: layoutVersion ?? this.layoutVersion,
      level: level ?? this.level,
      warnings: warnings ?? this.warnings,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (uuid.present) {
      map['uuid'] = Variable<String>(uuid.value);
    }
    if (epubIdentifier.present) {
      map['epub_identifier'] = Variable<String>(epubIdentifier.value);
    }
    if (identityVersion.present) {
      map['identity_version'] = Variable<int>(identityVersion.value);
    }
    if (legacyUuid.present) {
      map['legacy_uuid'] = Variable<String>(legacyUuid.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (language.present) {
      map['language'] = Variable<String>(language.value);
    }
    if (contentDir.present) {
      map['content_dir'] = Variable<String>(contentDir.value);
    }
    if (sourcePath.present) {
      map['source_path'] = Variable<String>(sourcePath.value);
    }
    if (coverPath.present) {
      map['cover_path'] = Variable<String>(coverPath.value);
    }
    if (spineCount.present) {
      map['spine_count'] = Variable<int>(spineCount.value);
    }
    if (charCount.present) {
      map['char_count'] = Variable<int>(charCount.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (lastReadAt.present) {
      map['last_read_at'] = Variable<int>(lastReadAt.value);
    }
    if (layoutVersion.present) {
      map['layout_version'] = Variable<int>(layoutVersion.value);
    }
    if (level.present) {
      map['level'] = Variable<int>(level.value);
    }
    if (warnings.present) {
      map['warnings'] = Variable<String>(warnings.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BooksCompanion(')
          ..write('id: $id, ')
          ..write('uuid: $uuid, ')
          ..write('epubIdentifier: $epubIdentifier, ')
          ..write('identityVersion: $identityVersion, ')
          ..write('legacyUuid: $legacyUuid, ')
          ..write('title: $title, ')
          ..write('author: $author, ')
          ..write('description: $description, ')
          ..write('language: $language, ')
          ..write('contentDir: $contentDir, ')
          ..write('sourcePath: $sourcePath, ')
          ..write('coverPath: $coverPath, ')
          ..write('spineCount: $spineCount, ')
          ..write('charCount: $charCount, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastReadAt: $lastReadAt, ')
          ..write('layoutVersion: $layoutVersion, ')
          ..write('level: $level, ')
          ..write('warnings: $warnings, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }
}

class $SpineItemsTable extends SpineItems
    with TableInfo<$SpineItemsTable, SpineItemRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SpineItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<int> bookId = GeneratedColumn<int>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _spineIndexMeta = const VerificationMeta(
    'spineIndex',
  );
  @override
  late final GeneratedColumn<int> spineIndex = GeneratedColumn<int>(
    'spine_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hrefMeta = const VerificationMeta('href');
  @override
  late final GeneratedColumn<String> href = GeneratedColumn<String>(
    'href',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _linearMeta = const VerificationMeta('linear');
  @override
  late final GeneratedColumn<int> linear = GeneratedColumn<int>(
    'linear',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _byteSizeMeta = const VerificationMeta(
    'byteSize',
  );
  @override
  late final GeneratedColumn<int> byteSize = GeneratedColumn<int>(
    'byte_size',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _charCountMeta = const VerificationMeta(
    'charCount',
  );
  @override
  late final GeneratedColumn<int> charCount = GeneratedColumn<int>(
    'char_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _charStartMeta = const VerificationMeta(
    'charStart',
  );
  @override
  late final GeneratedColumn<int> charStart = GeneratedColumn<int>(
    'char_start',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bookId,
    spineIndex,
    href,
    linear,
    byteSize,
    charCount,
    charStart,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'spine_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<SpineItemRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('spine_index')) {
      context.handle(
        _spineIndexMeta,
        spineIndex.isAcceptableOrUnknown(data['spine_index']!, _spineIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_spineIndexMeta);
    }
    if (data.containsKey('href')) {
      context.handle(
        _hrefMeta,
        href.isAcceptableOrUnknown(data['href']!, _hrefMeta),
      );
    } else if (isInserting) {
      context.missing(_hrefMeta);
    }
    if (data.containsKey('linear')) {
      context.handle(
        _linearMeta,
        linear.isAcceptableOrUnknown(data['linear']!, _linearMeta),
      );
    }
    if (data.containsKey('byte_size')) {
      context.handle(
        _byteSizeMeta,
        byteSize.isAcceptableOrUnknown(data['byte_size']!, _byteSizeMeta),
      );
    }
    if (data.containsKey('char_count')) {
      context.handle(
        _charCountMeta,
        charCount.isAcceptableOrUnknown(data['char_count']!, _charCountMeta),
      );
    }
    if (data.containsKey('char_start')) {
      context.handle(
        _charStartMeta,
        charStart.isAcceptableOrUnknown(data['char_start']!, _charStartMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SpineItemRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SpineItemRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}book_id'],
      )!,
      spineIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}spine_index'],
      )!,
      href: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}href'],
      )!,
      linear: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}linear'],
      )!,
      byteSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_size'],
      ),
      charCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}char_count'],
      ),
      charStart: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}char_start'],
      ),
    );
  }

  @override
  $SpineItemsTable createAlias(String alias) {
    return $SpineItemsTable(attachedDatabase, alias);
  }
}

class SpineItemRow extends DataClass implements Insertable<SpineItemRow> {
  /// 主键。
  final int id;

  /// 所属书籍（删书级联）。
  final int bookId;

  /// spine 序号（§34.2：(原序+1)×2）。
  final int spineIndex;

  /// 章节文档路径。
  final String href;

  /// 是否 linear（1 参与主线阅读）。
  final int linear;

  /// 文档字节数。
  final int? byteSize;

  /// 本章字符数（进度用）。
  final int? charCount;

  /// 全书字符偏移起点。
  final int? charStart;
  const SpineItemRow({
    required this.id,
    required this.bookId,
    required this.spineIndex,
    required this.href,
    required this.linear,
    this.byteSize,
    this.charCount,
    this.charStart,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['book_id'] = Variable<int>(bookId);
    map['spine_index'] = Variable<int>(spineIndex);
    map['href'] = Variable<String>(href);
    map['linear'] = Variable<int>(linear);
    if (!nullToAbsent || byteSize != null) {
      map['byte_size'] = Variable<int>(byteSize);
    }
    if (!nullToAbsent || charCount != null) {
      map['char_count'] = Variable<int>(charCount);
    }
    if (!nullToAbsent || charStart != null) {
      map['char_start'] = Variable<int>(charStart);
    }
    return map;
  }

  SpineItemsCompanion toCompanion(bool nullToAbsent) {
    return SpineItemsCompanion(
      id: Value(id),
      bookId: Value(bookId),
      spineIndex: Value(spineIndex),
      href: Value(href),
      linear: Value(linear),
      byteSize: byteSize == null && nullToAbsent
          ? const Value.absent()
          : Value(byteSize),
      charCount: charCount == null && nullToAbsent
          ? const Value.absent()
          : Value(charCount),
      charStart: charStart == null && nullToAbsent
          ? const Value.absent()
          : Value(charStart),
    );
  }

  factory SpineItemRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SpineItemRow(
      id: serializer.fromJson<int>(json['id']),
      bookId: serializer.fromJson<int>(json['bookId']),
      spineIndex: serializer.fromJson<int>(json['spineIndex']),
      href: serializer.fromJson<String>(json['href']),
      linear: serializer.fromJson<int>(json['linear']),
      byteSize: serializer.fromJson<int?>(json['byteSize']),
      charCount: serializer.fromJson<int?>(json['charCount']),
      charStart: serializer.fromJson<int?>(json['charStart']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'bookId': serializer.toJson<int>(bookId),
      'spineIndex': serializer.toJson<int>(spineIndex),
      'href': serializer.toJson<String>(href),
      'linear': serializer.toJson<int>(linear),
      'byteSize': serializer.toJson<int?>(byteSize),
      'charCount': serializer.toJson<int?>(charCount),
      'charStart': serializer.toJson<int?>(charStart),
    };
  }

  SpineItemRow copyWith({
    int? id,
    int? bookId,
    int? spineIndex,
    String? href,
    int? linear,
    Value<int?> byteSize = const Value.absent(),
    Value<int?> charCount = const Value.absent(),
    Value<int?> charStart = const Value.absent(),
  }) => SpineItemRow(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    spineIndex: spineIndex ?? this.spineIndex,
    href: href ?? this.href,
    linear: linear ?? this.linear,
    byteSize: byteSize.present ? byteSize.value : this.byteSize,
    charCount: charCount.present ? charCount.value : this.charCount,
    charStart: charStart.present ? charStart.value : this.charStart,
  );
  SpineItemRow copyWithCompanion(SpineItemsCompanion data) {
    return SpineItemRow(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      spineIndex: data.spineIndex.present
          ? data.spineIndex.value
          : this.spineIndex,
      href: data.href.present ? data.href.value : this.href,
      linear: data.linear.present ? data.linear.value : this.linear,
      byteSize: data.byteSize.present ? data.byteSize.value : this.byteSize,
      charCount: data.charCount.present ? data.charCount.value : this.charCount,
      charStart: data.charStart.present ? data.charStart.value : this.charStart,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SpineItemRow(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('spineIndex: $spineIndex, ')
          ..write('href: $href, ')
          ..write('linear: $linear, ')
          ..write('byteSize: $byteSize, ')
          ..write('charCount: $charCount, ')
          ..write('charStart: $charStart')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    bookId,
    spineIndex,
    href,
    linear,
    byteSize,
    charCount,
    charStart,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SpineItemRow &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.spineIndex == this.spineIndex &&
          other.href == this.href &&
          other.linear == this.linear &&
          other.byteSize == this.byteSize &&
          other.charCount == this.charCount &&
          other.charStart == this.charStart);
}

class SpineItemsCompanion extends UpdateCompanion<SpineItemRow> {
  final Value<int> id;
  final Value<int> bookId;
  final Value<int> spineIndex;
  final Value<String> href;
  final Value<int> linear;
  final Value<int?> byteSize;
  final Value<int?> charCount;
  final Value<int?> charStart;
  const SpineItemsCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.spineIndex = const Value.absent(),
    this.href = const Value.absent(),
    this.linear = const Value.absent(),
    this.byteSize = const Value.absent(),
    this.charCount = const Value.absent(),
    this.charStart = const Value.absent(),
  });
  SpineItemsCompanion.insert({
    this.id = const Value.absent(),
    required int bookId,
    required int spineIndex,
    required String href,
    this.linear = const Value.absent(),
    this.byteSize = const Value.absent(),
    this.charCount = const Value.absent(),
    this.charStart = const Value.absent(),
  }) : bookId = Value(bookId),
       spineIndex = Value(spineIndex),
       href = Value(href);
  static Insertable<SpineItemRow> custom({
    Expression<int>? id,
    Expression<int>? bookId,
    Expression<int>? spineIndex,
    Expression<String>? href,
    Expression<int>? linear,
    Expression<int>? byteSize,
    Expression<int>? charCount,
    Expression<int>? charStart,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (spineIndex != null) 'spine_index': spineIndex,
      if (href != null) 'href': href,
      if (linear != null) 'linear': linear,
      if (byteSize != null) 'byte_size': byteSize,
      if (charCount != null) 'char_count': charCount,
      if (charStart != null) 'char_start': charStart,
    });
  }

  SpineItemsCompanion copyWith({
    Value<int>? id,
    Value<int>? bookId,
    Value<int>? spineIndex,
    Value<String>? href,
    Value<int>? linear,
    Value<int?>? byteSize,
    Value<int?>? charCount,
    Value<int?>? charStart,
  }) {
    return SpineItemsCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      spineIndex: spineIndex ?? this.spineIndex,
      href: href ?? this.href,
      linear: linear ?? this.linear,
      byteSize: byteSize ?? this.byteSize,
      charCount: charCount ?? this.charCount,
      charStart: charStart ?? this.charStart,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<int>(bookId.value);
    }
    if (spineIndex.present) {
      map['spine_index'] = Variable<int>(spineIndex.value);
    }
    if (href.present) {
      map['href'] = Variable<String>(href.value);
    }
    if (linear.present) {
      map['linear'] = Variable<int>(linear.value);
    }
    if (byteSize.present) {
      map['byte_size'] = Variable<int>(byteSize.value);
    }
    if (charCount.present) {
      map['char_count'] = Variable<int>(charCount.value);
    }
    if (charStart.present) {
      map['char_start'] = Variable<int>(charStart.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SpineItemsCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('spineIndex: $spineIndex, ')
          ..write('href: $href, ')
          ..write('linear: $linear, ')
          ..write('byteSize: $byteSize, ')
          ..write('charCount: $charCount, ')
          ..write('charStart: $charStart')
          ..write(')'))
        .toString();
  }
}

class $ChaptersTable extends Chapters
    with TableInfo<$ChaptersTable, ChapterRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChaptersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<int> bookId = GeneratedColumn<int>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _depthMeta = const VerificationMeta('depth');
  @override
  late final GeneratedColumn<int> depth = GeneratedColumn<int>(
    'depth',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hrefMeta = const VerificationMeta('href');
  @override
  late final GeneratedColumn<String> href = GeneratedColumn<String>(
    'href',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cfiMeta = const VerificationMeta('cfi');
  @override
  late final GeneratedColumn<String> cfi = GeneratedColumn<String>(
    'cfi',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _orderIndexMeta = const VerificationMeta(
    'orderIndex',
  );
  @override
  late final GeneratedColumn<int> orderIndex = GeneratedColumn<int>(
    'order_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bookId,
    depth,
    title,
    href,
    cfi,
    orderIndex,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chapters';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChapterRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('depth')) {
      context.handle(
        _depthMeta,
        depth.isAcceptableOrUnknown(data['depth']!, _depthMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('href')) {
      context.handle(
        _hrefMeta,
        href.isAcceptableOrUnknown(data['href']!, _hrefMeta),
      );
    } else if (isInserting) {
      context.missing(_hrefMeta);
    }
    if (data.containsKey('cfi')) {
      context.handle(
        _cfiMeta,
        cfi.isAcceptableOrUnknown(data['cfi']!, _cfiMeta),
      );
    }
    if (data.containsKey('order_index')) {
      context.handle(
        _orderIndexMeta,
        orderIndex.isAcceptableOrUnknown(data['order_index']!, _orderIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_orderIndexMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChapterRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChapterRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}book_id'],
      )!,
      depth: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}depth'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      href: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}href'],
      )!,
      cfi: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cfi'],
      ),
      orderIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order_index'],
      )!,
    );
  }

  @override
  $ChaptersTable createAlias(String alias) {
    return $ChaptersTable(attachedDatabase, alias);
  }
}

class ChapterRow extends DataClass implements Insertable<ChapterRow> {
  /// 主键。
  final int id;

  /// 所属书籍。
  final int bookId;

  /// 层级（1 起，决定目录缩进）。
  final int depth;

  /// 标题。
  final String title;

  /// 目标文档路径。
  final String href;

  /// 解析期算出的 CFI。
  final String? cfi;

  /// 文档顺序。
  final int orderIndex;
  const ChapterRow({
    required this.id,
    required this.bookId,
    required this.depth,
    required this.title,
    required this.href,
    this.cfi,
    required this.orderIndex,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['book_id'] = Variable<int>(bookId);
    map['depth'] = Variable<int>(depth);
    map['title'] = Variable<String>(title);
    map['href'] = Variable<String>(href);
    if (!nullToAbsent || cfi != null) {
      map['cfi'] = Variable<String>(cfi);
    }
    map['order_index'] = Variable<int>(orderIndex);
    return map;
  }

  ChaptersCompanion toCompanion(bool nullToAbsent) {
    return ChaptersCompanion(
      id: Value(id),
      bookId: Value(bookId),
      depth: Value(depth),
      title: Value(title),
      href: Value(href),
      cfi: cfi == null && nullToAbsent ? const Value.absent() : Value(cfi),
      orderIndex: Value(orderIndex),
    );
  }

  factory ChapterRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChapterRow(
      id: serializer.fromJson<int>(json['id']),
      bookId: serializer.fromJson<int>(json['bookId']),
      depth: serializer.fromJson<int>(json['depth']),
      title: serializer.fromJson<String>(json['title']),
      href: serializer.fromJson<String>(json['href']),
      cfi: serializer.fromJson<String?>(json['cfi']),
      orderIndex: serializer.fromJson<int>(json['orderIndex']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'bookId': serializer.toJson<int>(bookId),
      'depth': serializer.toJson<int>(depth),
      'title': serializer.toJson<String>(title),
      'href': serializer.toJson<String>(href),
      'cfi': serializer.toJson<String?>(cfi),
      'orderIndex': serializer.toJson<int>(orderIndex),
    };
  }

  ChapterRow copyWith({
    int? id,
    int? bookId,
    int? depth,
    String? title,
    String? href,
    Value<String?> cfi = const Value.absent(),
    int? orderIndex,
  }) => ChapterRow(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    depth: depth ?? this.depth,
    title: title ?? this.title,
    href: href ?? this.href,
    cfi: cfi.present ? cfi.value : this.cfi,
    orderIndex: orderIndex ?? this.orderIndex,
  );
  ChapterRow copyWithCompanion(ChaptersCompanion data) {
    return ChapterRow(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      depth: data.depth.present ? data.depth.value : this.depth,
      title: data.title.present ? data.title.value : this.title,
      href: data.href.present ? data.href.value : this.href,
      cfi: data.cfi.present ? data.cfi.value : this.cfi,
      orderIndex: data.orderIndex.present
          ? data.orderIndex.value
          : this.orderIndex,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChapterRow(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('depth: $depth, ')
          ..write('title: $title, ')
          ..write('href: $href, ')
          ..write('cfi: $cfi, ')
          ..write('orderIndex: $orderIndex')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, bookId, depth, title, href, cfi, orderIndex);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChapterRow &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.depth == this.depth &&
          other.title == this.title &&
          other.href == this.href &&
          other.cfi == this.cfi &&
          other.orderIndex == this.orderIndex);
}

class ChaptersCompanion extends UpdateCompanion<ChapterRow> {
  final Value<int> id;
  final Value<int> bookId;
  final Value<int> depth;
  final Value<String> title;
  final Value<String> href;
  final Value<String?> cfi;
  final Value<int> orderIndex;
  const ChaptersCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.depth = const Value.absent(),
    this.title = const Value.absent(),
    this.href = const Value.absent(),
    this.cfi = const Value.absent(),
    this.orderIndex = const Value.absent(),
  });
  ChaptersCompanion.insert({
    this.id = const Value.absent(),
    required int bookId,
    this.depth = const Value.absent(),
    required String title,
    required String href,
    this.cfi = const Value.absent(),
    required int orderIndex,
  }) : bookId = Value(bookId),
       title = Value(title),
       href = Value(href),
       orderIndex = Value(orderIndex);
  static Insertable<ChapterRow> custom({
    Expression<int>? id,
    Expression<int>? bookId,
    Expression<int>? depth,
    Expression<String>? title,
    Expression<String>? href,
    Expression<String>? cfi,
    Expression<int>? orderIndex,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (depth != null) 'depth': depth,
      if (title != null) 'title': title,
      if (href != null) 'href': href,
      if (cfi != null) 'cfi': cfi,
      if (orderIndex != null) 'order_index': orderIndex,
    });
  }

  ChaptersCompanion copyWith({
    Value<int>? id,
    Value<int>? bookId,
    Value<int>? depth,
    Value<String>? title,
    Value<String>? href,
    Value<String?>? cfi,
    Value<int>? orderIndex,
  }) {
    return ChaptersCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      depth: depth ?? this.depth,
      title: title ?? this.title,
      href: href ?? this.href,
      cfi: cfi ?? this.cfi,
      orderIndex: orderIndex ?? this.orderIndex,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<int>(bookId.value);
    }
    if (depth.present) {
      map['depth'] = Variable<int>(depth.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (href.present) {
      map['href'] = Variable<String>(href.value);
    }
    if (cfi.present) {
      map['cfi'] = Variable<String>(cfi.value);
    }
    if (orderIndex.present) {
      map['order_index'] = Variable<int>(orderIndex.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChaptersCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('depth: $depth, ')
          ..write('title: $title, ')
          ..write('href: $href, ')
          ..write('cfi: $cfi, ')
          ..write('orderIndex: $orderIndex')
          ..write(')'))
        .toString();
  }
}

class $AnnotationsTable extends Annotations
    with TableInfo<$AnnotationsTable, AnnotationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AnnotationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<int> bookId = GeneratedColumn<int>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<int> type = GeneratedColumn<int>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startCfiMeta = const VerificationMeta(
    'startCfi',
  );
  @override
  late final GeneratedColumn<String> startCfi = GeneratedColumn<String>(
    'start_cfi',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endCfiMeta = const VerificationMeta('endCfi');
  @override
  late final GeneratedColumn<String> endCfi = GeneratedColumn<String>(
    'end_cfi',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _quoteMeta = const VerificationMeta('quote');
  @override
  late final GeneratedColumn<String> quote = GeneratedColumn<String>(
    'quote',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contextBeforeMeta = const VerificationMeta(
    'contextBefore',
  );
  @override
  late final GeneratedColumn<String> contextBefore = GeneratedColumn<String>(
    'context_before',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contextAfterMeta = const VerificationMeta(
    'contextAfter',
  );
  @override
  late final GeneratedColumn<String> contextAfter = GeneratedColumn<String>(
    'context_after',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _styleMeta = const VerificationMeta('style');
  @override
  late final GeneratedColumn<int> style = GeneratedColumn<int>(
    'style',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<int> color = GeneratedColumn<int>(
    'color',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bookId,
    type,
    startCfi,
    endCfi,
    quote,
    contextBefore,
    contextAfter,
    style,
    color,
    note,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'annotations';
  @override
  VerificationContext validateIntegrity(
    Insertable<AnnotationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('start_cfi')) {
      context.handle(
        _startCfiMeta,
        startCfi.isAcceptableOrUnknown(data['start_cfi']!, _startCfiMeta),
      );
    } else if (isInserting) {
      context.missing(_startCfiMeta);
    }
    if (data.containsKey('end_cfi')) {
      context.handle(
        _endCfiMeta,
        endCfi.isAcceptableOrUnknown(data['end_cfi']!, _endCfiMeta),
      );
    } else if (isInserting) {
      context.missing(_endCfiMeta);
    }
    if (data.containsKey('quote')) {
      context.handle(
        _quoteMeta,
        quote.isAcceptableOrUnknown(data['quote']!, _quoteMeta),
      );
    } else if (isInserting) {
      context.missing(_quoteMeta);
    }
    if (data.containsKey('context_before')) {
      context.handle(
        _contextBeforeMeta,
        contextBefore.isAcceptableOrUnknown(
          data['context_before']!,
          _contextBeforeMeta,
        ),
      );
    }
    if (data.containsKey('context_after')) {
      context.handle(
        _contextAfterMeta,
        contextAfter.isAcceptableOrUnknown(
          data['context_after']!,
          _contextAfterMeta,
        ),
      );
    }
    if (data.containsKey('style')) {
      context.handle(
        _styleMeta,
        style.isAcceptableOrUnknown(data['style']!, _styleMeta),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AnnotationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AnnotationRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}book_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}type'],
      )!,
      startCfi: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}start_cfi'],
      )!,
      endCfi: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}end_cfi'],
      )!,
      quote: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}quote'],
      )!,
      contextBefore: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}context_before'],
      ),
      contextAfter: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}context_after'],
      ),
      style: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}style'],
      ),
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AnnotationsTable createAlias(String alias) {
    return $AnnotationsTable(attachedDatabase, alias);
  }
}

class AnnotationRow extends DataClass implements Insertable<AnnotationRow> {
  /// 主键（uuid 字符串，可迁移）。
  final String id;

  /// 所属书籍。
  final int bookId;

  /// 类型：0 高亮、1 笔记、2 书签。
  final int type;

  /// 起始 CFI。
  final String startCfi;

  /// 结束 CFI。
  final String endCfi;

  /// 原文引用（兜底重定位）。
  final String quote;

  /// 前文上下文（约 20 字）。
  final String? contextBefore;

  /// 后文上下文（约 20 字）。
  final String? contextAfter;

  /// 样式（划线/波浪线等）。
  final int? style;

  /// 颜色（ARGB）。
  final int? color;

  /// 笔记正文。
  final String? note;

  /// 创建时间（毫秒）。
  final int createdAt;

  /// 更新时间（毫秒）。
  final int updatedAt;
  const AnnotationRow({
    required this.id,
    required this.bookId,
    required this.type,
    required this.startCfi,
    required this.endCfi,
    required this.quote,
    this.contextBefore,
    this.contextAfter,
    this.style,
    this.color,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['book_id'] = Variable<int>(bookId);
    map['type'] = Variable<int>(type);
    map['start_cfi'] = Variable<String>(startCfi);
    map['end_cfi'] = Variable<String>(endCfi);
    map['quote'] = Variable<String>(quote);
    if (!nullToAbsent || contextBefore != null) {
      map['context_before'] = Variable<String>(contextBefore);
    }
    if (!nullToAbsent || contextAfter != null) {
      map['context_after'] = Variable<String>(contextAfter);
    }
    if (!nullToAbsent || style != null) {
      map['style'] = Variable<int>(style);
    }
    if (!nullToAbsent || color != null) {
      map['color'] = Variable<int>(color);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  AnnotationsCompanion toCompanion(bool nullToAbsent) {
    return AnnotationsCompanion(
      id: Value(id),
      bookId: Value(bookId),
      type: Value(type),
      startCfi: Value(startCfi),
      endCfi: Value(endCfi),
      quote: Value(quote),
      contextBefore: contextBefore == null && nullToAbsent
          ? const Value.absent()
          : Value(contextBefore),
      contextAfter: contextAfter == null && nullToAbsent
          ? const Value.absent()
          : Value(contextAfter),
      style: style == null && nullToAbsent
          ? const Value.absent()
          : Value(style),
      color: color == null && nullToAbsent
          ? const Value.absent()
          : Value(color),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory AnnotationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AnnotationRow(
      id: serializer.fromJson<String>(json['id']),
      bookId: serializer.fromJson<int>(json['bookId']),
      type: serializer.fromJson<int>(json['type']),
      startCfi: serializer.fromJson<String>(json['startCfi']),
      endCfi: serializer.fromJson<String>(json['endCfi']),
      quote: serializer.fromJson<String>(json['quote']),
      contextBefore: serializer.fromJson<String?>(json['contextBefore']),
      contextAfter: serializer.fromJson<String?>(json['contextAfter']),
      style: serializer.fromJson<int?>(json['style']),
      color: serializer.fromJson<int?>(json['color']),
      note: serializer.fromJson<String?>(json['note']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'bookId': serializer.toJson<int>(bookId),
      'type': serializer.toJson<int>(type),
      'startCfi': serializer.toJson<String>(startCfi),
      'endCfi': serializer.toJson<String>(endCfi),
      'quote': serializer.toJson<String>(quote),
      'contextBefore': serializer.toJson<String?>(contextBefore),
      'contextAfter': serializer.toJson<String?>(contextAfter),
      'style': serializer.toJson<int?>(style),
      'color': serializer.toJson<int?>(color),
      'note': serializer.toJson<String?>(note),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  AnnotationRow copyWith({
    String? id,
    int? bookId,
    int? type,
    String? startCfi,
    String? endCfi,
    String? quote,
    Value<String?> contextBefore = const Value.absent(),
    Value<String?> contextAfter = const Value.absent(),
    Value<int?> style = const Value.absent(),
    Value<int?> color = const Value.absent(),
    Value<String?> note = const Value.absent(),
    int? createdAt,
    int? updatedAt,
  }) => AnnotationRow(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    type: type ?? this.type,
    startCfi: startCfi ?? this.startCfi,
    endCfi: endCfi ?? this.endCfi,
    quote: quote ?? this.quote,
    contextBefore: contextBefore.present
        ? contextBefore.value
        : this.contextBefore,
    contextAfter: contextAfter.present ? contextAfter.value : this.contextAfter,
    style: style.present ? style.value : this.style,
    color: color.present ? color.value : this.color,
    note: note.present ? note.value : this.note,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  AnnotationRow copyWithCompanion(AnnotationsCompanion data) {
    return AnnotationRow(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      type: data.type.present ? data.type.value : this.type,
      startCfi: data.startCfi.present ? data.startCfi.value : this.startCfi,
      endCfi: data.endCfi.present ? data.endCfi.value : this.endCfi,
      quote: data.quote.present ? data.quote.value : this.quote,
      contextBefore: data.contextBefore.present
          ? data.contextBefore.value
          : this.contextBefore,
      contextAfter: data.contextAfter.present
          ? data.contextAfter.value
          : this.contextAfter,
      style: data.style.present ? data.style.value : this.style,
      color: data.color.present ? data.color.value : this.color,
      note: data.note.present ? data.note.value : this.note,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AnnotationRow(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('type: $type, ')
          ..write('startCfi: $startCfi, ')
          ..write('endCfi: $endCfi, ')
          ..write('quote: $quote, ')
          ..write('contextBefore: $contextBefore, ')
          ..write('contextAfter: $contextAfter, ')
          ..write('style: $style, ')
          ..write('color: $color, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    bookId,
    type,
    startCfi,
    endCfi,
    quote,
    contextBefore,
    contextAfter,
    style,
    color,
    note,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AnnotationRow &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.type == this.type &&
          other.startCfi == this.startCfi &&
          other.endCfi == this.endCfi &&
          other.quote == this.quote &&
          other.contextBefore == this.contextBefore &&
          other.contextAfter == this.contextAfter &&
          other.style == this.style &&
          other.color == this.color &&
          other.note == this.note &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class AnnotationsCompanion extends UpdateCompanion<AnnotationRow> {
  final Value<String> id;
  final Value<int> bookId;
  final Value<int> type;
  final Value<String> startCfi;
  final Value<String> endCfi;
  final Value<String> quote;
  final Value<String?> contextBefore;
  final Value<String?> contextAfter;
  final Value<int?> style;
  final Value<int?> color;
  final Value<String?> note;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const AnnotationsCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.type = const Value.absent(),
    this.startCfi = const Value.absent(),
    this.endCfi = const Value.absent(),
    this.quote = const Value.absent(),
    this.contextBefore = const Value.absent(),
    this.contextAfter = const Value.absent(),
    this.style = const Value.absent(),
    this.color = const Value.absent(),
    this.note = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AnnotationsCompanion.insert({
    required String id,
    required int bookId,
    required int type,
    required String startCfi,
    required String endCfi,
    required String quote,
    this.contextBefore = const Value.absent(),
    this.contextAfter = const Value.absent(),
    this.style = const Value.absent(),
    this.color = const Value.absent(),
    this.note = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       bookId = Value(bookId),
       type = Value(type),
       startCfi = Value(startCfi),
       endCfi = Value(endCfi),
       quote = Value(quote),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<AnnotationRow> custom({
    Expression<String>? id,
    Expression<int>? bookId,
    Expression<int>? type,
    Expression<String>? startCfi,
    Expression<String>? endCfi,
    Expression<String>? quote,
    Expression<String>? contextBefore,
    Expression<String>? contextAfter,
    Expression<int>? style,
    Expression<int>? color,
    Expression<String>? note,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (type != null) 'type': type,
      if (startCfi != null) 'start_cfi': startCfi,
      if (endCfi != null) 'end_cfi': endCfi,
      if (quote != null) 'quote': quote,
      if (contextBefore != null) 'context_before': contextBefore,
      if (contextAfter != null) 'context_after': contextAfter,
      if (style != null) 'style': style,
      if (color != null) 'color': color,
      if (note != null) 'note': note,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AnnotationsCompanion copyWith({
    Value<String>? id,
    Value<int>? bookId,
    Value<int>? type,
    Value<String>? startCfi,
    Value<String>? endCfi,
    Value<String>? quote,
    Value<String?>? contextBefore,
    Value<String?>? contextAfter,
    Value<int?>? style,
    Value<int?>? color,
    Value<String?>? note,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return AnnotationsCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      type: type ?? this.type,
      startCfi: startCfi ?? this.startCfi,
      endCfi: endCfi ?? this.endCfi,
      quote: quote ?? this.quote,
      contextBefore: contextBefore ?? this.contextBefore,
      contextAfter: contextAfter ?? this.contextAfter,
      style: style ?? this.style,
      color: color ?? this.color,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<int>(bookId.value);
    }
    if (type.present) {
      map['type'] = Variable<int>(type.value);
    }
    if (startCfi.present) {
      map['start_cfi'] = Variable<String>(startCfi.value);
    }
    if (endCfi.present) {
      map['end_cfi'] = Variable<String>(endCfi.value);
    }
    if (quote.present) {
      map['quote'] = Variable<String>(quote.value);
    }
    if (contextBefore.present) {
      map['context_before'] = Variable<String>(contextBefore.value);
    }
    if (contextAfter.present) {
      map['context_after'] = Variable<String>(contextAfter.value);
    }
    if (style.present) {
      map['style'] = Variable<int>(style.value);
    }
    if (color.present) {
      map['color'] = Variable<int>(color.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AnnotationsCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('type: $type, ')
          ..write('startCfi: $startCfi, ')
          ..write('endCfi: $endCfi, ')
          ..write('quote: $quote, ')
          ..write('contextBefore: $contextBefore, ')
          ..write('contextAfter: $contextAfter, ')
          ..write('style: $style, ')
          ..write('color: $color, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReadingProgressTable extends ReadingProgress
    with TableInfo<$ReadingProgressTable, ProgressRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReadingProgressTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<int> bookId = GeneratedColumn<int>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _locatorCfiMeta = const VerificationMeta(
    'locatorCfi',
  );
  @override
  late final GeneratedColumn<String> locatorCfi = GeneratedColumn<String>(
    'locator_cfi',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _spineIndexMeta = const VerificationMeta(
    'spineIndex',
  );
  @override
  late final GeneratedColumn<int> spineIndex = GeneratedColumn<int>(
    'spine_index',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pageIndexMeta = const VerificationMeta(
    'pageIndex',
  );
  @override
  late final GeneratedColumn<int> pageIndex = GeneratedColumn<int>(
    'page_index',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _finishedMeta = const VerificationMeta(
    'finished',
  );
  @override
  late final GeneratedColumn<bool> finished = GeneratedColumn<bool>(
    'finished',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("finished" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _percentMeta = const VerificationMeta(
    'percent',
  );
  @override
  late final GeneratedColumn<double> percent = GeneratedColumn<double>(
    'percent',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    bookId,
    locatorCfi,
    spineIndex,
    pageIndex,
    finished,
    percent,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reading_progress';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProgressRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    }
    if (data.containsKey('locator_cfi')) {
      context.handle(
        _locatorCfiMeta,
        locatorCfi.isAcceptableOrUnknown(data['locator_cfi']!, _locatorCfiMeta),
      );
    } else if (isInserting) {
      context.missing(_locatorCfiMeta);
    }
    if (data.containsKey('spine_index')) {
      context.handle(
        _spineIndexMeta,
        spineIndex.isAcceptableOrUnknown(data['spine_index']!, _spineIndexMeta),
      );
    }
    if (data.containsKey('page_index')) {
      context.handle(
        _pageIndexMeta,
        pageIndex.isAcceptableOrUnknown(data['page_index']!, _pageIndexMeta),
      );
    }
    if (data.containsKey('finished')) {
      context.handle(
        _finishedMeta,
        finished.isAcceptableOrUnknown(data['finished']!, _finishedMeta),
      );
    }
    if (data.containsKey('percent')) {
      context.handle(
        _percentMeta,
        percent.isAcceptableOrUnknown(data['percent']!, _percentMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookId};
  @override
  ProgressRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProgressRow(
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}book_id'],
      )!,
      locatorCfi: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}locator_cfi'],
      )!,
      spineIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}spine_index'],
      ),
      pageIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_index'],
      ),
      finished: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}finished'],
      )!,
      percent: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}percent'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ReadingProgressTable createAlias(String alias) {
    return $ReadingProgressTable(attachedDatabase, alias);
  }
}

class ProgressRow extends DataClass implements Insertable<ProgressRow> {
  /// 书籍主键兼外键。
  final int bookId;

  /// 位置 CFI（P5 接入 CFI 后使用；当前存 `spine:i/page:j` 占位串）。
  final String locatorCfi;

  /// spine 序号（P4-10：进度迁移到表内，书架/续读用）。
  final int? spineIndex;

  /// 章内页序号。
  final int? pageIndex;

  /// 用户手动标记的读完状态。
  final bool finished;

  /// 全书百分比（0～1）。
  final double percent;

  /// 写入时间（毫秒）。
  final int updatedAt;
  const ProgressRow({
    required this.bookId,
    required this.locatorCfi,
    this.spineIndex,
    this.pageIndex,
    required this.finished,
    required this.percent,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_id'] = Variable<int>(bookId);
    map['locator_cfi'] = Variable<String>(locatorCfi);
    if (!nullToAbsent || spineIndex != null) {
      map['spine_index'] = Variable<int>(spineIndex);
    }
    if (!nullToAbsent || pageIndex != null) {
      map['page_index'] = Variable<int>(pageIndex);
    }
    map['finished'] = Variable<bool>(finished);
    map['percent'] = Variable<double>(percent);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  ReadingProgressCompanion toCompanion(bool nullToAbsent) {
    return ReadingProgressCompanion(
      bookId: Value(bookId),
      locatorCfi: Value(locatorCfi),
      spineIndex: spineIndex == null && nullToAbsent
          ? const Value.absent()
          : Value(spineIndex),
      pageIndex: pageIndex == null && nullToAbsent
          ? const Value.absent()
          : Value(pageIndex),
      finished: Value(finished),
      percent: Value(percent),
      updatedAt: Value(updatedAt),
    );
  }

  factory ProgressRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProgressRow(
      bookId: serializer.fromJson<int>(json['bookId']),
      locatorCfi: serializer.fromJson<String>(json['locatorCfi']),
      spineIndex: serializer.fromJson<int?>(json['spineIndex']),
      pageIndex: serializer.fromJson<int?>(json['pageIndex']),
      finished: serializer.fromJson<bool>(json['finished']),
      percent: serializer.fromJson<double>(json['percent']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookId': serializer.toJson<int>(bookId),
      'locatorCfi': serializer.toJson<String>(locatorCfi),
      'spineIndex': serializer.toJson<int?>(spineIndex),
      'pageIndex': serializer.toJson<int?>(pageIndex),
      'finished': serializer.toJson<bool>(finished),
      'percent': serializer.toJson<double>(percent),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  ProgressRow copyWith({
    int? bookId,
    String? locatorCfi,
    Value<int?> spineIndex = const Value.absent(),
    Value<int?> pageIndex = const Value.absent(),
    bool? finished,
    double? percent,
    int? updatedAt,
  }) => ProgressRow(
    bookId: bookId ?? this.bookId,
    locatorCfi: locatorCfi ?? this.locatorCfi,
    spineIndex: spineIndex.present ? spineIndex.value : this.spineIndex,
    pageIndex: pageIndex.present ? pageIndex.value : this.pageIndex,
    finished: finished ?? this.finished,
    percent: percent ?? this.percent,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ProgressRow copyWithCompanion(ReadingProgressCompanion data) {
    return ProgressRow(
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      locatorCfi: data.locatorCfi.present
          ? data.locatorCfi.value
          : this.locatorCfi,
      spineIndex: data.spineIndex.present
          ? data.spineIndex.value
          : this.spineIndex,
      pageIndex: data.pageIndex.present ? data.pageIndex.value : this.pageIndex,
      finished: data.finished.present ? data.finished.value : this.finished,
      percent: data.percent.present ? data.percent.value : this.percent,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProgressRow(')
          ..write('bookId: $bookId, ')
          ..write('locatorCfi: $locatorCfi, ')
          ..write('spineIndex: $spineIndex, ')
          ..write('pageIndex: $pageIndex, ')
          ..write('finished: $finished, ')
          ..write('percent: $percent, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    bookId,
    locatorCfi,
    spineIndex,
    pageIndex,
    finished,
    percent,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProgressRow &&
          other.bookId == this.bookId &&
          other.locatorCfi == this.locatorCfi &&
          other.spineIndex == this.spineIndex &&
          other.pageIndex == this.pageIndex &&
          other.finished == this.finished &&
          other.percent == this.percent &&
          other.updatedAt == this.updatedAt);
}

class ReadingProgressCompanion extends UpdateCompanion<ProgressRow> {
  final Value<int> bookId;
  final Value<String> locatorCfi;
  final Value<int?> spineIndex;
  final Value<int?> pageIndex;
  final Value<bool> finished;
  final Value<double> percent;
  final Value<int> updatedAt;
  const ReadingProgressCompanion({
    this.bookId = const Value.absent(),
    this.locatorCfi = const Value.absent(),
    this.spineIndex = const Value.absent(),
    this.pageIndex = const Value.absent(),
    this.finished = const Value.absent(),
    this.percent = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  ReadingProgressCompanion.insert({
    this.bookId = const Value.absent(),
    required String locatorCfi,
    this.spineIndex = const Value.absent(),
    this.pageIndex = const Value.absent(),
    this.finished = const Value.absent(),
    this.percent = const Value.absent(),
    required int updatedAt,
  }) : locatorCfi = Value(locatorCfi),
       updatedAt = Value(updatedAt);
  static Insertable<ProgressRow> custom({
    Expression<int>? bookId,
    Expression<String>? locatorCfi,
    Expression<int>? spineIndex,
    Expression<int>? pageIndex,
    Expression<bool>? finished,
    Expression<double>? percent,
    Expression<int>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (bookId != null) 'book_id': bookId,
      if (locatorCfi != null) 'locator_cfi': locatorCfi,
      if (spineIndex != null) 'spine_index': spineIndex,
      if (pageIndex != null) 'page_index': pageIndex,
      if (finished != null) 'finished': finished,
      if (percent != null) 'percent': percent,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  ReadingProgressCompanion copyWith({
    Value<int>? bookId,
    Value<String>? locatorCfi,
    Value<int?>? spineIndex,
    Value<int?>? pageIndex,
    Value<bool>? finished,
    Value<double>? percent,
    Value<int>? updatedAt,
  }) {
    return ReadingProgressCompanion(
      bookId: bookId ?? this.bookId,
      locatorCfi: locatorCfi ?? this.locatorCfi,
      spineIndex: spineIndex ?? this.spineIndex,
      pageIndex: pageIndex ?? this.pageIndex,
      finished: finished ?? this.finished,
      percent: percent ?? this.percent,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookId.present) {
      map['book_id'] = Variable<int>(bookId.value);
    }
    if (locatorCfi.present) {
      map['locator_cfi'] = Variable<String>(locatorCfi.value);
    }
    if (spineIndex.present) {
      map['spine_index'] = Variable<int>(spineIndex.value);
    }
    if (pageIndex.present) {
      map['page_index'] = Variable<int>(pageIndex.value);
    }
    if (finished.present) {
      map['finished'] = Variable<bool>(finished.value);
    }
    if (percent.present) {
      map['percent'] = Variable<double>(percent.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReadingProgressCompanion(')
          ..write('bookId: $bookId, ')
          ..write('locatorCfi: $locatorCfi, ')
          ..write('spineIndex: $spineIndex, ')
          ..write('pageIndex: $pageIndex, ')
          ..write('finished: $finished, ')
          ..write('percent: $percent, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $UserFontsTable extends UserFonts
    with TableInfo<$UserFontsTable, UserFontRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UserFontsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _familyMeta = const VerificationMeta('family');
  @override
  late final GeneratedColumn<String> family = GeneratedColumn<String>(
    'family',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _weightMeta = const VerificationMeta('weight');
  @override
  late final GeneratedColumn<int> weight = GeneratedColumn<int>(
    'weight',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _styleMeta = const VerificationMeta('style');
  @override
  late final GeneratedColumn<int> style = GeneratedColumn<int>(
    'style',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    family,
    filePath,
    weight,
    style,
    displayName,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'user_fonts';
  @override
  VerificationContext validateIntegrity(
    Insertable<UserFontRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('family')) {
      context.handle(
        _familyMeta,
        family.isAcceptableOrUnknown(data['family']!, _familyMeta),
      );
    } else if (isInserting) {
      context.missing(_familyMeta);
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('weight')) {
      context.handle(
        _weightMeta,
        weight.isAcceptableOrUnknown(data['weight']!, _weightMeta),
      );
    }
    if (data.containsKey('style')) {
      context.handle(
        _styleMeta,
        style.isAcceptableOrUnknown(data['style']!, _styleMeta),
      );
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UserFontRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UserFontRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      family: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}family'],
      )!,
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      )!,
      weight: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}weight'],
      ),
      style: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}style'],
      ),
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      ),
    );
  }

  @override
  $UserFontsTable createAlias(String alias) {
    return $UserFontsTable(attachedDatabase, alias);
  }
}

class UserFontRow extends DataClass implements Insertable<UserFontRow> {
  /// 主键。
  final int id;

  /// 族名。
  final String family;

  /// 字体文件路径。
  final String filePath;

  /// 字重。
  final int? weight;

  /// 字体样式（normal/italic）。
  final int? style;

  /// 展示名。
  final String? displayName;
  const UserFontRow({
    required this.id,
    required this.family,
    required this.filePath,
    this.weight,
    this.style,
    this.displayName,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['family'] = Variable<String>(family);
    map['file_path'] = Variable<String>(filePath);
    if (!nullToAbsent || weight != null) {
      map['weight'] = Variable<int>(weight);
    }
    if (!nullToAbsent || style != null) {
      map['style'] = Variable<int>(style);
    }
    if (!nullToAbsent || displayName != null) {
      map['display_name'] = Variable<String>(displayName);
    }
    return map;
  }

  UserFontsCompanion toCompanion(bool nullToAbsent) {
    return UserFontsCompanion(
      id: Value(id),
      family: Value(family),
      filePath: Value(filePath),
      weight: weight == null && nullToAbsent
          ? const Value.absent()
          : Value(weight),
      style: style == null && nullToAbsent
          ? const Value.absent()
          : Value(style),
      displayName: displayName == null && nullToAbsent
          ? const Value.absent()
          : Value(displayName),
    );
  }

  factory UserFontRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UserFontRow(
      id: serializer.fromJson<int>(json['id']),
      family: serializer.fromJson<String>(json['family']),
      filePath: serializer.fromJson<String>(json['filePath']),
      weight: serializer.fromJson<int?>(json['weight']),
      style: serializer.fromJson<int?>(json['style']),
      displayName: serializer.fromJson<String?>(json['displayName']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'family': serializer.toJson<String>(family),
      'filePath': serializer.toJson<String>(filePath),
      'weight': serializer.toJson<int?>(weight),
      'style': serializer.toJson<int?>(style),
      'displayName': serializer.toJson<String?>(displayName),
    };
  }

  UserFontRow copyWith({
    int? id,
    String? family,
    String? filePath,
    Value<int?> weight = const Value.absent(),
    Value<int?> style = const Value.absent(),
    Value<String?> displayName = const Value.absent(),
  }) => UserFontRow(
    id: id ?? this.id,
    family: family ?? this.family,
    filePath: filePath ?? this.filePath,
    weight: weight.present ? weight.value : this.weight,
    style: style.present ? style.value : this.style,
    displayName: displayName.present ? displayName.value : this.displayName,
  );
  UserFontRow copyWithCompanion(UserFontsCompanion data) {
    return UserFontRow(
      id: data.id.present ? data.id.value : this.id,
      family: data.family.present ? data.family.value : this.family,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      weight: data.weight.present ? data.weight.value : this.weight,
      style: data.style.present ? data.style.value : this.style,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UserFontRow(')
          ..write('id: $id, ')
          ..write('family: $family, ')
          ..write('filePath: $filePath, ')
          ..write('weight: $weight, ')
          ..write('style: $style, ')
          ..write('displayName: $displayName')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, family, filePath, weight, style, displayName);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserFontRow &&
          other.id == this.id &&
          other.family == this.family &&
          other.filePath == this.filePath &&
          other.weight == this.weight &&
          other.style == this.style &&
          other.displayName == this.displayName);
}

class UserFontsCompanion extends UpdateCompanion<UserFontRow> {
  final Value<int> id;
  final Value<String> family;
  final Value<String> filePath;
  final Value<int?> weight;
  final Value<int?> style;
  final Value<String?> displayName;
  const UserFontsCompanion({
    this.id = const Value.absent(),
    this.family = const Value.absent(),
    this.filePath = const Value.absent(),
    this.weight = const Value.absent(),
    this.style = const Value.absent(),
    this.displayName = const Value.absent(),
  });
  UserFontsCompanion.insert({
    this.id = const Value.absent(),
    required String family,
    required String filePath,
    this.weight = const Value.absent(),
    this.style = const Value.absent(),
    this.displayName = const Value.absent(),
  }) : family = Value(family),
       filePath = Value(filePath);
  static Insertable<UserFontRow> custom({
    Expression<int>? id,
    Expression<String>? family,
    Expression<String>? filePath,
    Expression<int>? weight,
    Expression<int>? style,
    Expression<String>? displayName,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (family != null) 'family': family,
      if (filePath != null) 'file_path': filePath,
      if (weight != null) 'weight': weight,
      if (style != null) 'style': style,
      if (displayName != null) 'display_name': displayName,
    });
  }

  UserFontsCompanion copyWith({
    Value<int>? id,
    Value<String>? family,
    Value<String>? filePath,
    Value<int?>? weight,
    Value<int?>? style,
    Value<String?>? displayName,
  }) {
    return UserFontsCompanion(
      id: id ?? this.id,
      family: family ?? this.family,
      filePath: filePath ?? this.filePath,
      weight: weight ?? this.weight,
      style: style ?? this.style,
      displayName: displayName ?? this.displayName,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (family.present) {
      map['family'] = Variable<String>(family.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (weight.present) {
      map['weight'] = Variable<int>(weight.value);
    }
    if (style.present) {
      map['style'] = Variable<int>(style.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UserFontsCompanion(')
          ..write('id: $id, ')
          ..write('family: $family, ')
          ..write('filePath: $filePath, ')
          ..write('weight: $weight, ')
          ..write('style: $style, ')
          ..write('displayName: $displayName')
          ..write(')'))
        .toString();
  }
}

class $SettingsTableTable extends SettingsTable
    with TableInfo<$SettingsTableTable, SettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingsTableTable createAlias(String alias) {
    return $SettingsTableTable(attachedDatabase, alias);
  }
}

class SettingRow extends DataClass implements Insertable<SettingRow> {
  /// 设置键。
  final String key;

  /// 设置值。
  final String value;
  const SettingRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsTableCompanion toCompanion(bool nullToAbsent) {
    return SettingsTableCompanion(key: Value(key), value: Value(value));
  }

  factory SettingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SettingRow copyWith({String? key, String? value}) =>
      SettingRow(key: key ?? this.key, value: value ?? this.value);
  SettingRow copyWithCompanion(SettingsTableCompanion data) {
    return SettingRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingRow &&
          other.key == this.key &&
          other.value == this.value);
}

class SettingsTableCompanion extends UpdateCompanion<SettingRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsTableCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsTableCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SettingRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsTableCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsTableCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsTableCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ImportReportsTable extends ImportReports
    with TableInfo<$ImportReportsTable, ImportReportRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ImportReportsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<int> bookId = GeneratedColumn<int>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _severityMeta = const VerificationMeta(
    'severity',
  );
  @override
  late final GeneratedColumn<int> severity = GeneratedColumn<int>(
    'severity',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _messageMeta = const VerificationMeta(
    'message',
  );
  @override
  late final GeneratedColumn<String> message = GeneratedColumn<String>(
    'message',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _offsetMeta = const VerificationMeta('offset');
  @override
  late final GeneratedColumn<int> offset = GeneratedColumn<int>(
    'offset',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bookId,
    code,
    severity,
    message,
    offset,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'import_reports';
  @override
  VerificationContext validateIntegrity(
    Insertable<ImportReportRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('severity')) {
      context.handle(
        _severityMeta,
        severity.isAcceptableOrUnknown(data['severity']!, _severityMeta),
      );
    }
    if (data.containsKey('message')) {
      context.handle(
        _messageMeta,
        message.isAcceptableOrUnknown(data['message']!, _messageMeta),
      );
    } else if (isInserting) {
      context.missing(_messageMeta);
    }
    if (data.containsKey('offset')) {
      context.handle(
        _offsetMeta,
        offset.isAcceptableOrUnknown(data['offset']!, _offsetMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ImportReportRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ImportReportRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}book_id'],
      )!,
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      severity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}severity'],
      )!,
      message: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message'],
      )!,
      offset: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}offset'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ImportReportsTable createAlias(String alias) {
    return $ImportReportsTable(attachedDatabase, alias);
  }
}

class ImportReportRow extends DataClass implements Insertable<ImportReportRow> {
  /// 主键。
  final int id;

  /// 所属书籍。
  final int bookId;

  /// 诊断码（P7-05 诊断码）。
  final String code;

  /// 分级：0 info、1 warning、2 error。
  final int severity;

  /// 人类可读信息。
  final String message;

  /// 相关文件内偏移（可空）。
  final int? offset;

  /// 记录时间（毫秒）。
  final int createdAt;
  const ImportReportRow({
    required this.id,
    required this.bookId,
    required this.code,
    required this.severity,
    required this.message,
    this.offset,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['book_id'] = Variable<int>(bookId);
    map['code'] = Variable<String>(code);
    map['severity'] = Variable<int>(severity);
    map['message'] = Variable<String>(message);
    if (!nullToAbsent || offset != null) {
      map['offset'] = Variable<int>(offset);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  ImportReportsCompanion toCompanion(bool nullToAbsent) {
    return ImportReportsCompanion(
      id: Value(id),
      bookId: Value(bookId),
      code: Value(code),
      severity: Value(severity),
      message: Value(message),
      offset: offset == null && nullToAbsent
          ? const Value.absent()
          : Value(offset),
      createdAt: Value(createdAt),
    );
  }

  factory ImportReportRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ImportReportRow(
      id: serializer.fromJson<int>(json['id']),
      bookId: serializer.fromJson<int>(json['bookId']),
      code: serializer.fromJson<String>(json['code']),
      severity: serializer.fromJson<int>(json['severity']),
      message: serializer.fromJson<String>(json['message']),
      offset: serializer.fromJson<int?>(json['offset']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'bookId': serializer.toJson<int>(bookId),
      'code': serializer.toJson<String>(code),
      'severity': serializer.toJson<int>(severity),
      'message': serializer.toJson<String>(message),
      'offset': serializer.toJson<int?>(offset),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  ImportReportRow copyWith({
    int? id,
    int? bookId,
    String? code,
    int? severity,
    String? message,
    Value<int?> offset = const Value.absent(),
    int? createdAt,
  }) => ImportReportRow(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    code: code ?? this.code,
    severity: severity ?? this.severity,
    message: message ?? this.message,
    offset: offset.present ? offset.value : this.offset,
    createdAt: createdAt ?? this.createdAt,
  );
  ImportReportRow copyWithCompanion(ImportReportsCompanion data) {
    return ImportReportRow(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      code: data.code.present ? data.code.value : this.code,
      severity: data.severity.present ? data.severity.value : this.severity,
      message: data.message.present ? data.message.value : this.message,
      offset: data.offset.present ? data.offset.value : this.offset,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ImportReportRow(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('code: $code, ')
          ..write('severity: $severity, ')
          ..write('message: $message, ')
          ..write('offset: $offset, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, bookId, code, severity, message, offset, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImportReportRow &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.code == this.code &&
          other.severity == this.severity &&
          other.message == this.message &&
          other.offset == this.offset &&
          other.createdAt == this.createdAt);
}

class ImportReportsCompanion extends UpdateCompanion<ImportReportRow> {
  final Value<int> id;
  final Value<int> bookId;
  final Value<String> code;
  final Value<int> severity;
  final Value<String> message;
  final Value<int?> offset;
  final Value<int> createdAt;
  const ImportReportsCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.code = const Value.absent(),
    this.severity = const Value.absent(),
    this.message = const Value.absent(),
    this.offset = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ImportReportsCompanion.insert({
    this.id = const Value.absent(),
    required int bookId,
    required String code,
    this.severity = const Value.absent(),
    required String message,
    this.offset = const Value.absent(),
    required int createdAt,
  }) : bookId = Value(bookId),
       code = Value(code),
       message = Value(message),
       createdAt = Value(createdAt);
  static Insertable<ImportReportRow> custom({
    Expression<int>? id,
    Expression<int>? bookId,
    Expression<String>? code,
    Expression<int>? severity,
    Expression<String>? message,
    Expression<int>? offset,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (code != null) 'code': code,
      if (severity != null) 'severity': severity,
      if (message != null) 'message': message,
      if (offset != null) 'offset': offset,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ImportReportsCompanion copyWith({
    Value<int>? id,
    Value<int>? bookId,
    Value<String>? code,
    Value<int>? severity,
    Value<String>? message,
    Value<int?>? offset,
    Value<int>? createdAt,
  }) {
    return ImportReportsCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      code: code ?? this.code,
      severity: severity ?? this.severity,
      message: message ?? this.message,
      offset: offset ?? this.offset,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<int>(bookId.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (severity.present) {
      map['severity'] = Variable<int>(severity.value);
    }
    if (message.present) {
      map['message'] = Variable<String>(message.value);
    }
    if (offset.present) {
      map['offset'] = Variable<int>(offset.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ImportReportsCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('code: $code, ')
          ..write('severity: $severity, ')
          ..write('message: $message, ')
          ..write('offset: $offset, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $BookReviewsTable extends BookReviews
    with TableInfo<$BookReviewsTable, BookReviewRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookReviewsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<int> bookId = GeneratedColumn<int>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  @override
  late final GeneratedColumn<int> rating = GeneratedColumn<int>(
    'rating',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    bookId,
    rating,
    content,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'book_reviews';
  @override
  VerificationContext validateIntegrity(
    Insertable<BookReviewRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    }
    if (data.containsKey('rating')) {
      context.handle(
        _ratingMeta,
        rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta),
      );
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookId};
  @override
  BookReviewRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookReviewRow(
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}book_id'],
      )!,
      rating: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rating'],
      ),
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $BookReviewsTable createAlias(String alias) {
    return $BookReviewsTable(attachedDatabase, alias);
  }
}

class BookReviewRow extends DataClass implements Insertable<BookReviewRow> {
  /// 所属书籍，同时作为主键。
  final int bookId;

  /// 评分 1～5；null 表示未评分。
  final int? rating;

  /// 书评正文。
  final String content;

  /// 创建时间（毫秒）。
  final int createdAt;

  /// 更新时间（毫秒）。
  final int updatedAt;
  const BookReviewRow({
    required this.bookId,
    this.rating,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_id'] = Variable<int>(bookId);
    if (!nullToAbsent || rating != null) {
      map['rating'] = Variable<int>(rating);
    }
    map['content'] = Variable<String>(content);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  BookReviewsCompanion toCompanion(bool nullToAbsent) {
    return BookReviewsCompanion(
      bookId: Value(bookId),
      rating: rating == null && nullToAbsent
          ? const Value.absent()
          : Value(rating),
      content: Value(content),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory BookReviewRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BookReviewRow(
      bookId: serializer.fromJson<int>(json['bookId']),
      rating: serializer.fromJson<int?>(json['rating']),
      content: serializer.fromJson<String>(json['content']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookId': serializer.toJson<int>(bookId),
      'rating': serializer.toJson<int?>(rating),
      'content': serializer.toJson<String>(content),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  BookReviewRow copyWith({
    int? bookId,
    Value<int?> rating = const Value.absent(),
    String? content,
    int? createdAt,
    int? updatedAt,
  }) => BookReviewRow(
    bookId: bookId ?? this.bookId,
    rating: rating.present ? rating.value : this.rating,
    content: content ?? this.content,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  BookReviewRow copyWithCompanion(BookReviewsCompanion data) {
    return BookReviewRow(
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      rating: data.rating.present ? data.rating.value : this.rating,
      content: data.content.present ? data.content.value : this.content,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BookReviewRow(')
          ..write('bookId: $bookId, ')
          ..write('rating: $rating, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(bookId, rating, content, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookReviewRow &&
          other.bookId == this.bookId &&
          other.rating == this.rating &&
          other.content == this.content &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class BookReviewsCompanion extends UpdateCompanion<BookReviewRow> {
  final Value<int> bookId;
  final Value<int?> rating;
  final Value<String> content;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  const BookReviewsCompanion({
    this.bookId = const Value.absent(),
    this.rating = const Value.absent(),
    this.content = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  BookReviewsCompanion.insert({
    this.bookId = const Value.absent(),
    this.rating = const Value.absent(),
    this.content = const Value.absent(),
    required int createdAt,
    required int updatedAt,
  }) : createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<BookReviewRow> custom({
    Expression<int>? bookId,
    Expression<int>? rating,
    Expression<String>? content,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (bookId != null) 'book_id': bookId,
      if (rating != null) 'rating': rating,
      if (content != null) 'content': content,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  BookReviewsCompanion copyWith({
    Value<int>? bookId,
    Value<int?>? rating,
    Value<String>? content,
    Value<int>? createdAt,
    Value<int>? updatedAt,
  }) {
    return BookReviewsCompanion(
      bookId: bookId ?? this.bookId,
      rating: rating ?? this.rating,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookId.present) {
      map['book_id'] = Variable<int>(bookId.value);
    }
    if (rating.present) {
      map['rating'] = Variable<int>(rating.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookReviewsCompanion(')
          ..write('bookId: $bookId, ')
          ..write('rating: $rating, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ReadingSessionsTable extends ReadingSessions
    with TableInfo<$ReadingSessionsTable, ReadingSessionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReadingSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<int> bookId = GeneratedColumn<int>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<int> startedAt = GeneratedColumn<int>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endedAtMeta = const VerificationMeta(
    'endedAt',
  );
  @override
  late final GeneratedColumn<int> endedAt = GeneratedColumn<int>(
    'ended_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pageTurnsMeta = const VerificationMeta(
    'pageTurns',
  );
  @override
  late final GeneratedColumn<int> pageTurns = GeneratedColumn<int>(
    'page_turns',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _charactersReadMeta = const VerificationMeta(
    'charactersRead',
  );
  @override
  late final GeneratedColumn<int> charactersRead = GeneratedColumn<int>(
    'characters_read',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bookId,
    startedAt,
    endedAt,
    durationMs,
    pageTurns,
    charactersRead,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reading_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReadingSessionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('ended_at')) {
      context.handle(
        _endedAtMeta,
        endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_endedAtMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    } else if (isInserting) {
      context.missing(_durationMsMeta);
    }
    if (data.containsKey('page_turns')) {
      context.handle(
        _pageTurnsMeta,
        pageTurns.isAcceptableOrUnknown(data['page_turns']!, _pageTurnsMeta),
      );
    }
    if (data.containsKey('characters_read')) {
      context.handle(
        _charactersReadMeta,
        charactersRead.isAcceptableOrUnknown(
          data['characters_read']!,
          _charactersReadMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReadingSessionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReadingSessionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}book_id'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}started_at'],
      )!,
      endedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ended_at'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      pageTurns: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_turns'],
      )!,
      charactersRead: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}characters_read'],
      )!,
    );
  }

  @override
  $ReadingSessionsTable createAlias(String alias) {
    return $ReadingSessionsTable(attachedDatabase, alias);
  }
}

class ReadingSessionRow extends DataClass
    implements Insertable<ReadingSessionRow> {
  /// 主键。
  final int id;

  /// 所属书籍，删书时级联删除。
  final int bookId;

  /// 开始时间（毫秒）。
  final int startedAt;

  /// 结束时间（毫秒）。
  final int endedAt;

  /// 有效阅读时长（毫秒）。
  final int durationMs;

  /// 本段阅读的翻页次数。
  final int pageTurns;

  /// 本段阅读翻过页面的非空白字符数。
  final int charactersRead;
  const ReadingSessionRow({
    required this.id,
    required this.bookId,
    required this.startedAt,
    required this.endedAt,
    required this.durationMs,
    required this.pageTurns,
    required this.charactersRead,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['book_id'] = Variable<int>(bookId);
    map['started_at'] = Variable<int>(startedAt);
    map['ended_at'] = Variable<int>(endedAt);
    map['duration_ms'] = Variable<int>(durationMs);
    map['page_turns'] = Variable<int>(pageTurns);
    map['characters_read'] = Variable<int>(charactersRead);
    return map;
  }

  ReadingSessionsCompanion toCompanion(bool nullToAbsent) {
    return ReadingSessionsCompanion(
      id: Value(id),
      bookId: Value(bookId),
      startedAt: Value(startedAt),
      endedAt: Value(endedAt),
      durationMs: Value(durationMs),
      pageTurns: Value(pageTurns),
      charactersRead: Value(charactersRead),
    );
  }

  factory ReadingSessionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReadingSessionRow(
      id: serializer.fromJson<int>(json['id']),
      bookId: serializer.fromJson<int>(json['bookId']),
      startedAt: serializer.fromJson<int>(json['startedAt']),
      endedAt: serializer.fromJson<int>(json['endedAt']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      pageTurns: serializer.fromJson<int>(json['pageTurns']),
      charactersRead: serializer.fromJson<int>(json['charactersRead']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'bookId': serializer.toJson<int>(bookId),
      'startedAt': serializer.toJson<int>(startedAt),
      'endedAt': serializer.toJson<int>(endedAt),
      'durationMs': serializer.toJson<int>(durationMs),
      'pageTurns': serializer.toJson<int>(pageTurns),
      'charactersRead': serializer.toJson<int>(charactersRead),
    };
  }

  ReadingSessionRow copyWith({
    int? id,
    int? bookId,
    int? startedAt,
    int? endedAt,
    int? durationMs,
    int? pageTurns,
    int? charactersRead,
  }) => ReadingSessionRow(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt ?? this.endedAt,
    durationMs: durationMs ?? this.durationMs,
    pageTurns: pageTurns ?? this.pageTurns,
    charactersRead: charactersRead ?? this.charactersRead,
  );
  ReadingSessionRow copyWithCompanion(ReadingSessionsCompanion data) {
    return ReadingSessionRow(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      pageTurns: data.pageTurns.present ? data.pageTurns.value : this.pageTurns,
      charactersRead: data.charactersRead.present
          ? data.charactersRead.value
          : this.charactersRead,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReadingSessionRow(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('durationMs: $durationMs, ')
          ..write('pageTurns: $pageTurns, ')
          ..write('charactersRead: $charactersRead')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    bookId,
    startedAt,
    endedAt,
    durationMs,
    pageTurns,
    charactersRead,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReadingSessionRow &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt &&
          other.durationMs == this.durationMs &&
          other.pageTurns == this.pageTurns &&
          other.charactersRead == this.charactersRead);
}

class ReadingSessionsCompanion extends UpdateCompanion<ReadingSessionRow> {
  final Value<int> id;
  final Value<int> bookId;
  final Value<int> startedAt;
  final Value<int> endedAt;
  final Value<int> durationMs;
  final Value<int> pageTurns;
  final Value<int> charactersRead;
  const ReadingSessionsCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.pageTurns = const Value.absent(),
    this.charactersRead = const Value.absent(),
  });
  ReadingSessionsCompanion.insert({
    this.id = const Value.absent(),
    required int bookId,
    required int startedAt,
    required int endedAt,
    required int durationMs,
    this.pageTurns = const Value.absent(),
    this.charactersRead = const Value.absent(),
  }) : bookId = Value(bookId),
       startedAt = Value(startedAt),
       endedAt = Value(endedAt),
       durationMs = Value(durationMs);
  static Insertable<ReadingSessionRow> custom({
    Expression<int>? id,
    Expression<int>? bookId,
    Expression<int>? startedAt,
    Expression<int>? endedAt,
    Expression<int>? durationMs,
    Expression<int>? pageTurns,
    Expression<int>? charactersRead,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (durationMs != null) 'duration_ms': durationMs,
      if (pageTurns != null) 'page_turns': pageTurns,
      if (charactersRead != null) 'characters_read': charactersRead,
    });
  }

  ReadingSessionsCompanion copyWith({
    Value<int>? id,
    Value<int>? bookId,
    Value<int>? startedAt,
    Value<int>? endedAt,
    Value<int>? durationMs,
    Value<int>? pageTurns,
    Value<int>? charactersRead,
  }) {
    return ReadingSessionsCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      durationMs: durationMs ?? this.durationMs,
      pageTurns: pageTurns ?? this.pageTurns,
      charactersRead: charactersRead ?? this.charactersRead,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<int>(bookId.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<int>(startedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<int>(endedAt.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (pageTurns.present) {
      map['page_turns'] = Variable<int>(pageTurns.value);
    }
    if (charactersRead.present) {
      map['characters_read'] = Variable<int>(charactersRead.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReadingSessionsCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('durationMs: $durationMs, ')
          ..write('pageTurns: $pageTurns, ')
          ..write('charactersRead: $charactersRead')
          ..write(')'))
        .toString();
  }
}

class $ShelfGroupsTable extends ShelfGroups
    with TableInfo<$ShelfGroupsTable, ShelfGroupRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ShelfGroupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'shelf_groups';
  @override
  VerificationContext validateIntegrity(
    Insertable<ShelfGroupRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ShelfGroupRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ShelfGroupRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ShelfGroupsTable createAlias(String alias) {
    return $ShelfGroupsTable(attachedDatabase, alias);
  }
}

class ShelfGroupRow extends DataClass implements Insertable<ShelfGroupRow> {
  /// 分组标识。
  final String id;

  /// 分组名称。
  final String name;

  /// 创建时间（毫秒）。
  final int createdAt;
  const ShelfGroupRow({
    required this.id,
    required this.name,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  ShelfGroupsCompanion toCompanion(bool nullToAbsent) {
    return ShelfGroupsCompanion(
      id: Value(id),
      name: Value(name),
      createdAt: Value(createdAt),
    );
  }

  factory ShelfGroupRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ShelfGroupRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  ShelfGroupRow copyWith({String? id, String? name, int? createdAt}) =>
      ShelfGroupRow(
        id: id ?? this.id,
        name: name ?? this.name,
        createdAt: createdAt ?? this.createdAt,
      );
  ShelfGroupRow copyWithCompanion(ShelfGroupsCompanion data) {
    return ShelfGroupRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ShelfGroupRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ShelfGroupRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.createdAt == this.createdAt);
}

class ShelfGroupsCompanion extends UpdateCompanion<ShelfGroupRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> createdAt;
  final Value<int> rowid;
  const ShelfGroupsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ShelfGroupsCompanion.insert({
    required String id,
    required String name,
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt);
  static Insertable<ShelfGroupRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ShelfGroupsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return ShelfGroupsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ShelfGroupsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ShelfGroupBooksTable extends ShelfGroupBooks
    with TableInfo<$ShelfGroupBooksTable, ShelfGroupBookRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ShelfGroupBooksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookUuidMeta = const VerificationMeta(
    'bookUuid',
  );
  @override
  late final GeneratedColumn<String> bookUuid = GeneratedColumn<String>(
    'book_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES shelf_groups (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [bookUuid, groupId, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'shelf_group_books';
  @override
  VerificationContext validateIntegrity(
    Insertable<ShelfGroupBookRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_uuid')) {
      context.handle(
        _bookUuidMeta,
        bookUuid.isAcceptableOrUnknown(data['book_uuid']!, _bookUuidMeta),
      );
    } else if (isInserting) {
      context.missing(_bookUuidMeta);
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookUuid};
  @override
  ShelfGroupBookRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ShelfGroupBookRow(
      bookUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_uuid'],
      )!,
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ShelfGroupBooksTable createAlias(String alias) {
    return $ShelfGroupBooksTable(attachedDatabase, alias);
  }
}

class ShelfGroupBookRow extends DataClass
    implements Insertable<ShelfGroupBookRow> {
  /// 书籍 uuid（`books.uuid`）；删书走软删除，归属保留供重新导入恢复。
  final String bookUuid;

  /// 所属分组。
  final String groupId;

  /// 加入分组时间（毫秒）。
  final int createdAt;
  const ShelfGroupBookRow({
    required this.bookUuid,
    required this.groupId,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_uuid'] = Variable<String>(bookUuid);
    map['group_id'] = Variable<String>(groupId);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  ShelfGroupBooksCompanion toCompanion(bool nullToAbsent) {
    return ShelfGroupBooksCompanion(
      bookUuid: Value(bookUuid),
      groupId: Value(groupId),
      createdAt: Value(createdAt),
    );
  }

  factory ShelfGroupBookRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ShelfGroupBookRow(
      bookUuid: serializer.fromJson<String>(json['bookUuid']),
      groupId: serializer.fromJson<String>(json['groupId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookUuid': serializer.toJson<String>(bookUuid),
      'groupId': serializer.toJson<String>(groupId),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  ShelfGroupBookRow copyWith({
    String? bookUuid,
    String? groupId,
    int? createdAt,
  }) => ShelfGroupBookRow(
    bookUuid: bookUuid ?? this.bookUuid,
    groupId: groupId ?? this.groupId,
    createdAt: createdAt ?? this.createdAt,
  );
  ShelfGroupBookRow copyWithCompanion(ShelfGroupBooksCompanion data) {
    return ShelfGroupBookRow(
      bookUuid: data.bookUuid.present ? data.bookUuid.value : this.bookUuid,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ShelfGroupBookRow(')
          ..write('bookUuid: $bookUuid, ')
          ..write('groupId: $groupId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(bookUuid, groupId, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ShelfGroupBookRow &&
          other.bookUuid == this.bookUuid &&
          other.groupId == this.groupId &&
          other.createdAt == this.createdAt);
}

class ShelfGroupBooksCompanion extends UpdateCompanion<ShelfGroupBookRow> {
  final Value<String> bookUuid;
  final Value<String> groupId;
  final Value<int> createdAt;
  final Value<int> rowid;
  const ShelfGroupBooksCompanion({
    this.bookUuid = const Value.absent(),
    this.groupId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ShelfGroupBooksCompanion.insert({
    required String bookUuid,
    required String groupId,
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : bookUuid = Value(bookUuid),
       groupId = Value(groupId),
       createdAt = Value(createdAt);
  static Insertable<ShelfGroupBookRow> custom({
    Expression<String>? bookUuid,
    Expression<String>? groupId,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookUuid != null) 'book_uuid': bookUuid,
      if (groupId != null) 'group_id': groupId,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ShelfGroupBooksCompanion copyWith({
    Value<String>? bookUuid,
    Value<String>? groupId,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return ShelfGroupBooksCompanion(
      bookUuid: bookUuid ?? this.bookUuid,
      groupId: groupId ?? this.groupId,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookUuid.present) {
      map['book_uuid'] = Variable<String>(bookUuid.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ShelfGroupBooksCompanion(')
          ..write('bookUuid: $bookUuid, ')
          ..write('groupId: $groupId, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BookTagsTable extends BookTags
    with TableInfo<$BookTagsTable, BookTagRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookTagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'book_tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<BookTagRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BookTagRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookTagRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $BookTagsTable createAlias(String alias) {
    return $BookTagsTable(attachedDatabase, alias);
  }
}

class BookTagRow extends DataClass implements Insertable<BookTagRow> {
  /// 标签标识。
  final String id;

  /// 标签名称（全局唯一）。
  final String name;

  /// 创建时间（毫秒）。
  final int createdAt;
  const BookTagRow({
    required this.id,
    required this.name,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  BookTagsCompanion toCompanion(bool nullToAbsent) {
    return BookTagsCompanion(
      id: Value(id),
      name: Value(name),
      createdAt: Value(createdAt),
    );
  }

  factory BookTagRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BookTagRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  BookTagRow copyWith({String? id, String? name, int? createdAt}) => BookTagRow(
    id: id ?? this.id,
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
  );
  BookTagRow copyWithCompanion(BookTagsCompanion data) {
    return BookTagRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BookTagRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookTagRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.createdAt == this.createdAt);
}

class BookTagsCompanion extends UpdateCompanion<BookTagRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> createdAt;
  final Value<int> rowid;
  const BookTagsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BookTagsCompanion.insert({
    required String id,
    required String name,
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt);
  static Insertable<BookTagRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BookTagsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return BookTagsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookTagsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BookTagLinksTable extends BookTagLinks
    with TableInfo<$BookTagLinksTable, BookTagLinkRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookTagLinksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookUuidMeta = const VerificationMeta(
    'bookUuid',
  );
  @override
  late final GeneratedColumn<String> bookUuid = GeneratedColumn<String>(
    'book_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tagIdMeta = const VerificationMeta('tagId');
  @override
  late final GeneratedColumn<String> tagId = GeneratedColumn<String>(
    'tag_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES book_tags (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [bookUuid, tagId, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'book_tag_links';
  @override
  VerificationContext validateIntegrity(
    Insertable<BookTagLinkRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_uuid')) {
      context.handle(
        _bookUuidMeta,
        bookUuid.isAcceptableOrUnknown(data['book_uuid']!, _bookUuidMeta),
      );
    } else if (isInserting) {
      context.missing(_bookUuidMeta);
    }
    if (data.containsKey('tag_id')) {
      context.handle(
        _tagIdMeta,
        tagId.isAcceptableOrUnknown(data['tag_id']!, _tagIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tagIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookUuid, tagId};
  @override
  BookTagLinkRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookTagLinkRow(
      bookUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_uuid'],
      )!,
      tagId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $BookTagLinksTable createAlias(String alias) {
    return $BookTagLinksTable(attachedDatabase, alias);
  }
}

class BookTagLinkRow extends DataClass implements Insertable<BookTagLinkRow> {
  /// 书籍 uuid（`books.uuid`）；删书走软删除，关联保留供重新导入恢复。
  final String bookUuid;

  /// 标签。
  final String tagId;

  /// 打标签时间（毫秒）。
  final int createdAt;
  const BookTagLinkRow({
    required this.bookUuid,
    required this.tagId,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_uuid'] = Variable<String>(bookUuid);
    map['tag_id'] = Variable<String>(tagId);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  BookTagLinksCompanion toCompanion(bool nullToAbsent) {
    return BookTagLinksCompanion(
      bookUuid: Value(bookUuid),
      tagId: Value(tagId),
      createdAt: Value(createdAt),
    );
  }

  factory BookTagLinkRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BookTagLinkRow(
      bookUuid: serializer.fromJson<String>(json['bookUuid']),
      tagId: serializer.fromJson<String>(json['tagId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookUuid': serializer.toJson<String>(bookUuid),
      'tagId': serializer.toJson<String>(tagId),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  BookTagLinkRow copyWith({String? bookUuid, String? tagId, int? createdAt}) =>
      BookTagLinkRow(
        bookUuid: bookUuid ?? this.bookUuid,
        tagId: tagId ?? this.tagId,
        createdAt: createdAt ?? this.createdAt,
      );
  BookTagLinkRow copyWithCompanion(BookTagLinksCompanion data) {
    return BookTagLinkRow(
      bookUuid: data.bookUuid.present ? data.bookUuid.value : this.bookUuid,
      tagId: data.tagId.present ? data.tagId.value : this.tagId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BookTagLinkRow(')
          ..write('bookUuid: $bookUuid, ')
          ..write('tagId: $tagId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(bookUuid, tagId, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookTagLinkRow &&
          other.bookUuid == this.bookUuid &&
          other.tagId == this.tagId &&
          other.createdAt == this.createdAt);
}

class BookTagLinksCompanion extends UpdateCompanion<BookTagLinkRow> {
  final Value<String> bookUuid;
  final Value<String> tagId;
  final Value<int> createdAt;
  final Value<int> rowid;
  const BookTagLinksCompanion({
    this.bookUuid = const Value.absent(),
    this.tagId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BookTagLinksCompanion.insert({
    required String bookUuid,
    required String tagId,
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : bookUuid = Value(bookUuid),
       tagId = Value(tagId),
       createdAt = Value(createdAt);
  static Insertable<BookTagLinkRow> custom({
    Expression<String>? bookUuid,
    Expression<String>? tagId,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookUuid != null) 'book_uuid': bookUuid,
      if (tagId != null) 'tag_id': tagId,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BookTagLinksCompanion copyWith({
    Value<String>? bookUuid,
    Value<String>? tagId,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return BookTagLinksCompanion(
      bookUuid: bookUuid ?? this.bookUuid,
      tagId: tagId ?? this.tagId,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookUuid.present) {
      map['book_uuid'] = Variable<String>(bookUuid.value);
    }
    if (tagId.present) {
      map['tag_id'] = Variable<String>(tagId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookTagLinksCompanion(')
          ..write('bookUuid: $bookUuid, ')
          ..write('tagId: $tagId, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $BooksTable books = $BooksTable(this);
  late final $SpineItemsTable spineItems = $SpineItemsTable(this);
  late final $ChaptersTable chapters = $ChaptersTable(this);
  late final $AnnotationsTable annotations = $AnnotationsTable(this);
  late final $ReadingProgressTable readingProgress = $ReadingProgressTable(
    this,
  );
  late final $UserFontsTable userFonts = $UserFontsTable(this);
  late final $SettingsTableTable settingsTable = $SettingsTableTable(this);
  late final $ImportReportsTable importReports = $ImportReportsTable(this);
  late final $BookReviewsTable bookReviews = $BookReviewsTable(this);
  late final $ReadingSessionsTable readingSessions = $ReadingSessionsTable(
    this,
  );
  late final $ShelfGroupsTable shelfGroups = $ShelfGroupsTable(this);
  late final $ShelfGroupBooksTable shelfGroupBooks = $ShelfGroupBooksTable(
    this,
  );
  late final $BookTagsTable bookTags = $BookTagsTable(this);
  late final $BookTagLinksTable bookTagLinks = $BookTagLinksTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    books,
    spineItems,
    chapters,
    annotations,
    readingProgress,
    userFonts,
    settingsTable,
    importReports,
    bookReviews,
    readingSessions,
    shelfGroups,
    shelfGroupBooks,
    bookTags,
    bookTagLinks,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'books',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('spine_items', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'books',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('chapters', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'books',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('annotations', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'books',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('reading_progress', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'books',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('import_reports', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'books',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('book_reviews', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'books',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('reading_sessions', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'shelf_groups',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('shelf_group_books', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'book_tags',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('book_tag_links', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$BooksTableCreateCompanionBuilder = BooksCompanion Function({
  Value<int> id,
  required String uuid,
  Value<String?> epubIdentifier,
  Value<int> identityVersion,
  Value<String?> legacyUuid,
  required String title,
  Value<String?> author,
  Value<String?> description,
  Value<String?> language,
  required String contentDir,
  Value<String?> sourcePath,
  Value<String?> coverPath,
  Value<int> spineCount,
  Value<int> charCount,
  required int createdAt,
  Value<int?> lastReadAt,
  Value<int> layoutVersion,
  Value<int> level,
  Value<String?> warnings,
  Value<int?> deletedAt,
});
typedef $$BooksTableUpdateCompanionBuilder = BooksCompanion Function({
  Value<int> id,
  Value<String> uuid,
  Value<String?> epubIdentifier,
  Value<int> identityVersion,
  Value<String?> legacyUuid,
  Value<String> title,
  Value<String?> author,
  Value<String?> description,
  Value<String?> language,
  Value<String> contentDir,
  Value<String?> sourcePath,
  Value<String?> coverPath,
  Value<int> spineCount,
  Value<int> charCount,
  Value<int> createdAt,
  Value<int?> lastReadAt,
  Value<int> layoutVersion,
  Value<int> level,
  Value<String?> warnings,
  Value<int?> deletedAt,
});

final class $$BooksTableReferences
    extends BaseReferences<_$AppDatabase, $BooksTable, BookRow> {
  $$BooksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$SpineItemsTable, List<SpineItemRow>>
  _spineItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.spineItems,
    aliasName: 'books__id__spine_items__book_id',
  );

  $$SpineItemsTableProcessedTableManager get spineItemsRefs {
    final manager = $$SpineItemsTableTableManager(
      $_db,
      $_db.spineItems,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_spineItemsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ChaptersTable, List<ChapterRow>>
  _chaptersRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.chapters,
    aliasName: 'books__id__chapters__book_id',
  );

  $$ChaptersTableProcessedTableManager get chaptersRefs {
    final manager = $$ChaptersTableTableManager(
      $_db,
      $_db.chapters,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_chaptersRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$AnnotationsTable, List<AnnotationRow>>
  _annotationsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.annotations,
    aliasName: 'books__id__annotations__book_id',
  );

  $$AnnotationsTableProcessedTableManager get annotationsRefs {
    final manager = $$AnnotationsTableTableManager(
      $_db,
      $_db.annotations,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_annotationsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ReadingProgressTable, List<ProgressRow>>
  _readingProgressRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.readingProgress,
    aliasName: 'books__id__reading_progress__book_id',
  );

  $$ReadingProgressTableProcessedTableManager get readingProgressRefs {
    final manager = $$ReadingProgressTableTableManager(
      $_db,
      $_db.readingProgress,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _readingProgressRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ImportReportsTable, List<ImportReportRow>>
  _importReportsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.importReports,
    aliasName: 'books__id__import_reports__book_id',
  );

  $$ImportReportsTableProcessedTableManager get importReportsRefs {
    final manager = $$ImportReportsTableTableManager(
      $_db,
      $_db.importReports,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_importReportsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$BookReviewsTable, List<BookReviewRow>>
  _bookReviewsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.bookReviews,
    aliasName: 'books__id__book_reviews__book_id',
  );

  $$BookReviewsTableProcessedTableManager get bookReviewsRefs {
    final manager = $$BookReviewsTableTableManager(
      $_db,
      $_db.bookReviews,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_bookReviewsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ReadingSessionsTable, List<ReadingSessionRow>>
  _readingSessionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.readingSessions,
    aliasName: 'books__id__reading_sessions__book_id',
  );

  $$ReadingSessionsTableProcessedTableManager get readingSessionsRefs {
    final manager = $$ReadingSessionsTableTableManager(
      $_db,
      $_db.readingSessions,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _readingSessionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$BooksTableFilterComposer extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get epubIdentifier => $composableBuilder(
    column: $table.epubIdentifier,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get identityVersion => $composableBuilder(
    column: $table.identityVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get legacyUuid => $composableBuilder(
    column: $table.legacyUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentDir => $composableBuilder(
    column: $table.contentDir,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverPath => $composableBuilder(
    column: $table.coverPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get spineCount => $composableBuilder(
    column: $table.spineCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get charCount => $composableBuilder(
    column: $table.charCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get layoutVersion => $composableBuilder(
    column: $table.layoutVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get warnings => $composableBuilder(
    column: $table.warnings,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> spineItemsRefs(
    Expression<bool> Function($$SpineItemsTableFilterComposer f) f,
  ) {
    final $$SpineItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.spineItems,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpineItemsTableFilterComposer(
            $db: $db,
            $table: $db.spineItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> chaptersRefs(
    Expression<bool> Function($$ChaptersTableFilterComposer f) f,
  ) {
    final $$ChaptersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.chapters,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChaptersTableFilterComposer(
            $db: $db,
            $table: $db.chapters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> annotationsRefs(
    Expression<bool> Function($$AnnotationsTableFilterComposer f) f,
  ) {
    final $$AnnotationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.annotations,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AnnotationsTableFilterComposer(
            $db: $db,
            $table: $db.annotations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> readingProgressRefs(
    Expression<bool> Function($$ReadingProgressTableFilterComposer f) f,
  ) {
    final $$ReadingProgressTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.readingProgress,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReadingProgressTableFilterComposer(
            $db: $db,
            $table: $db.readingProgress,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> importReportsRefs(
    Expression<bool> Function($$ImportReportsTableFilterComposer f) f,
  ) {
    final $$ImportReportsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.importReports,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ImportReportsTableFilterComposer(
            $db: $db,
            $table: $db.importReports,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> bookReviewsRefs(
    Expression<bool> Function($$BookReviewsTableFilterComposer f) f,
  ) {
    final $$BookReviewsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookReviews,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookReviewsTableFilterComposer(
            $db: $db,
            $table: $db.bookReviews,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> readingSessionsRefs(
    Expression<bool> Function($$ReadingSessionsTableFilterComposer f) f,
  ) {
    final $$ReadingSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.readingSessions,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReadingSessionsTableFilterComposer(
            $db: $db,
            $table: $db.readingSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BooksTableOrderingComposer
    extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get epubIdentifier => $composableBuilder(
    column: $table.epubIdentifier,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get identityVersion => $composableBuilder(
    column: $table.identityVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get legacyUuid => $composableBuilder(
    column: $table.legacyUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentDir => $composableBuilder(
    column: $table.contentDir,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverPath => $composableBuilder(
    column: $table.coverPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get spineCount => $composableBuilder(
    column: $table.spineCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get charCount => $composableBuilder(
    column: $table.charCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get layoutVersion => $composableBuilder(
    column: $table.layoutVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get warnings => $composableBuilder(
    column: $table.warnings,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BooksTableAnnotationComposer
    extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get uuid =>
      $composableBuilder(column: $table.uuid, builder: (column) => column);

  GeneratedColumn<String> get epubIdentifier => $composableBuilder(
    column: $table.epubIdentifier,
    builder: (column) => column,
  );

  GeneratedColumn<int> get identityVersion => $composableBuilder(
    column: $table.identityVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get legacyUuid => $composableBuilder(
    column: $table.legacyUuid,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get author =>
      $composableBuilder(column: $table.author, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get language =>
      $composableBuilder(column: $table.language, builder: (column) => column);

  GeneratedColumn<String> get contentDir => $composableBuilder(
    column: $table.contentDir,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get coverPath =>
      $composableBuilder(column: $table.coverPath, builder: (column) => column);

  GeneratedColumn<int> get spineCount => $composableBuilder(
    column: $table.spineCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get charCount =>
      $composableBuilder(column: $table.charCount, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get layoutVersion => $composableBuilder(
    column: $table.layoutVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get level =>
      $composableBuilder(column: $table.level, builder: (column) => column);

  GeneratedColumn<String> get warnings =>
      $composableBuilder(column: $table.warnings, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  Expression<T> spineItemsRefs<T extends Object>(
    Expression<T> Function($$SpineItemsTableAnnotationComposer a) f,
  ) {
    final $$SpineItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.spineItems,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpineItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.spineItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> chaptersRefs<T extends Object>(
    Expression<T> Function($$ChaptersTableAnnotationComposer a) f,
  ) {
    final $$ChaptersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.chapters,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChaptersTableAnnotationComposer(
            $db: $db,
            $table: $db.chapters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> annotationsRefs<T extends Object>(
    Expression<T> Function($$AnnotationsTableAnnotationComposer a) f,
  ) {
    final $$AnnotationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.annotations,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AnnotationsTableAnnotationComposer(
            $db: $db,
            $table: $db.annotations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> readingProgressRefs<T extends Object>(
    Expression<T> Function($$ReadingProgressTableAnnotationComposer a) f,
  ) {
    final $$ReadingProgressTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.readingProgress,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReadingProgressTableAnnotationComposer(
            $db: $db,
            $table: $db.readingProgress,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> importReportsRefs<T extends Object>(
    Expression<T> Function($$ImportReportsTableAnnotationComposer a) f,
  ) {
    final $$ImportReportsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.importReports,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ImportReportsTableAnnotationComposer(
            $db: $db,
            $table: $db.importReports,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> bookReviewsRefs<T extends Object>(
    Expression<T> Function($$BookReviewsTableAnnotationComposer a) f,
  ) {
    final $$BookReviewsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookReviews,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookReviewsTableAnnotationComposer(
            $db: $db,
            $table: $db.bookReviews,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> readingSessionsRefs<T extends Object>(
    Expression<T> Function($$ReadingSessionsTableAnnotationComposer a) f,
  ) {
    final $$ReadingSessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.readingSessions,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReadingSessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.readingSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BooksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BooksTable,
          BookRow,
          $$BooksTableFilterComposer,
          $$BooksTableOrderingComposer,
          $$BooksTableAnnotationComposer,
          $$BooksTableCreateCompanionBuilder,
          $$BooksTableUpdateCompanionBuilder,
          (BookRow, $$BooksTableReferences),
          BookRow,
          PrefetchHooks Function({
            bool spineItemsRefs,
            bool chaptersRefs,
            bool annotationsRefs,
            bool readingProgressRefs,
            bool importReportsRefs,
            bool bookReviewsRefs,
            bool readingSessionsRefs,
          })
        > {
  $$BooksTableTableManager(_$AppDatabase db, $BooksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BooksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BooksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BooksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> uuid = const Value.absent(),
                Value<String?> epubIdentifier = const Value.absent(),
                Value<int> identityVersion = const Value.absent(),
                Value<String?> legacyUuid = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> author = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> language = const Value.absent(),
                Value<String> contentDir = const Value.absent(),
                Value<String?> sourcePath = const Value.absent(),
                Value<String?> coverPath = const Value.absent(),
                Value<int> spineCount = const Value.absent(),
                Value<int> charCount = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int?> lastReadAt = const Value.absent(),
                Value<int> layoutVersion = const Value.absent(),
                Value<int> level = const Value.absent(),
                Value<String?> warnings = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
              }) => BooksCompanion(
                id: id,
                uuid: uuid,
                epubIdentifier: epubIdentifier,
                identityVersion: identityVersion,
                legacyUuid: legacyUuid,
                title: title,
                author: author,
                description: description,
                language: language,
                contentDir: contentDir,
                sourcePath: sourcePath,
                coverPath: coverPath,
                spineCount: spineCount,
                charCount: charCount,
                createdAt: createdAt,
                lastReadAt: lastReadAt,
                layoutVersion: layoutVersion,
                level: level,
                warnings: warnings,
                deletedAt: deletedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String uuid,
                Value<String?> epubIdentifier = const Value.absent(),
                Value<int> identityVersion = const Value.absent(),
                Value<String?> legacyUuid = const Value.absent(),
                required String title,
                Value<String?> author = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> language = const Value.absent(),
                required String contentDir,
                Value<String?> sourcePath = const Value.absent(),
                Value<String?> coverPath = const Value.absent(),
                Value<int> spineCount = const Value.absent(),
                Value<int> charCount = const Value.absent(),
                required int createdAt,
                Value<int?> lastReadAt = const Value.absent(),
                Value<int> layoutVersion = const Value.absent(),
                Value<int> level = const Value.absent(),
                Value<String?> warnings = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
              }) => BooksCompanion.insert(
                id: id,
                uuid: uuid,
                epubIdentifier: epubIdentifier,
                identityVersion: identityVersion,
                legacyUuid: legacyUuid,
                title: title,
                author: author,
                description: description,
                language: language,
                contentDir: contentDir,
                sourcePath: sourcePath,
                coverPath: coverPath,
                spineCount: spineCount,
                charCount: charCount,
                createdAt: createdAt,
                lastReadAt: lastReadAt,
                layoutVersion: layoutVersion,
                level: level,
                warnings: warnings,
                deletedAt: deletedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BooksTable, BookRow>(table),
                  $$BooksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                spineItemsRefs = false,
                chaptersRefs = false,
                annotationsRefs = false,
                readingProgressRefs = false,
                importReportsRefs = false,
                bookReviewsRefs = false,
                readingSessionsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (spineItemsRefs) db.spineItems,
                    if (chaptersRefs) db.chapters,
                    if (annotationsRefs) db.annotations,
                    if (readingProgressRefs) db.readingProgress,
                    if (importReportsRefs) db.importReports,
                    if (bookReviewsRefs) db.bookReviews,
                    if (readingSessionsRefs) db.readingSessions,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (spineItemsRefs)
                        await $_getPrefetchedData<
                          BookRow,
                          $BooksTable,
                          SpineItemRow
                        >(
                          currentTable: table,
                          referencedTable: $$BooksTableReferences
                              ._spineItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BooksTableReferences(
                                db,
                                table,
                                p0,
                              ).spineItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.bookId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (chaptersRefs)
                        await $_getPrefetchedData<
                          BookRow,
                          $BooksTable,
                          ChapterRow
                        >(
                          currentTable: table,
                          referencedTable: $$BooksTableReferences
                              ._chaptersRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BooksTableReferences(
                                db,
                                table,
                                p0,
                              ).chaptersRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.bookId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (annotationsRefs)
                        await $_getPrefetchedData<
                          BookRow,
                          $BooksTable,
                          AnnotationRow
                        >(
                          currentTable: table,
                          referencedTable: $$BooksTableReferences
                              ._annotationsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BooksTableReferences(
                                db,
                                table,
                                p0,
                              ).annotationsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.bookId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (readingProgressRefs)
                        await $_getPrefetchedData<
                          BookRow,
                          $BooksTable,
                          ProgressRow
                        >(
                          currentTable: table,
                          referencedTable: $$BooksTableReferences
                              ._readingProgressRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BooksTableReferences(
                                db,
                                table,
                                p0,
                              ).readingProgressRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.bookId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (importReportsRefs)
                        await $_getPrefetchedData<
                          BookRow,
                          $BooksTable,
                          ImportReportRow
                        >(
                          currentTable: table,
                          referencedTable: $$BooksTableReferences
                              ._importReportsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BooksTableReferences(
                                db,
                                table,
                                p0,
                              ).importReportsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.bookId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (bookReviewsRefs)
                        await $_getPrefetchedData<
                          BookRow,
                          $BooksTable,
                          BookReviewRow
                        >(
                          currentTable: table,
                          referencedTable: $$BooksTableReferences
                              ._bookReviewsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BooksTableReferences(
                                db,
                                table,
                                p0,
                              ).bookReviewsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.bookId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (readingSessionsRefs)
                        await $_getPrefetchedData<
                          BookRow,
                          $BooksTable,
                          ReadingSessionRow
                        >(
                          currentTable: table,
                          referencedTable: $$BooksTableReferences
                              ._readingSessionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BooksTableReferences(
                                db,
                                table,
                                p0,
                              ).readingSessionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.bookId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$BooksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BooksTable,
      BookRow,
      $$BooksTableFilterComposer,
      $$BooksTableOrderingComposer,
      $$BooksTableAnnotationComposer,
      $$BooksTableCreateCompanionBuilder,
      $$BooksTableUpdateCompanionBuilder,
      (BookRow, $$BooksTableReferences),
      BookRow,
      PrefetchHooks Function({
        bool spineItemsRefs,
        bool chaptersRefs,
        bool annotationsRefs,
        bool readingProgressRefs,
        bool importReportsRefs,
        bool bookReviewsRefs,
        bool readingSessionsRefs,
      })
    >;
typedef $$SpineItemsTableCreateCompanionBuilder = SpineItemsCompanion Function({
  Value<int> id,
  required int bookId,
  required int spineIndex,
  required String href,
  Value<int> linear,
  Value<int?> byteSize,
  Value<int?> charCount,
  Value<int?> charStart,
});
typedef $$SpineItemsTableUpdateCompanionBuilder = SpineItemsCompanion Function({
  Value<int> id,
  Value<int> bookId,
  Value<int> spineIndex,
  Value<String> href,
  Value<int> linear,
  Value<int?> byteSize,
  Value<int?> charCount,
  Value<int?> charStart,
});

final class $$SpineItemsTableReferences
    extends BaseReferences<_$AppDatabase, $SpineItemsTable, SpineItemRow> {
  $$SpineItemsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BooksTable _bookIdTable(_$AppDatabase db) =>
      db.books.createAlias('spine_items__book_id__books__id');

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<int>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SpineItemsTableFilterComposer
    extends Composer<_$AppDatabase, $SpineItemsTable> {
  $$SpineItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get spineIndex => $composableBuilder(
    column: $table.spineIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get href => $composableBuilder(
    column: $table.href,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get linear => $composableBuilder(
    column: $table.linear,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get charCount => $composableBuilder(
    column: $table.charCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get charStart => $composableBuilder(
    column: $table.charStart,
    builder: (column) => ColumnFilters(column),
  );

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SpineItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $SpineItemsTable> {
  $$SpineItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get spineIndex => $composableBuilder(
    column: $table.spineIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get href => $composableBuilder(
    column: $table.href,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get linear => $composableBuilder(
    column: $table.linear,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get charCount => $composableBuilder(
    column: $table.charCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get charStart => $composableBuilder(
    column: $table.charStart,
    builder: (column) => ColumnOrderings(column),
  );

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SpineItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SpineItemsTable> {
  $$SpineItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get spineIndex => $composableBuilder(
    column: $table.spineIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get href =>
      $composableBuilder(column: $table.href, builder: (column) => column);

  GeneratedColumn<int> get linear =>
      $composableBuilder(column: $table.linear, builder: (column) => column);

  GeneratedColumn<int> get byteSize =>
      $composableBuilder(column: $table.byteSize, builder: (column) => column);

  GeneratedColumn<int> get charCount =>
      $composableBuilder(column: $table.charCount, builder: (column) => column);

  GeneratedColumn<int> get charStart =>
      $composableBuilder(column: $table.charStart, builder: (column) => column);

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SpineItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SpineItemsTable,
          SpineItemRow,
          $$SpineItemsTableFilterComposer,
          $$SpineItemsTableOrderingComposer,
          $$SpineItemsTableAnnotationComposer,
          $$SpineItemsTableCreateCompanionBuilder,
          $$SpineItemsTableUpdateCompanionBuilder,
          (SpineItemRow, $$SpineItemsTableReferences),
          SpineItemRow,
          PrefetchHooks Function({bool bookId})
        > {
  $$SpineItemsTableTableManager(_$AppDatabase db, $SpineItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SpineItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SpineItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SpineItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> bookId = const Value.absent(),
                Value<int> spineIndex = const Value.absent(),
                Value<String> href = const Value.absent(),
                Value<int> linear = const Value.absent(),
                Value<int?> byteSize = const Value.absent(),
                Value<int?> charCount = const Value.absent(),
                Value<int?> charStart = const Value.absent(),
              }) => SpineItemsCompanion(
                id: id,
                bookId: bookId,
                spineIndex: spineIndex,
                href: href,
                linear: linear,
                byteSize: byteSize,
                charCount: charCount,
                charStart: charStart,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int bookId,
                required int spineIndex,
                required String href,
                Value<int> linear = const Value.absent(),
                Value<int?> byteSize = const Value.absent(),
                Value<int?> charCount = const Value.absent(),
                Value<int?> charStart = const Value.absent(),
              }) => SpineItemsCompanion.insert(
                id: id,
                bookId: bookId,
                spineIndex: spineIndex,
                href: href,
                linear: linear,
                byteSize: byteSize,
                charCount: charCount,
                charStart: charStart,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SpineItemsTable, SpineItemRow>(table),
                  $$SpineItemsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (bookId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.bookId,
                        referencedTable: $$SpineItemsTableReferences
                            ._bookIdTable(db),
                        referencedColumn: $$SpineItemsTableReferences
                            ._bookIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SpineItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SpineItemsTable,
      SpineItemRow,
      $$SpineItemsTableFilterComposer,
      $$SpineItemsTableOrderingComposer,
      $$SpineItemsTableAnnotationComposer,
      $$SpineItemsTableCreateCompanionBuilder,
      $$SpineItemsTableUpdateCompanionBuilder,
      (SpineItemRow, $$SpineItemsTableReferences),
      SpineItemRow,
      PrefetchHooks Function({bool bookId})
    >;
typedef $$ChaptersTableCreateCompanionBuilder = ChaptersCompanion Function({
  Value<int> id,
  required int bookId,
  Value<int> depth,
  required String title,
  required String href,
  Value<String?> cfi,
  required int orderIndex,
});
typedef $$ChaptersTableUpdateCompanionBuilder = ChaptersCompanion Function({
  Value<int> id,
  Value<int> bookId,
  Value<int> depth,
  Value<String> title,
  Value<String> href,
  Value<String?> cfi,
  Value<int> orderIndex,
});

final class $$ChaptersTableReferences
    extends BaseReferences<_$AppDatabase, $ChaptersTable, ChapterRow> {
  $$ChaptersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BooksTable _bookIdTable(_$AppDatabase db) =>
      db.books.createAlias('chapters__book_id__books__id');

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<int>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ChaptersTableFilterComposer
    extends Composer<_$AppDatabase, $ChaptersTable> {
  $$ChaptersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get depth => $composableBuilder(
    column: $table.depth,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get href => $composableBuilder(
    column: $table.href,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cfi => $composableBuilder(
    column: $table.cfi,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => ColumnFilters(column),
  );

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChaptersTableOrderingComposer
    extends Composer<_$AppDatabase, $ChaptersTable> {
  $$ChaptersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get depth => $composableBuilder(
    column: $table.depth,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get href => $composableBuilder(
    column: $table.href,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cfi => $composableBuilder(
    column: $table.cfi,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => ColumnOrderings(column),
  );

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChaptersTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChaptersTable> {
  $$ChaptersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get depth =>
      $composableBuilder(column: $table.depth, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get href =>
      $composableBuilder(column: $table.href, builder: (column) => column);

  GeneratedColumn<String> get cfi =>
      $composableBuilder(column: $table.cfi, builder: (column) => column);

  GeneratedColumn<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => column,
  );

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChaptersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChaptersTable,
          ChapterRow,
          $$ChaptersTableFilterComposer,
          $$ChaptersTableOrderingComposer,
          $$ChaptersTableAnnotationComposer,
          $$ChaptersTableCreateCompanionBuilder,
          $$ChaptersTableUpdateCompanionBuilder,
          (ChapterRow, $$ChaptersTableReferences),
          ChapterRow,
          PrefetchHooks Function({bool bookId})
        > {
  $$ChaptersTableTableManager(_$AppDatabase db, $ChaptersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChaptersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChaptersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChaptersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> bookId = const Value.absent(),
                Value<int> depth = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> href = const Value.absent(),
                Value<String?> cfi = const Value.absent(),
                Value<int> orderIndex = const Value.absent(),
              }) => ChaptersCompanion(
                id: id,
                bookId: bookId,
                depth: depth,
                title: title,
                href: href,
                cfi: cfi,
                orderIndex: orderIndex,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int bookId,
                Value<int> depth = const Value.absent(),
                required String title,
                required String href,
                Value<String?> cfi = const Value.absent(),
                required int orderIndex,
              }) => ChaptersCompanion.insert(
                id: id,
                bookId: bookId,
                depth: depth,
                title: title,
                href: href,
                cfi: cfi,
                orderIndex: orderIndex,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ChaptersTable, ChapterRow>(table),
                  $$ChaptersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (bookId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.bookId,
                        referencedTable: $$ChaptersTableReferences._bookIdTable(
                          db,
                        ),
                        referencedColumn: $$ChaptersTableReferences
                            ._bookIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ChaptersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChaptersTable,
      ChapterRow,
      $$ChaptersTableFilterComposer,
      $$ChaptersTableOrderingComposer,
      $$ChaptersTableAnnotationComposer,
      $$ChaptersTableCreateCompanionBuilder,
      $$ChaptersTableUpdateCompanionBuilder,
      (ChapterRow, $$ChaptersTableReferences),
      ChapterRow,
      PrefetchHooks Function({bool bookId})
    >;
typedef $$AnnotationsTableCreateCompanionBuilder =
    AnnotationsCompanion Function({
      required String id,
      required int bookId,
      required int type,
      required String startCfi,
      required String endCfi,
      required String quote,
      Value<String?> contextBefore,
      Value<String?> contextAfter,
      Value<int?> style,
      Value<int?> color,
      Value<String?> note,
      required int createdAt,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$AnnotationsTableUpdateCompanionBuilder =
    AnnotationsCompanion Function({
      Value<String> id,
      Value<int> bookId,
      Value<int> type,
      Value<String> startCfi,
      Value<String> endCfi,
      Value<String> quote,
      Value<String?> contextBefore,
      Value<String?> contextAfter,
      Value<int?> style,
      Value<int?> color,
      Value<String?> note,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

final class $$AnnotationsTableReferences
    extends BaseReferences<_$AppDatabase, $AnnotationsTable, AnnotationRow> {
  $$AnnotationsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BooksTable _bookIdTable(_$AppDatabase db) =>
      db.books.createAlias('annotations__book_id__books__id');

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<int>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$AnnotationsTableFilterComposer
    extends Composer<_$AppDatabase, $AnnotationsTable> {
  $$AnnotationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startCfi => $composableBuilder(
    column: $table.startCfi,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endCfi => $composableBuilder(
    column: $table.endCfi,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get quote => $composableBuilder(
    column: $table.quote,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contextBefore => $composableBuilder(
    column: $table.contextBefore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contextAfter => $composableBuilder(
    column: $table.contextAfter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get style => $composableBuilder(
    column: $table.style,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AnnotationsTableOrderingComposer
    extends Composer<_$AppDatabase, $AnnotationsTable> {
  $$AnnotationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startCfi => $composableBuilder(
    column: $table.startCfi,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endCfi => $composableBuilder(
    column: $table.endCfi,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get quote => $composableBuilder(
    column: $table.quote,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contextBefore => $composableBuilder(
    column: $table.contextBefore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contextAfter => $composableBuilder(
    column: $table.contextAfter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get style => $composableBuilder(
    column: $table.style,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AnnotationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AnnotationsTable> {
  $$AnnotationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get startCfi =>
      $composableBuilder(column: $table.startCfi, builder: (column) => column);

  GeneratedColumn<String> get endCfi =>
      $composableBuilder(column: $table.endCfi, builder: (column) => column);

  GeneratedColumn<String> get quote =>
      $composableBuilder(column: $table.quote, builder: (column) => column);

  GeneratedColumn<String> get contextBefore => $composableBuilder(
    column: $table.contextBefore,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contextAfter => $composableBuilder(
    column: $table.contextAfter,
    builder: (column) => column,
  );

  GeneratedColumn<int> get style =>
      $composableBuilder(column: $table.style, builder: (column) => column);

  GeneratedColumn<int> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AnnotationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AnnotationsTable,
          AnnotationRow,
          $$AnnotationsTableFilterComposer,
          $$AnnotationsTableOrderingComposer,
          $$AnnotationsTableAnnotationComposer,
          $$AnnotationsTableCreateCompanionBuilder,
          $$AnnotationsTableUpdateCompanionBuilder,
          (AnnotationRow, $$AnnotationsTableReferences),
          AnnotationRow,
          PrefetchHooks Function({bool bookId})
        > {
  $$AnnotationsTableTableManager(_$AppDatabase db, $AnnotationsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AnnotationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AnnotationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AnnotationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> bookId = const Value.absent(),
                Value<int> type = const Value.absent(),
                Value<String> startCfi = const Value.absent(),
                Value<String> endCfi = const Value.absent(),
                Value<String> quote = const Value.absent(),
                Value<String?> contextBefore = const Value.absent(),
                Value<String?> contextAfter = const Value.absent(),
                Value<int?> style = const Value.absent(),
                Value<int?> color = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AnnotationsCompanion(
                id: id,
                bookId: bookId,
                type: type,
                startCfi: startCfi,
                endCfi: endCfi,
                quote: quote,
                contextBefore: contextBefore,
                contextAfter: contextAfter,
                style: style,
                color: color,
                note: note,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required int bookId,
                required int type,
                required String startCfi,
                required String endCfi,
                required String quote,
                Value<String?> contextBefore = const Value.absent(),
                Value<String?> contextAfter = const Value.absent(),
                Value<int?> style = const Value.absent(),
                Value<int?> color = const Value.absent(),
                Value<String?> note = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => AnnotationsCompanion.insert(
                id: id,
                bookId: bookId,
                type: type,
                startCfi: startCfi,
                endCfi: endCfi,
                quote: quote,
                contextBefore: contextBefore,
                contextAfter: contextAfter,
                style: style,
                color: color,
                note: note,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AnnotationsTable, AnnotationRow>(table),
                  $$AnnotationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (bookId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.bookId,
                        referencedTable: $$AnnotationsTableReferences
                            ._bookIdTable(db),
                        referencedColumn: $$AnnotationsTableReferences
                            ._bookIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$AnnotationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AnnotationsTable,
      AnnotationRow,
      $$AnnotationsTableFilterComposer,
      $$AnnotationsTableOrderingComposer,
      $$AnnotationsTableAnnotationComposer,
      $$AnnotationsTableCreateCompanionBuilder,
      $$AnnotationsTableUpdateCompanionBuilder,
      (AnnotationRow, $$AnnotationsTableReferences),
      AnnotationRow,
      PrefetchHooks Function({bool bookId})
    >;
typedef $$ReadingProgressTableCreateCompanionBuilder =
    ReadingProgressCompanion Function({
      Value<int> bookId,
      required String locatorCfi,
      Value<int?> spineIndex,
      Value<int?> pageIndex,
      Value<bool> finished,
      Value<double> percent,
      required int updatedAt,
    });
typedef $$ReadingProgressTableUpdateCompanionBuilder =
    ReadingProgressCompanion Function({
      Value<int> bookId,
      Value<String> locatorCfi,
      Value<int?> spineIndex,
      Value<int?> pageIndex,
      Value<bool> finished,
      Value<double> percent,
      Value<int> updatedAt,
    });

final class $$ReadingProgressTableReferences
    extends BaseReferences<_$AppDatabase, $ReadingProgressTable, ProgressRow> {
  $$ReadingProgressTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $BooksTable _bookIdTable(_$AppDatabase db) =>
      db.books.createAlias('reading_progress__book_id__books__id');

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<int>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ReadingProgressTableFilterComposer
    extends Composer<_$AppDatabase, $ReadingProgressTable> {
  $$ReadingProgressTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get locatorCfi => $composableBuilder(
    column: $table.locatorCfi,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get spineIndex => $composableBuilder(
    column: $table.spineIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pageIndex => $composableBuilder(
    column: $table.pageIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get finished => $composableBuilder(
    column: $table.finished,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get percent => $composableBuilder(
    column: $table.percent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingProgressTableOrderingComposer
    extends Composer<_$AppDatabase, $ReadingProgressTable> {
  $$ReadingProgressTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get locatorCfi => $composableBuilder(
    column: $table.locatorCfi,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get spineIndex => $composableBuilder(
    column: $table.spineIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pageIndex => $composableBuilder(
    column: $table.pageIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get finished => $composableBuilder(
    column: $table.finished,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get percent => $composableBuilder(
    column: $table.percent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingProgressTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReadingProgressTable> {
  $$ReadingProgressTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get locatorCfi => $composableBuilder(
    column: $table.locatorCfi,
    builder: (column) => column,
  );

  GeneratedColumn<int> get spineIndex => $composableBuilder(
    column: $table.spineIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get pageIndex =>
      $composableBuilder(column: $table.pageIndex, builder: (column) => column);

  GeneratedColumn<bool> get finished =>
      $composableBuilder(column: $table.finished, builder: (column) => column);

  GeneratedColumn<double> get percent =>
      $composableBuilder(column: $table.percent, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingProgressTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReadingProgressTable,
          ProgressRow,
          $$ReadingProgressTableFilterComposer,
          $$ReadingProgressTableOrderingComposer,
          $$ReadingProgressTableAnnotationComposer,
          $$ReadingProgressTableCreateCompanionBuilder,
          $$ReadingProgressTableUpdateCompanionBuilder,
          (ProgressRow, $$ReadingProgressTableReferences),
          ProgressRow,
          PrefetchHooks Function({bool bookId})
        > {
  $$ReadingProgressTableTableManager(
    _$AppDatabase db,
    $ReadingProgressTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReadingProgressTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReadingProgressTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReadingProgressTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> bookId = const Value.absent(),
                Value<String> locatorCfi = const Value.absent(),
                Value<int?> spineIndex = const Value.absent(),
                Value<int?> pageIndex = const Value.absent(),
                Value<bool> finished = const Value.absent(),
                Value<double> percent = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
              }) => ReadingProgressCompanion(
                bookId: bookId,
                locatorCfi: locatorCfi,
                spineIndex: spineIndex,
                pageIndex: pageIndex,
                finished: finished,
                percent: percent,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> bookId = const Value.absent(),
                required String locatorCfi,
                Value<int?> spineIndex = const Value.absent(),
                Value<int?> pageIndex = const Value.absent(),
                Value<bool> finished = const Value.absent(),
                Value<double> percent = const Value.absent(),
                required int updatedAt,
              }) => ReadingProgressCompanion.insert(
                bookId: bookId,
                locatorCfi: locatorCfi,
                spineIndex: spineIndex,
                pageIndex: pageIndex,
                finished: finished,
                percent: percent,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReadingProgressTable, ProgressRow>(table),
                  $$ReadingProgressTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (bookId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.bookId,
                        referencedTable: $$ReadingProgressTableReferences
                            ._bookIdTable(db),
                        referencedColumn: $$ReadingProgressTableReferences
                            ._bookIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ReadingProgressTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReadingProgressTable,
      ProgressRow,
      $$ReadingProgressTableFilterComposer,
      $$ReadingProgressTableOrderingComposer,
      $$ReadingProgressTableAnnotationComposer,
      $$ReadingProgressTableCreateCompanionBuilder,
      $$ReadingProgressTableUpdateCompanionBuilder,
      (ProgressRow, $$ReadingProgressTableReferences),
      ProgressRow,
      PrefetchHooks Function({bool bookId})
    >;
typedef $$UserFontsTableCreateCompanionBuilder = UserFontsCompanion Function({
  Value<int> id,
  required String family,
  required String filePath,
  Value<int?> weight,
  Value<int?> style,
  Value<String?> displayName,
});
typedef $$UserFontsTableUpdateCompanionBuilder = UserFontsCompanion Function({
  Value<int> id,
  Value<String> family,
  Value<String> filePath,
  Value<int?> weight,
  Value<int?> style,
  Value<String?> displayName,
});

class $$UserFontsTableFilterComposer
    extends Composer<_$AppDatabase, $UserFontsTable> {
  $$UserFontsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get family => $composableBuilder(
    column: $table.family,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get weight => $composableBuilder(
    column: $table.weight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get style => $composableBuilder(
    column: $table.style,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UserFontsTableOrderingComposer
    extends Composer<_$AppDatabase, $UserFontsTable> {
  $$UserFontsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get family => $composableBuilder(
    column: $table.family,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get weight => $composableBuilder(
    column: $table.weight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get style => $composableBuilder(
    column: $table.style,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UserFontsTableAnnotationComposer
    extends Composer<_$AppDatabase, $UserFontsTable> {
  $$UserFontsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get family =>
      $composableBuilder(column: $table.family, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<int> get weight =>
      $composableBuilder(column: $table.weight, builder: (column) => column);

  GeneratedColumn<int> get style =>
      $composableBuilder(column: $table.style, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );
}

class $$UserFontsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UserFontsTable,
          UserFontRow,
          $$UserFontsTableFilterComposer,
          $$UserFontsTableOrderingComposer,
          $$UserFontsTableAnnotationComposer,
          $$UserFontsTableCreateCompanionBuilder,
          $$UserFontsTableUpdateCompanionBuilder,
          (
            UserFontRow,
            BaseReferences<_$AppDatabase, $UserFontsTable, UserFontRow>,
          ),
          UserFontRow,
          PrefetchHooks Function()
        > {
  $$UserFontsTableTableManager(_$AppDatabase db, $UserFontsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UserFontsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UserFontsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UserFontsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> family = const Value.absent(),
                Value<String> filePath = const Value.absent(),
                Value<int?> weight = const Value.absent(),
                Value<int?> style = const Value.absent(),
                Value<String?> displayName = const Value.absent(),
              }) => UserFontsCompanion(
                id: id,
                family: family,
                filePath: filePath,
                weight: weight,
                style: style,
                displayName: displayName,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String family,
                required String filePath,
                Value<int?> weight = const Value.absent(),
                Value<int?> style = const Value.absent(),
                Value<String?> displayName = const Value.absent(),
              }) => UserFontsCompanion.insert(
                id: id,
                family: family,
                filePath: filePath,
                weight: weight,
                style: style,
                displayName: displayName,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$UserFontsTable, UserFontRow>(table),
                  BaseReferences<_$AppDatabase, $UserFontsTable, UserFontRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UserFontsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UserFontsTable,
      UserFontRow,
      $$UserFontsTableFilterComposer,
      $$UserFontsTableOrderingComposer,
      $$UserFontsTableAnnotationComposer,
      $$UserFontsTableCreateCompanionBuilder,
      $$UserFontsTableUpdateCompanionBuilder,
      (
        UserFontRow,
        BaseReferences<_$AppDatabase, $UserFontsTable, UserFontRow>,
      ),
      UserFontRow,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableTableCreateCompanionBuilder =
    SettingsTableCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SettingsTableTableUpdateCompanionBuilder =
    SettingsTableCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SettingsTableTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTableTable> {
  $$SettingsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTableTable> {
  $$SettingsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTableTable> {
  $$SettingsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsTableTable,
          SettingRow,
          $$SettingsTableTableFilterComposer,
          $$SettingsTableTableOrderingComposer,
          $$SettingsTableTableAnnotationComposer,
          $$SettingsTableTableCreateCompanionBuilder,
          $$SettingsTableTableUpdateCompanionBuilder,
          (
            SettingRow,
            BaseReferences<_$AppDatabase, $SettingsTableTable, SettingRow>,
          ),
          SettingRow,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableTableManager(_$AppDatabase db, $SettingsTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => SettingsTableCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SettingsTableCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettingsTableTable, SettingRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SettingsTableTable,
                    SettingRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsTableTable,
      SettingRow,
      $$SettingsTableTableFilterComposer,
      $$SettingsTableTableOrderingComposer,
      $$SettingsTableTableAnnotationComposer,
      $$SettingsTableTableCreateCompanionBuilder,
      $$SettingsTableTableUpdateCompanionBuilder,
      (
        SettingRow,
        BaseReferences<_$AppDatabase, $SettingsTableTable, SettingRow>,
      ),
      SettingRow,
      PrefetchHooks Function()
    >;
typedef $$ImportReportsTableCreateCompanionBuilder =
    ImportReportsCompanion Function({
      Value<int> id,
      required int bookId,
      required String code,
      Value<int> severity,
      required String message,
      Value<int?> offset,
      required int createdAt,
    });
typedef $$ImportReportsTableUpdateCompanionBuilder =
    ImportReportsCompanion Function({
      Value<int> id,
      Value<int> bookId,
      Value<String> code,
      Value<int> severity,
      Value<String> message,
      Value<int?> offset,
      Value<int> createdAt,
    });

final class $$ImportReportsTableReferences
    extends
        BaseReferences<_$AppDatabase, $ImportReportsTable, ImportReportRow> {
  $$ImportReportsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $BooksTable _bookIdTable(_$AppDatabase db) =>
      db.books.createAlias('import_reports__book_id__books__id');

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<int>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ImportReportsTableFilterComposer
    extends Composer<_$AppDatabase, $ImportReportsTable> {
  $$ImportReportsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get severity => $composableBuilder(
    column: $table.severity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get offset => $composableBuilder(
    column: $table.offset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ImportReportsTableOrderingComposer
    extends Composer<_$AppDatabase, $ImportReportsTable> {
  $$ImportReportsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get severity => $composableBuilder(
    column: $table.severity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get offset => $composableBuilder(
    column: $table.offset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ImportReportsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ImportReportsTable> {
  $$ImportReportsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<int> get severity =>
      $composableBuilder(column: $table.severity, builder: (column) => column);

  GeneratedColumn<String> get message =>
      $composableBuilder(column: $table.message, builder: (column) => column);

  GeneratedColumn<int> get offset =>
      $composableBuilder(column: $table.offset, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ImportReportsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ImportReportsTable,
          ImportReportRow,
          $$ImportReportsTableFilterComposer,
          $$ImportReportsTableOrderingComposer,
          $$ImportReportsTableAnnotationComposer,
          $$ImportReportsTableCreateCompanionBuilder,
          $$ImportReportsTableUpdateCompanionBuilder,
          (ImportReportRow, $$ImportReportsTableReferences),
          ImportReportRow,
          PrefetchHooks Function({bool bookId})
        > {
  $$ImportReportsTableTableManager(_$AppDatabase db, $ImportReportsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ImportReportsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ImportReportsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ImportReportsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> bookId = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<int> severity = const Value.absent(),
                Value<String> message = const Value.absent(),
                Value<int?> offset = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
              }) => ImportReportsCompanion(
                id: id,
                bookId: bookId,
                code: code,
                severity: severity,
                message: message,
                offset: offset,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int bookId,
                required String code,
                Value<int> severity = const Value.absent(),
                required String message,
                Value<int?> offset = const Value.absent(),
                required int createdAt,
              }) => ImportReportsCompanion.insert(
                id: id,
                bookId: bookId,
                code: code,
                severity: severity,
                message: message,
                offset: offset,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ImportReportsTable, ImportReportRow>(table),
                  $$ImportReportsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (bookId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.bookId,
                        referencedTable: $$ImportReportsTableReferences
                            ._bookIdTable(db),
                        referencedColumn: $$ImportReportsTableReferences
                            ._bookIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ImportReportsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ImportReportsTable,
      ImportReportRow,
      $$ImportReportsTableFilterComposer,
      $$ImportReportsTableOrderingComposer,
      $$ImportReportsTableAnnotationComposer,
      $$ImportReportsTableCreateCompanionBuilder,
      $$ImportReportsTableUpdateCompanionBuilder,
      (ImportReportRow, $$ImportReportsTableReferences),
      ImportReportRow,
      PrefetchHooks Function({bool bookId})
    >;
typedef $$BookReviewsTableCreateCompanionBuilder =
    BookReviewsCompanion Function({
      Value<int> bookId,
      Value<int?> rating,
      Value<String> content,
      required int createdAt,
      required int updatedAt,
    });
typedef $$BookReviewsTableUpdateCompanionBuilder =
    BookReviewsCompanion Function({
      Value<int> bookId,
      Value<int?> rating,
      Value<String> content,
      Value<int> createdAt,
      Value<int> updatedAt,
    });

final class $$BookReviewsTableReferences
    extends BaseReferences<_$AppDatabase, $BookReviewsTable, BookReviewRow> {
  $$BookReviewsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BooksTable _bookIdTable(_$AppDatabase db) =>
      db.books.createAlias('book_reviews__book_id__books__id');

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<int>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$BookReviewsTableFilterComposer
    extends Composer<_$AppDatabase, $BookReviewsTable> {
  $$BookReviewsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookReviewsTableOrderingComposer
    extends Composer<_$AppDatabase, $BookReviewsTable> {
  $$BookReviewsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookReviewsTableAnnotationComposer
    extends Composer<_$AppDatabase, $BookReviewsTable> {
  $$BookReviewsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookReviewsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BookReviewsTable,
          BookReviewRow,
          $$BookReviewsTableFilterComposer,
          $$BookReviewsTableOrderingComposer,
          $$BookReviewsTableAnnotationComposer,
          $$BookReviewsTableCreateCompanionBuilder,
          $$BookReviewsTableUpdateCompanionBuilder,
          (BookReviewRow, $$BookReviewsTableReferences),
          BookReviewRow,
          PrefetchHooks Function({bool bookId})
        > {
  $$BookReviewsTableTableManager(_$AppDatabase db, $BookReviewsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BookReviewsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BookReviewsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BookReviewsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> bookId = const Value.absent(),
                Value<int?> rating = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
              }) => BookReviewsCompanion(
                bookId: bookId,
                rating: rating,
                content: content,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> bookId = const Value.absent(),
                Value<int?> rating = const Value.absent(),
                Value<String> content = const Value.absent(),
                required int createdAt,
                required int updatedAt,
              }) => BookReviewsCompanion.insert(
                bookId: bookId,
                rating: rating,
                content: content,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BookReviewsTable, BookReviewRow>(table),
                  $$BookReviewsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (bookId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.bookId,
                        referencedTable: $$BookReviewsTableReferences
                            ._bookIdTable(db),
                        referencedColumn: $$BookReviewsTableReferences
                            ._bookIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$BookReviewsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BookReviewsTable,
      BookReviewRow,
      $$BookReviewsTableFilterComposer,
      $$BookReviewsTableOrderingComposer,
      $$BookReviewsTableAnnotationComposer,
      $$BookReviewsTableCreateCompanionBuilder,
      $$BookReviewsTableUpdateCompanionBuilder,
      (BookReviewRow, $$BookReviewsTableReferences),
      BookReviewRow,
      PrefetchHooks Function({bool bookId})
    >;
typedef $$ReadingSessionsTableCreateCompanionBuilder =
    ReadingSessionsCompanion Function({
      Value<int> id,
      required int bookId,
      required int startedAt,
      required int endedAt,
      required int durationMs,
      Value<int> pageTurns,
      Value<int> charactersRead,
    });
typedef $$ReadingSessionsTableUpdateCompanionBuilder =
    ReadingSessionsCompanion Function({
      Value<int> id,
      Value<int> bookId,
      Value<int> startedAt,
      Value<int> endedAt,
      Value<int> durationMs,
      Value<int> pageTurns,
      Value<int> charactersRead,
    });

final class $$ReadingSessionsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ReadingSessionsTable,
          ReadingSessionRow
        > {
  $$ReadingSessionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $BooksTable _bookIdTable(_$AppDatabase db) =>
      db.books.createAlias('reading_sessions__book_id__books__id');

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<int>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ReadingSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $ReadingSessionsTable> {
  $$ReadingSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pageTurns => $composableBuilder(
    column: $table.pageTurns,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get charactersRead => $composableBuilder(
    column: $table.charactersRead,
    builder: (column) => ColumnFilters(column),
  );

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReadingSessionsTable> {
  $$ReadingSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pageTurns => $composableBuilder(
    column: $table.pageTurns,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get charactersRead => $composableBuilder(
    column: $table.charactersRead,
    builder: (column) => ColumnOrderings(column),
  );

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReadingSessionsTable> {
  $$ReadingSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<int> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get pageTurns =>
      $composableBuilder(column: $table.pageTurns, builder: (column) => column);

  GeneratedColumn<int> get charactersRead => $composableBuilder(
    column: $table.charactersRead,
    builder: (column) => column,
  );

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReadingSessionsTable,
          ReadingSessionRow,
          $$ReadingSessionsTableFilterComposer,
          $$ReadingSessionsTableOrderingComposer,
          $$ReadingSessionsTableAnnotationComposer,
          $$ReadingSessionsTableCreateCompanionBuilder,
          $$ReadingSessionsTableUpdateCompanionBuilder,
          (ReadingSessionRow, $$ReadingSessionsTableReferences),
          ReadingSessionRow,
          PrefetchHooks Function({bool bookId})
        > {
  $$ReadingSessionsTableTableManager(
    _$AppDatabase db,
    $ReadingSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReadingSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReadingSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReadingSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> bookId = const Value.absent(),
                Value<int> startedAt = const Value.absent(),
                Value<int> endedAt = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<int> pageTurns = const Value.absent(),
                Value<int> charactersRead = const Value.absent(),
              }) => ReadingSessionsCompanion(
                id: id,
                bookId: bookId,
                startedAt: startedAt,
                endedAt: endedAt,
                durationMs: durationMs,
                pageTurns: pageTurns,
                charactersRead: charactersRead,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int bookId,
                required int startedAt,
                required int endedAt,
                required int durationMs,
                Value<int> pageTurns = const Value.absent(),
                Value<int> charactersRead = const Value.absent(),
              }) => ReadingSessionsCompanion.insert(
                id: id,
                bookId: bookId,
                startedAt: startedAt,
                endedAt: endedAt,
                durationMs: durationMs,
                pageTurns: pageTurns,
                charactersRead: charactersRead,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReadingSessionsTable, ReadingSessionRow>(table),
                  $$ReadingSessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (bookId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.bookId,
                        referencedTable: $$ReadingSessionsTableReferences
                            ._bookIdTable(db),
                        referencedColumn: $$ReadingSessionsTableReferences
                            ._bookIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ReadingSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReadingSessionsTable,
      ReadingSessionRow,
      $$ReadingSessionsTableFilterComposer,
      $$ReadingSessionsTableOrderingComposer,
      $$ReadingSessionsTableAnnotationComposer,
      $$ReadingSessionsTableCreateCompanionBuilder,
      $$ReadingSessionsTableUpdateCompanionBuilder,
      (ReadingSessionRow, $$ReadingSessionsTableReferences),
      ReadingSessionRow,
      PrefetchHooks Function({bool bookId})
    >;
typedef $$ShelfGroupsTableCreateCompanionBuilder =
    ShelfGroupsCompanion Function({
      required String id,
      required String name,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$ShelfGroupsTableUpdateCompanionBuilder =
    ShelfGroupsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<int> createdAt,
      Value<int> rowid,
    });

final class $$ShelfGroupsTableReferences
    extends BaseReferences<_$AppDatabase, $ShelfGroupsTable, ShelfGroupRow> {
  $$ShelfGroupsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ShelfGroupBooksTable, List<ShelfGroupBookRow>>
  _shelfGroupBooksRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.shelfGroupBooks,
    aliasName: 'shelf_groups__id__shelf_group_books__group_id',
  );

  $$ShelfGroupBooksTableProcessedTableManager get shelfGroupBooksRefs {
    final manager = $$ShelfGroupBooksTableTableManager(
      $_db,
      $_db.shelfGroupBooks,
    ).filter((f) => f.groupId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _shelfGroupBooksRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ShelfGroupsTableFilterComposer
    extends Composer<_$AppDatabase, $ShelfGroupsTable> {
  $$ShelfGroupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> shelfGroupBooksRefs(
    Expression<bool> Function($$ShelfGroupBooksTableFilterComposer f) f,
  ) {
    final $$ShelfGroupBooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.shelfGroupBooks,
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShelfGroupBooksTableFilterComposer(
            $db: $db,
            $table: $db.shelfGroupBooks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ShelfGroupsTableOrderingComposer
    extends Composer<_$AppDatabase, $ShelfGroupsTable> {
  $$ShelfGroupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ShelfGroupsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ShelfGroupsTable> {
  $$ShelfGroupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> shelfGroupBooksRefs<T extends Object>(
    Expression<T> Function($$ShelfGroupBooksTableAnnotationComposer a) f,
  ) {
    final $$ShelfGroupBooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.shelfGroupBooks,
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShelfGroupBooksTableAnnotationComposer(
            $db: $db,
            $table: $db.shelfGroupBooks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ShelfGroupsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ShelfGroupsTable,
          ShelfGroupRow,
          $$ShelfGroupsTableFilterComposer,
          $$ShelfGroupsTableOrderingComposer,
          $$ShelfGroupsTableAnnotationComposer,
          $$ShelfGroupsTableCreateCompanionBuilder,
          $$ShelfGroupsTableUpdateCompanionBuilder,
          (ShelfGroupRow, $$ShelfGroupsTableReferences),
          ShelfGroupRow,
          PrefetchHooks Function({bool shelfGroupBooksRefs})
        > {
  $$ShelfGroupsTableTableManager(_$AppDatabase db, $ShelfGroupsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ShelfGroupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ShelfGroupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ShelfGroupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ShelfGroupsCompanion(
                id: id,
                name: name,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => ShelfGroupsCompanion.insert(
                id: id,
                name: name,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ShelfGroupsTable, ShelfGroupRow>(table),
                  $$ShelfGroupsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({shelfGroupBooksRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (shelfGroupBooksRefs) db.shelfGroupBooks,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (shelfGroupBooksRefs)
                    await $_getPrefetchedData<
                      ShelfGroupRow,
                      $ShelfGroupsTable,
                      ShelfGroupBookRow
                    >(
                      currentTable: table,
                      referencedTable: $$ShelfGroupsTableReferences
                          ._shelfGroupBooksRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$ShelfGroupsTableReferences(
                            db,
                            table,
                            p0,
                          ).shelfGroupBooksRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.groupId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ShelfGroupsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ShelfGroupsTable,
      ShelfGroupRow,
      $$ShelfGroupsTableFilterComposer,
      $$ShelfGroupsTableOrderingComposer,
      $$ShelfGroupsTableAnnotationComposer,
      $$ShelfGroupsTableCreateCompanionBuilder,
      $$ShelfGroupsTableUpdateCompanionBuilder,
      (ShelfGroupRow, $$ShelfGroupsTableReferences),
      ShelfGroupRow,
      PrefetchHooks Function({bool shelfGroupBooksRefs})
    >;
typedef $$ShelfGroupBooksTableCreateCompanionBuilder =
    ShelfGroupBooksCompanion Function({
      required String bookUuid,
      required String groupId,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$ShelfGroupBooksTableUpdateCompanionBuilder =
    ShelfGroupBooksCompanion Function({
      Value<String> bookUuid,
      Value<String> groupId,
      Value<int> createdAt,
      Value<int> rowid,
    });

final class $$ShelfGroupBooksTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ShelfGroupBooksTable,
          ShelfGroupBookRow
        > {
  $$ShelfGroupBooksTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ShelfGroupsTable _groupIdTable(_$AppDatabase db) => db.shelfGroups
      .createAlias('shelf_group_books__group_id__shelf_groups__id');

  $$ShelfGroupsTableProcessedTableManager get groupId {
    final $_column = $_itemColumn<String>('group_id')!;

    final manager = $$ShelfGroupsTableTableManager(
      $_db,
      $_db.shelfGroups,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_groupIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ShelfGroupBooksTableFilterComposer
    extends Composer<_$AppDatabase, $ShelfGroupBooksTable> {
  $$ShelfGroupBooksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bookUuid => $composableBuilder(
    column: $table.bookUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ShelfGroupsTableFilterComposer get groupId {
    final $$ShelfGroupsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.shelfGroups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShelfGroupsTableFilterComposer(
            $db: $db,
            $table: $db.shelfGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ShelfGroupBooksTableOrderingComposer
    extends Composer<_$AppDatabase, $ShelfGroupBooksTable> {
  $$ShelfGroupBooksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bookUuid => $composableBuilder(
    column: $table.bookUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ShelfGroupsTableOrderingComposer get groupId {
    final $$ShelfGroupsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.shelfGroups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShelfGroupsTableOrderingComposer(
            $db: $db,
            $table: $db.shelfGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ShelfGroupBooksTableAnnotationComposer
    extends Composer<_$AppDatabase, $ShelfGroupBooksTable> {
  $$ShelfGroupBooksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bookUuid =>
      $composableBuilder(column: $table.bookUuid, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$ShelfGroupsTableAnnotationComposer get groupId {
    final $$ShelfGroupsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.shelfGroups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShelfGroupsTableAnnotationComposer(
            $db: $db,
            $table: $db.shelfGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ShelfGroupBooksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ShelfGroupBooksTable,
          ShelfGroupBookRow,
          $$ShelfGroupBooksTableFilterComposer,
          $$ShelfGroupBooksTableOrderingComposer,
          $$ShelfGroupBooksTableAnnotationComposer,
          $$ShelfGroupBooksTableCreateCompanionBuilder,
          $$ShelfGroupBooksTableUpdateCompanionBuilder,
          (ShelfGroupBookRow, $$ShelfGroupBooksTableReferences),
          ShelfGroupBookRow,
          PrefetchHooks Function({bool groupId})
        > {
  $$ShelfGroupBooksTableTableManager(
    _$AppDatabase db,
    $ShelfGroupBooksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ShelfGroupBooksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ShelfGroupBooksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ShelfGroupBooksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> bookUuid = const Value.absent(),
                Value<String> groupId = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ShelfGroupBooksCompanion(
                bookUuid: bookUuid,
                groupId: groupId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookUuid,
                required String groupId,
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => ShelfGroupBooksCompanion.insert(
                bookUuid: bookUuid,
                groupId: groupId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ShelfGroupBooksTable, ShelfGroupBookRow>(table),
                  $$ShelfGroupBooksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({groupId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (groupId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.groupId,
                        referencedTable: $$ShelfGroupBooksTableReferences
                            ._groupIdTable(db),
                        referencedColumn: $$ShelfGroupBooksTableReferences
                            ._groupIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ShelfGroupBooksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ShelfGroupBooksTable,
      ShelfGroupBookRow,
      $$ShelfGroupBooksTableFilterComposer,
      $$ShelfGroupBooksTableOrderingComposer,
      $$ShelfGroupBooksTableAnnotationComposer,
      $$ShelfGroupBooksTableCreateCompanionBuilder,
      $$ShelfGroupBooksTableUpdateCompanionBuilder,
      (ShelfGroupBookRow, $$ShelfGroupBooksTableReferences),
      ShelfGroupBookRow,
      PrefetchHooks Function({bool groupId})
    >;
typedef $$BookTagsTableCreateCompanionBuilder = BookTagsCompanion Function({
  required String id,
  required String name,
  required int createdAt,
  Value<int> rowid,
});
typedef $$BookTagsTableUpdateCompanionBuilder = BookTagsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<int> createdAt,
  Value<int> rowid,
});

final class $$BookTagsTableReferences
    extends BaseReferences<_$AppDatabase, $BookTagsTable, BookTagRow> {
  $$BookTagsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$BookTagLinksTable, List<BookTagLinkRow>>
  _bookTagLinksRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.bookTagLinks,
    aliasName: 'book_tags__id__book_tag_links__tag_id',
  );

  $$BookTagLinksTableProcessedTableManager get bookTagLinksRefs {
    final manager = $$BookTagLinksTableTableManager(
      $_db,
      $_db.bookTagLinks,
    ).filter((f) => f.tagId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_bookTagLinksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$BookTagsTableFilterComposer
    extends Composer<_$AppDatabase, $BookTagsTable> {
  $$BookTagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> bookTagLinksRefs(
    Expression<bool> Function($$BookTagLinksTableFilterComposer f) f,
  ) {
    final $$BookTagLinksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookTagLinks,
      getReferencedColumn: (t) => t.tagId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookTagLinksTableFilterComposer(
            $db: $db,
            $table: $db.bookTagLinks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BookTagsTableOrderingComposer
    extends Composer<_$AppDatabase, $BookTagsTable> {
  $$BookTagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BookTagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $BookTagsTable> {
  $$BookTagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> bookTagLinksRefs<T extends Object>(
    Expression<T> Function($$BookTagLinksTableAnnotationComposer a) f,
  ) {
    final $$BookTagLinksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookTagLinks,
      getReferencedColumn: (t) => t.tagId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookTagLinksTableAnnotationComposer(
            $db: $db,
            $table: $db.bookTagLinks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BookTagsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BookTagsTable,
          BookTagRow,
          $$BookTagsTableFilterComposer,
          $$BookTagsTableOrderingComposer,
          $$BookTagsTableAnnotationComposer,
          $$BookTagsTableCreateCompanionBuilder,
          $$BookTagsTableUpdateCompanionBuilder,
          (BookTagRow, $$BookTagsTableReferences),
          BookTagRow,
          PrefetchHooks Function({bool bookTagLinksRefs})
        > {
  $$BookTagsTableTableManager(_$AppDatabase db, $BookTagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BookTagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BookTagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BookTagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BookTagsCompanion(
                id: id,
                name: name,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => BookTagsCompanion.insert(
                id: id,
                name: name,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BookTagsTable, BookTagRow>(table),
                  $$BookTagsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookTagLinksRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (bookTagLinksRefs) db.bookTagLinks],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (bookTagLinksRefs)
                    await $_getPrefetchedData<
                      BookTagRow,
                      $BookTagsTable,
                      BookTagLinkRow
                    >(
                      currentTable: table,
                      referencedTable: $$BookTagsTableReferences
                          ._bookTagLinksRefsTable(db),
                      managerFromTypedResult: (p0) => $$BookTagsTableReferences(
                        db,
                        table,
                        p0,
                      ).bookTagLinksRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.tagId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$BookTagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BookTagsTable,
      BookTagRow,
      $$BookTagsTableFilterComposer,
      $$BookTagsTableOrderingComposer,
      $$BookTagsTableAnnotationComposer,
      $$BookTagsTableCreateCompanionBuilder,
      $$BookTagsTableUpdateCompanionBuilder,
      (BookTagRow, $$BookTagsTableReferences),
      BookTagRow,
      PrefetchHooks Function({bool bookTagLinksRefs})
    >;
typedef $$BookTagLinksTableCreateCompanionBuilder =
    BookTagLinksCompanion Function({
      required String bookUuid,
      required String tagId,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$BookTagLinksTableUpdateCompanionBuilder =
    BookTagLinksCompanion Function({
      Value<String> bookUuid,
      Value<String> tagId,
      Value<int> createdAt,
      Value<int> rowid,
    });

final class $$BookTagLinksTableReferences
    extends BaseReferences<_$AppDatabase, $BookTagLinksTable, BookTagLinkRow> {
  $$BookTagLinksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BookTagsTable _tagIdTable(_$AppDatabase db) =>
      db.bookTags.createAlias('book_tag_links__tag_id__book_tags__id');

  $$BookTagsTableProcessedTableManager get tagId {
    final $_column = $_itemColumn<String>('tag_id')!;

    final manager = $$BookTagsTableTableManager(
      $_db,
      $_db.bookTags,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_tagIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$BookTagLinksTableFilterComposer
    extends Composer<_$AppDatabase, $BookTagLinksTable> {
  $$BookTagLinksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bookUuid => $composableBuilder(
    column: $table.bookUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BookTagsTableFilterComposer get tagId {
    final $$BookTagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.bookTags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookTagsTableFilterComposer(
            $db: $db,
            $table: $db.bookTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookTagLinksTableOrderingComposer
    extends Composer<_$AppDatabase, $BookTagLinksTable> {
  $$BookTagLinksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bookUuid => $composableBuilder(
    column: $table.bookUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BookTagsTableOrderingComposer get tagId {
    final $$BookTagsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.bookTags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookTagsTableOrderingComposer(
            $db: $db,
            $table: $db.bookTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookTagLinksTableAnnotationComposer
    extends Composer<_$AppDatabase, $BookTagLinksTable> {
  $$BookTagLinksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bookUuid =>
      $composableBuilder(column: $table.bookUuid, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$BookTagsTableAnnotationComposer get tagId {
    final $$BookTagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.bookTags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookTagsTableAnnotationComposer(
            $db: $db,
            $table: $db.bookTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookTagLinksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BookTagLinksTable,
          BookTagLinkRow,
          $$BookTagLinksTableFilterComposer,
          $$BookTagLinksTableOrderingComposer,
          $$BookTagLinksTableAnnotationComposer,
          $$BookTagLinksTableCreateCompanionBuilder,
          $$BookTagLinksTableUpdateCompanionBuilder,
          (BookTagLinkRow, $$BookTagLinksTableReferences),
          BookTagLinkRow,
          PrefetchHooks Function({bool tagId})
        > {
  $$BookTagLinksTableTableManager(_$AppDatabase db, $BookTagLinksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BookTagLinksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BookTagLinksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BookTagLinksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> bookUuid = const Value.absent(),
                Value<String> tagId = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BookTagLinksCompanion(
                bookUuid: bookUuid,
                tagId: tagId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookUuid,
                required String tagId,
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => BookTagLinksCompanion.insert(
                bookUuid: bookUuid,
                tagId: tagId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BookTagLinksTable, BookTagLinkRow>(table),
                  $$BookTagLinksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({tagId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (tagId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.tagId,
                        referencedTable: $$BookTagLinksTableReferences
                            ._tagIdTable(db),
                        referencedColumn: $$BookTagLinksTableReferences
                            ._tagIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$BookTagLinksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BookTagLinksTable,
      BookTagLinkRow,
      $$BookTagLinksTableFilterComposer,
      $$BookTagLinksTableOrderingComposer,
      $$BookTagLinksTableAnnotationComposer,
      $$BookTagLinksTableCreateCompanionBuilder,
      $$BookTagLinksTableUpdateCompanionBuilder,
      (BookTagLinkRow, $$BookTagLinksTableReferences),
      BookTagLinkRow,
      PrefetchHooks Function({bool tagId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$BooksTableTableManager get books =>
      $$BooksTableTableManager(_db, _db.books);
  $$SpineItemsTableTableManager get spineItems =>
      $$SpineItemsTableTableManager(_db, _db.spineItems);
  $$ChaptersTableTableManager get chapters =>
      $$ChaptersTableTableManager(_db, _db.chapters);
  $$AnnotationsTableTableManager get annotations =>
      $$AnnotationsTableTableManager(_db, _db.annotations);
  $$ReadingProgressTableTableManager get readingProgress =>
      $$ReadingProgressTableTableManager(_db, _db.readingProgress);
  $$UserFontsTableTableManager get userFonts =>
      $$UserFontsTableTableManager(_db, _db.userFonts);
  $$SettingsTableTableTableManager get settingsTable =>
      $$SettingsTableTableTableManager(_db, _db.settingsTable);
  $$ImportReportsTableTableManager get importReports =>
      $$ImportReportsTableTableManager(_db, _db.importReports);
  $$BookReviewsTableTableManager get bookReviews =>
      $$BookReviewsTableTableManager(_db, _db.bookReviews);
  $$ReadingSessionsTableTableManager get readingSessions =>
      $$ReadingSessionsTableTableManager(_db, _db.readingSessions);
  $$ShelfGroupsTableTableManager get shelfGroups =>
      $$ShelfGroupsTableTableManager(_db, _db.shelfGroups);
  $$ShelfGroupBooksTableTableManager get shelfGroupBooks =>
      $$ShelfGroupBooksTableTableManager(_db, _db.shelfGroupBooks);
  $$BookTagsTableTableManager get bookTags =>
      $$BookTagsTableTableManager(_db, _db.bookTags);
  $$BookTagLinksTableTableManager get bookTagLinks =>
      $$BookTagLinksTableTableManager(_db, _db.bookTagLinks);
}
