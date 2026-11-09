import 'dart:io';

import 'package:drift/native.dart';
import 'package:fl_clash/database/database.dart' as fl;
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database raw;
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('tailnet_v21_');
    raw = sqlite3.openInMemory();
    final seed = fl.Database(NativeDatabase.opened(raw, closeUnderlyingOnClose: false));
    await seed.profilesDao.putAll([
      const Profile(
        id: 7,
        label: 'Existing tailnet YAML',
        url: '',
        autoUpdateDuration: const Duration(hours: 12),
        selectedMap: const {'Home': 'Tailscale'},
      ).toCompanion(),
    ]);
    await seed.close();
    raw.execute('DROP TABLE profile_rule_mapping');
    raw.execute('ALTER TABLE profiles RENAME COLUMN overwrite_type TO extend_type');
    raw.execute("ALTER TABLE profiles ADD COLUMN type TEXT NOT NULL DEFAULT 'file'");
    raw.execute('ALTER TABLE profiles ADD COLUMN overrides TEXT');
    raw.execute('ALTER TABLE rules ADD COLUMN profile_id INTEGER');
    raw.execute('ALTER TABLE rules ADD COLUMN "order" TEXT');
    raw.execute("ALTER TABLE proxy_groups ADD COLUMN definition TEXT NOT NULL DEFAULT '{}'");
    raw.execute('''
      INSERT INTO rules(id, rule_action, content, rule_target, no_resolve, src, profile_id, "order")
      VALUES (1, 'DOMAIN', 'home.example', 'Tailscale', 0, 0, NULL, 'a'),
             (2, 'DOMAIN', 'work.example', 'Tailscale', 0, 0, 7, 'b')
    ''');
    raw.execute('CREATE TABLE disabled_rules(profile_id INTEGER, rule_id INTEGER)');
    raw.execute('INSERT INTO disabled_rules VALUES(7, 1)');
    raw.execute('''
      INSERT INTO proxy_groups(id, profile_id, name, type, definition)
      VALUES(9, 7, 'Home', 'select', '{"hidden":true,"disable-udp":true}')
    ''');
    raw.execute('PRAGMA user_version = 21');
  });

  tearDown(() async {
    raw.close();
    await directory.delete(recursive: true);
  });

  Future<fl.Database> migrate() async {
    final database = fl.Database.withLegacyBackup(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
      '${directory.path}/before.sqlite',
    );
    addTearDown(database.close);
    await database.customSelect('SELECT 1').get();
    return database;
  }

  test('v21 YAML profiles, rule ownership and group options survive with a full backup', () async {
    final database = await migrate();
    final profile = (await database.profilesDao.query().get()).single;
    expect(profile.id, 7);
    expect(profile.label, 'Existing tailnet YAML');
    expect(profile.selectedMap, {'Home': 'Tailscale'});
    expect(profile.overwriteType, OverwriteType.standard);
    final rules = await database.rulesDao.queryAddedRules(7).get();
    expect(rules.map((rule) => rule.id), [2]);
    final group = (await database.proxyGroupsDao.query(7).get()).single;
    expect(group.hidden, isTrue);
    expect(group.disableUDP, isTrue);
    await database.profilesDao.putAll([
      const Profile(id: 8, label: 'New', autoUpdateDuration: Duration(hours: 12)).toCompanion(),
    ]);
    expect(await database.profilesDao.query().get(), hasLength(2));
    expect(raw.select('PRAGMA user_version').single['user_version'], database.schemaVersion);
    expect(raw.select('SELECT * FROM tailnet_v21_profiles'), hasLength(1));
    final backup = sqlite3.open('${directory.path}/before.sqlite', mode: OpenMode.readOnly);
    try {
      expect(backup.select('PRAGMA user_version').single['user_version'], 21);
      expect(backup.select('SELECT * FROM profiles'), hasLength(1));
    } finally {
      backup.close();
    }
    await database.close();
    final reopened = fl.Database(NativeDatabase.opened(raw, closeUnderlyingOnClose: false));
    addTearDown(reopened.close);
    expect(await reopened.profilesDao.query().get(), hasLength(2));
  });

  test('unsupported custom profiles leave v21 unchanged and backed up', () async {
    raw.execute("UPDATE profiles SET type = 'custom'");
    await expectLater(migrate(), throwsA(isA<StateError>()));
    expect(raw.select('PRAGMA user_version').single['user_version'], 21);
    expect(raw.select('SELECT type FROM profiles').single['type'], 'custom');
    expect(raw.select("SELECT name FROM sqlite_master WHERE name LIKE 'tailnet_v21_%'"), isEmpty);
    expect(File('${directory.path}/before.sqlite').existsSync(), isTrue);
  });
}
