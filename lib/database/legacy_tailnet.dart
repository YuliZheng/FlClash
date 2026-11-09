part of 'database.dart';

extension _LegacyTailnetMigration on Database {
  Future<void> _backupLegacyTailnetDatabase() async {
    final path = await _legacyBackupPath;
    if (path == null || await File(path).exists()) return;
    await customStatement('VACUUM INTO ?', [path]);
  }

  Future<void> _migrateLegacyTailnetDatabase(Migrator migrator) async {
    final profileColumns = await _legacyColumns('profiles');
    if (!profileColumns.containsAll({'type', 'extend_type'})) {
      throw StateError('Unrecognized FlClash v21 database');
    }
    final customProfiles = await customSelect(
      "SELECT id FROM profiles WHERE type NOT IN ('file', 'url')",
    ).get();
    if (customProfiles.isNotEmpty) {
      throw StateError(
        'This build supports existing YAML and URL profiles. '
        'Export custom profiles as YAML in the previous version first. '
        'The original database has been preserved.',
      );
    }

    final tablesToMigrate = <TableInfo<Table, dynamic>>[
      profiles,
      scripts,
      rules,
      proxyGroups,
      iconRecords,
    ];
    for (final table in tablesToMigrate) {
      final name = table.actualTableName;
      final indexes = await customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        'AND tbl_name = ? AND sql IS NOT NULL',
        variables: [Variable(name)],
      ).get();
      for (final index in indexes) {
        final identifier = index.read<String>('name').replaceAll('"', '""');
        await customStatement('DROP INDEX "$identifier"');
      }
      await customStatement(
        'ALTER TABLE "$name" RENAME TO "tailnet_v21_$name"',
      );
    }
    await migrator.createAll();
    for (final table in tablesToMigrate) {
      final name = table.actualTableName;
      final oldColumns = await _legacyColumns('tailnet_v21_$name');
      final columns = table.$columns
          .map((column) => column.$name)
          .where(oldColumns.contains)
          .toList();
      final source = columns.map((name) => '"$name"').toList();
      if (name == 'profiles') {
        columns.add('overwrite_type');
        source.add('extend_type');
      }
      await customStatement(
        'INSERT INTO "$name" (${columns.map((name) => '"$name"').join(',')}) '
        'SELECT ${source.join(',')} FROM "tailnet_v21_$name"',
      );
    }

    final oldRules = await customSelect(
      'SELECT id, profile_id, "order" FROM tailnet_v21_rules',
    ).get();
    for (final row in oldRules) {
      final link = ProfileRuleLink(
        ruleId: row.read<int>('id'),
        profileId: row.readNullable<int>('profile_id'),
        scene: row.readNullable<int>('profile_id') == null
            ? null
            : RuleScene.added,
        order: row.readNullable<String>('order'),
      );
      await into(profileRuleLinks).insert(link.toCompanion());
    }
    final tables = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'disabled_rules'",
    ).get();
    if (tables.isNotEmpty) {
      final disabled = await customSelect('SELECT * FROM disabled_rules').get();
      for (final row in disabled) {
        final link = ProfileRuleLink(
          ruleId: row.read<int>('rule_id'),
          profileId: row.read<int>('profile_id'),
          scene: RuleScene.disabled,
        );
        await into(profileRuleLinks).insert(link.toCompanion());
      }
    }
    final oldGroups = await customSelect(
      'SELECT id, definition FROM tailnet_v21_proxy_groups',
    ).get();
    final groupColumns = await _legacyColumns('proxy_groups');
    for (final row in oldGroups) {
      final definition = Map<String, dynamic>.from(
        json.decode(row.read<String>('definition')) as Map,
      );
      for (final entry in definition.entries) {
        final column = entry.key == 'disable-udp'
            ? 'disable_u_d_p'
            : entry.key.replaceAll('-', '_');
        if (!groupColumns.contains(column) ||
            {
              'id',
              'profile_id',
              'name',
              'type',
              'proxies',
              'use',
              'order',
            }.contains(column)) {
          continue;
        }
        final value = entry.value;
        await customStatement(
          'UPDATE proxy_groups SET "$column" = ? WHERE id = ?',
          [value is bool ? (value ? 1 : 0) : value, row.read<int>('id')],
        );
      }
    }
  }

  Future<Set<String>> _legacyColumns(String table) async {
    final rows = await customSelect('PRAGMA table_info("$table")').get();
    return rows.map((row) => row.read<String>('name')).toSet();
  }
}
