import 'dart:io';

Future<int> verifyTailnetBuild(String rootDir) async {
  final output = Directory('$rootDir/dist')..createSync(recursive: true);
  final report = StringBuffer();
  Future<int> run(String executable, List<String> args, {String? cwd}) async {
    final command = '$executable ${args.join(' ')}';
    stdout.writeln('> $command');
    final process = await Process.start(
      executable,
      args,
      workingDirectory: cwd ?? rootDir,
      environment: {'CGO_ENABLED': '0'},
      mode: ProcessStartMode.inheritStdio,
    );
    final result = await process.exitCode;
    report.writeln('$result: $command');
    File(
      '${output.path}/verification.txt',
    ).writeAsStringSync(report.toString());
    return result;
  }

  final dartFiles = [
    'lib/core/controller.dart',
    'lib/core/interface.dart',
    'lib/core/method.dart',
    'lib/database/database.dart',
    'lib/database/legacy_tailnet.dart',
    'lib/views/navigation.dart',
    'lib/views/networking/networking.dart',
    'test/widgets/tailscale_control_test.dart',
    'test/widgets/easytier_networking_test.dart',
    'test/providers/state_derived_test.dart',
    'test/database/tailnet_legacy_test.dart',
    'test/database/migration_v1_to_v2_test.dart',
    'setup.dart',
    'tool/verify_tailnet.dart',
  ];
  var result = await run('dart', ['format', ...dartFiles]);
  if (result != 0) return result;
  final diff = await Process.run('git', ['diff', '--', ...dartFiles]);
  File(
    '${output.path}/formatted-source.patch',
  ).writeAsStringSync(diff.stdout.toString());
  result = await run('flutter', ['analyze', '--no-fatal-infos']);
  if (result != 0) return result;
  for (final target in ['.', 'github.com/metacubex/mihomo/adapter/outbound']) {
    result = await run('go', [
      'test',
      '-tags',
      'with_gvisor',
      target,
      '-run',
      target == '.' ? 'Overlay|Tailscale' : 'TestTailscale',
      '-count=1',
    ], cwd: '$rootDir/core');
    if (result != 0) return result;
  }

  final pubspec = File('$rootDir/pubspec.yaml');
  final original = pubspec.readAsStringSync();
  try {
    pubspec.writeAsStringSync(
      original.replaceAll(
        RegExp(r'build_assets:\s*true'),
        'build_assets: false',
      ),
    );
    return await run('flutter', [
      'test',
      'test/widgets/tailscale_control_test.dart',
      'test/widgets/easytier_networking_test.dart',
      'test/providers/state_derived_test.dart',
      'test/core/interface_message_test.dart',
      'test/core/protocol_contract_test.dart',
      'test/database/tailnet_legacy_test.dart',
      'test/database/migration_v1_to_v2_test.dart',
    ]);
  } finally {
    pubspec.writeAsStringSync(original);
  }
}
