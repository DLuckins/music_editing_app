import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:music_editing_app/library.dart';

const _permissionChannel =
    MethodChannel('flutter.baseflow.com/permissions/methods');
const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docsDir;

  setUp(() {
    docsDir = Directory.systemTemp.createTempSync('app_docs');

    _permissionChannel.setMockMethodCallHandler((call) async {
      switch (call.method) {
        case 'checkPermissionStatus':
          return PermissionStatus.granted.index;
        case 'requestPermissions':
          return {'storage': PermissionStatus.granted.index};
      }
      return null;
    });

    // 3) Stub out path_provider calls
    _pathProviderChannel.setMockMethodCallHandler((call) async {
      switch (call.method) {
        case 'getApplicationDocumentsDirectory':
        case 'getTemporaryDirectory':
          return docsDir.path;
      }
      return null;
    });
  });

  tearDown(() {
    _permissionChannel.setMockMethodCallHandler(null);
    _pathProviderChannel.setMockMethodCallHandler(null);
    if (docsDir.existsSync()) docsDir.deleteSync(recursive: true);
  });

  group('ExportedFilesPageState.getExternalDocumentPath', () {
    test('creates and returns a directory ending with EditedAudio', () async {
      final dir = await ExportedFilesPageState.getExternalDocumentPath();

      expect(dir.existsSync(), isTrue);

      expect(
        p.basename(dir.path),
        equals('EditedAudio'),
      );

      expect(
        dir.path,
        startsWith(p.normalize(docsDir.path + Platform.pathSeparator)),
      );
    });
  });

  testWidgets('ExportedFilesPage builds and shows a ListView',
      (WidgetTester tester) async {
    final player = AudioPlayer();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportedFilesPage(player: player),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ListView), findsOneWidget);
  });
}
