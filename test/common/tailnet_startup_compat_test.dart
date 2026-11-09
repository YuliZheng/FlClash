import 'dart:convert';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/preferences.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> _legacyConfig() => {
  'currentProfileId': 42,
  'overrideDns': false,
  'excludeSSIDs': ['home'],
  'alwaysOn': true,
  'hotKeyActions': [
    for (final action in [
      'start', 'view', 'mode', 'proxy', 'tun', 'ruleMode', 'globalMode',
      'directMode', 'delayTest', 'updateProfiles', 'copyEnv', 'exit',
    ])
      {'action': action, 'key': null, 'modifiers': <String>[]},
  ],
  'themeProps': {'themeMode': 'dark'},
  'appSettingProps': {
    'locale': 'zh_CN',
    'autoRun': true,
    'openLogs': true,
    'dashboardWidgets': ['networkSpeed', 'serviceStatus', 'currentOutbound'],
  },
  'proxiesStyleProps': {'cardType': 'compact', 'iconStyle': 'plain'},
  'networkProps': {'routeMode': 'config', 'appendSystemDns': false},
  'vpnProps': {'dnsHijacking': false},
  'patchClashConfig': {'mode': 'rule', 'mixed-port': 7890},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  late SharedPreferences store;

  setUp(() async {
    store = await SharedPreferences.getInstance();
    await store.clear();
  });

  test('installed v0.9.2 preferences load without resetting network or profile settings', () async {
    final raw = jsonEncode(_legacyConfig());
    await store.setString(configKey, raw);
    final config = (await preferences.getConfig())!;

    expect(config.hotKeyActions.map((action) => action.action), HotAction.values);
    expect(config.currentProfileId, 42);
    expect(config.overrideDns, isFalse);
    expect(config.excludeSSIDs, ['home']);
    expect(config.alwaysOn, isTrue);
    expect(config.appSettingProps.locale, 'zh_CN');
    expect(config.appSettingProps.autoRun, isTrue);
    expect(config.appSettingProps.openLogs, isTrue);
    expect(config.networkProps.routeMode, RouteMode.config);
    expect(config.networkProps.appendSystemDns, isFalse);
    expect(config.vpnProps.dnsHijacking, isFalse);
    expect(config.patchClashConfig.mixedPort, 7890);
    final backup = store.getString(Preferences.tailnetUpgradeBackupKey);
    expect(jsonDecode(backup!), jsonDecode(raw));
    expect(store.getString(configKey), raw);

    await preferences.saveConfig(config);
    expect(await preferences.getConfig(), config);
    expect(store.getString(Preferences.tailnetUpgradeBackupKey), backup);
  });

  test('unsupported shortcut entries cannot abort startup or become a different action', () {
    final raw = _legacyConfig();
    raw['hotKeyActions'] = [
      {'action': 'delayTest'},
      {'action': 'updateProfiles'},
      {'action': 'futureAction'},
      null,
      10,
      {'action': 'start', 'key': 65, 'modifiers': ['control', 'futureModifier']},
    ];
    final before = jsonEncode(raw);
    final config = Config.fromJson(raw);

    expect(config.hotKeyActions, [
      const HotKeyAction(action: HotAction.start, key: 65, modifiers: {KeyboardModifier.control}),
    ]);
    expect(jsonEncode(raw), before);
    expect(Config.fromJson(jsonDecode(jsonEncode(config))), config);
  });

  test('all supported shortcut combinations survive a normal save and load', () {
    final config = Config(
      themeProps: defaultThemeProps,
      hotKeyActions: [
        for (final action in HotAction.values)
          HotKeyAction(action: action, key: 65, modifiers: KeyboardModifier.values.toSet()),
      ],
    );
    expect(Config.fromJson(jsonDecode(jsonEncode(config))), config);
  });
}
