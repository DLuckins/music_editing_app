import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:music_editing_app/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioEditorApp', () {
    testWidgets('renders Library and Editor tabs', (WidgetTester tester) async {
      await tester.pumpWidget(AudioEditorApp(themeMode: ThemeMode.light));
      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Editor'), findsOneWidget);
    });

    testWidgets('switching tabs shows correct content',
        (WidgetTester tester) async {
      await tester.pumpWidget(AudioEditorApp(themeMode: ThemeMode.light));

      expect(find.text('Pick Audio File'), findsNothing);

      await tester.tap(find.text('Editor'));
      await tester.pumpAndSettle();
      expect(find.text('Pick Audio File'), findsOneWidget);

      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      expect(find.text('Pick Audio File'), findsNothing);
    });
  });

  group('FormatDuration', () {
    testWidgets('formats durations correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
          MaterialApp(home: AudioEditorPage(player: AudioPlayer())));
      final state = tester.state(find.byType(AudioEditorPage)) as dynamic;
      expect(state.formatDuration(const Duration(seconds: 5)), '00:05');
      expect(state.formatDuration(const Duration(minutes: 2, seconds: 7)),
          '02:07');
      expect(
          state
              .formatDuration(const Duration(hours: 2, minutes: 3, seconds: 9)),
          '03:09');
    });
  });

  group('OverlayClip', () {
    test('stores file and position', () {
      final file = File('test/path/audio.mp3');
      final position = const Duration(seconds: 12, milliseconds: 500);
      final clip = OverlayClip(file: file, position: position);
      expect(clip.file.path, 'test/path/audio.mp3');
      expect(clip.position, position);
    });
  });

  group('TimelineEditor', () {
    testWidgets('adds removal segment via button', (WidgetTester tester) async {
      final removalSegments = <RangeValues>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimelineEditor(
              totalDuration: const Duration(seconds: 10),
              currentPosition: Duration.zero,
              removalSegments: removalSegments,
              onSeek: (_) {},
              onAddRemovalSegment: (seg) => removalSegments.add(seg),
            ),
          ),
        ),
      );

      expect(removalSegments, isEmpty);
      await tester
          .tap(find.widgetWithText(ElevatedButton, 'Add Removal Segment'));
      await tester.pump();
      expect(removalSegments.length, 1);
      expect(removalSegments.first.start, 0);
      expect(removalSegments.first.end, 10);
    });

    testWidgets('onSeek callback from tapping timeline',
        (WidgetTester tester) async {
      bool called = false;
      Duration? sought;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 300, // increased height to avoid overflow
              child: TimelineEditor(
                totalDuration: const Duration(seconds: 20),
                currentPosition: Duration.zero,
                removalSegments: [],
                onSeek: (pos) {
                  called = true;
                  sought = pos;
                },
                onAddRemovalSegment: (_) {},
              ),
            ),
          ),
        ),
      );

      // Find the Container inside TimelineEditor representing the timeline
      final timelineContainer = find.descendant(
        of: find.byType(TimelineEditor),
        matching: find.byType(Container),
      );
      expect(timelineContainer, findsOneWidget);

      // Tap at the center of the timeline Container
      await tester.tapAt(tester.getCenter(timelineContainer));
      await tester.pump();

      expect(called, isTrue);
      expect(sought, isNotNull);
      expect(sought!.inSeconds, closeTo(10, 1));
    });
  });

  group('TimelinePainter', () {
    test('shouldRepaint behavior', () {
      // Use same list instance to test no repaint
      final segments = [const RangeValues(1, 2)];
      final painter1 = TimelinePainter(
        totalDuration: const Duration(seconds: 5),
        currentPosition: const Duration(seconds: 1),
        removalSegments: segments,
      );
      final painter2 = TimelinePainter(
        totalDuration: const Duration(seconds: 5),
        currentPosition: const Duration(seconds: 2),
        removalSegments: segments,
      );
      final painter3 = TimelinePainter(
        totalDuration: const Duration(seconds: 5),
        currentPosition: const Duration(seconds: 1),
        removalSegments: [const RangeValues(1, 2)],
      );
      final painter4 = TimelinePainter(
        totalDuration: const Duration(seconds: 5),
        currentPosition: const Duration(seconds: 1),
        removalSegments: segments,
      );

      // Different position: repaint
      expect(painter1.shouldRepaint(painter2), isTrue);
      // Different segments list instance: repaint
      expect(painter1.shouldRepaint(painter3), isTrue);
      // Same list & values: no repaint
      expect(painter1.shouldRepaint(painter4), isFalse);
    });
  });
}
