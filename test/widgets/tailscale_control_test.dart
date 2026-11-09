import 'dart:async';

import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/networking/networking.dart';
import 'package:fl_clash/widgets/inherited.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/test_app.dart';

class _Core extends Mock implements CoreHandlerInterface {}

void main() {
  setUpAll(() {
    registerFallbackValue(const GetOverlayNetworkStatusParams(targets: []));
  });

  for (final initialRunning in [true, false]) {
   for (final fail in [false, true]) {
    testWidgets('Tailscale switch from $initialRunning (failure: $fail)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(432, 936);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final core = _Core();
      var running = initialRunning;
      var unavailable = false;
      final pending = Completer<OverlayNetworkStatus>();
      OverlayNetworkStatus status() => OverlayNetworkStatus(
        name: 'TAILNET',
        kind: OverlayNetworkKind.tailscale,
        state: running
            ? OverlayNetworkState.connected
            : OverlayNetworkState.stopped,
        rawState: running ? 'Running' : 'Stopped',
        networkName: 'private-tailnet',
        authUrl: '',
        error: '',
      );
      when(() => core.getOverlayNetworkStatus(any())).thenAnswer(
        (_) async {
          if (unavailable) throw StateError('Core unavailable');
          return [status()];
        },
      );
      when(() => core.setTailscaleRunning('TAILNET', !initialRunning)).thenAnswer(
        (_) => pending.future,
      );
      final container = ProviderContainer(
        overrides: [
          coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        ],
      );
      addTearDown(container.dispose);
      globalState.container = container;
      container.read(viewSizeProvider.notifier).update(
        (_) => const Size(432, 936),
      );
      container.read(groupsProvider.notifier).update(
        (_) => const [
          Group(
            name: 'GLOBAL',
            type: GroupType.Selector,
            all: [Proxy(name: 'TAILNET', type: 'Tailscale')],
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TestApp(
            child: PageActivityScope(
              isActive: true,
              child: NetworkingView(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('tailscale-running-TAILNET'));
      expect(tester.widget<Switch>(toggle).value, initialRunning);
      running = !initialRunning;
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(toggle).value, !initialRunning);
      unavailable = true;
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(toggle).onChanged, isNull);
      expect(tester.widget<Switch>(toggle).value, isFalse);
      unavailable = false;
      running = initialRunning;
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(toggle).value, initialRunning);
      await tester.tap(toggle);
      await tester.pump();
      expect(tester.widget<Switch>(toggle).onChanged, isNull);
      expect(tester.widget<Switch>(toggle).value, initialRunning);
      if (fail) {
        pending.completeError(StateError('connection change failed'));
      } else {
        running = !initialRunning;
        pending.complete(status());
      }
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(toggle).value, fail ? initialRunning : !initialRunning);
      expect(tester.widget<Switch>(toggle).onChanged, isNotNull);
      verify(() => core.setTailscaleRunning('TAILNET', !initialRunning)).called(1);
      if (fail) {
        expect(find.textContaining('connection change failed'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
   }
  }
}
