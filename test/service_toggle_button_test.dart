import 'dart:io';
import 'dart:ui' as ui;

import 'package:dsh_launcher/services/web_service.dart';
import 'package:dsh_launcher/theme.dart';
import 'package:dsh_launcher/ui/widgets/service_toggle_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _captureKey = ValueKey('capture');

Widget _button(WebStatus status, {bool locked = false, VoidCallback? onTap}) {
  return MaterialApp(
    home: Center(
      child: RepaintBoundary(
        key: _captureKey,
        child: SizedBox(
          width: 140,
          height: 140,
          child: Center(
            child: ServiceToggleButton(
              status: status,
              locked: locked,
              onTap: onTap ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
}

Future<List<int>> _sampleFace(WidgetTester tester, String frame) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      // Inside the face, away from the border and power glyph.
      final offset = (70 * image.width + 34) * 4;
      if (Platform.environment['DSH_CAPTURE_FRAMES'] == '1') {
        final output = File('build/ui-qa/$frame.png');
        await output.parent.create(recursive: true);
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await output.writeAsBytes(png.buffer.asUint8List());
      }
      return List.generate(4, (i) => pixels.getUint8(offset + i));
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  setUpAll(() async {
    if (Platform.environment['DSH_CAPTURE_FRAMES'] == '1') {
      final loader = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await loader.load();
    }
  });
  testWidgets('face stays opaque and colors ease through every state', (
    tester,
  ) async {
    await tester.pumpWidget(_button(WebStatus.stopped));
    var previous = await _sampleFace(tester, 'initial');
    expect(previous[3], 255);
    for (final status in [
      WebStatus.starting,
      WebStatus.running,
      WebStatus.stopped,
      WebStatus.failed,
      WebStatus.starting,
      WebStatus.externalRunning,
      WebStatus.stopped,
    ]) {
      await tester.pumpWidget(_button(status));
      final initial = await _sampleFace(tester, '${status.name}-0');
      expect(
        initial,
        previous,
        reason: '$status must not hard cut on its first frame',
      );
      for (var step = 1; step <= 10; step++) {
        await tester.pump(const Duration(milliseconds: 24));
        final current = await _sampleFace(tester, '${status.name}-$step');
        expect(
          current[3],
          255,
          reason: '$status frame $step exposes the background',
        );
        for (var channel = 0; channel < 3; channel++) {
          expect(
            (current[channel] - previous[channel]).abs(),
            lessThan(80),
            reason: '$status frame $step has a sudden color jump',
          );
        }
        previous = current;
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('startup ring persists into running; glyph color interpolates', (
    tester,
  ) async {
    await tester.pumpWidget(_button(WebStatus.stopped));
    await tester.pumpWidget(_button(WebStatus.starting));
    Color? iconColor() =>
        tester.widget<Icon>(find.byIcon(Icons.power_settings_new)).color;
    expect(iconColor(), dshInk3);
    await tester.pump(const Duration(milliseconds: 120));
    expect(iconColor(), isNot(dshInk3));
    expect(iconColor(), isNot(Colors.white));
    await tester.pump(const Duration(milliseconds: 120));
    expect(iconColor(), Colors.white);
    final ring = find.descendant(
      of: find.byType(ServiceToggleButton),
      matching: find.byType(CustomPaint),
    );
    final element = tester.element(ring);
    await tester.pumpWidget(_button(WebStatus.running));
    expect(tester.element(ring), same(element));
    await tester.pumpWidget(_button(WebStatus.running));
    expect(
      tester.element(ring),
      same(element),
      reason: 'ordinary rebuilds preserve the ring',
    );
  });

  testWidgets('busy and locked button cannot trigger actions', (tester) async {
    var taps = 0;
    for (final status in [WebStatus.starting, WebStatus.running]) {
      await tester.pumpWidget(
        _button(
          status,
          locked: status == WebStatus.running,
          onTap: () => taps++,
        ),
      );
      await tester.tap(find.byType(ServiceToggleButton));
      await tester.pump();
      expect(taps, 0);
    }
    await tester.pumpWidget(_button(WebStatus.stopped, onTap: () => taps++));
    await tester.tap(find.byType(ServiceToggleButton));
    expect(taps, 1);
  });
}
