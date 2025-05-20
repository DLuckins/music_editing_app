import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'library.dart';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.yourapp.audio.channel',
    androidNotificationChannelName: 'Audio Playback',
    androidNotificationOngoing: true,
  );
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, mode, _) => AudioEditorApp(themeMode: mode)));
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final libraryKey = GlobalKey<ExportedFilesPageState>();
  final AudioPlayer sharedPlayer = AudioPlayer();
  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) {
          if (_tabController.index == 1) {
            sharedPlayer.stop();
          } else {
            libraryKey.currentState?.loadEditedFiles();
          }
          setState(() {});
        }
      });
  }

  @override
  void dispose() {
    _tabController.dispose();
    sharedPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 15.0),
          child: FloatingActionButton(
            mini: true,
            onPressed: () {
              themeNotifier.value = themeNotifier.value == ThemeMode.light
                  ? ThemeMode.dark
                  : ThemeMode.light;
            },
            child: Icon(Icons.brightness_6),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 23),
            child: TabBar(
              controller: _tabController, // ← add this
              labelColor: Colors.deepPurple,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Theme.of(context).primaryColor,
              tabs: [
                Tab(text: 'Library'),
                Tab(text: 'Editor'),
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tabController.index,
              children: [
                ExportedFilesPage(key: libraryKey, player: sharedPlayer),
                AudioEditorPage(player: sharedPlayer),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AudioEditorApp extends StatelessWidget {
  final ThemeMode themeMode;
  const AudioEditorApp({required this.themeMode});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music Editor',
      themeMode: themeMode,
      theme: ThemeData.light()
          .copyWith(
            colorScheme: ColorScheme(
              brightness: Brightness.light,
              primary: Colors.deepPurple,
              onPrimary: Colors.white,
              secondary: const Color.fromARGB(255, 232, 230, 230),
              onSecondary: Colors.deepPurple,
              surface: Colors.white,
              onSurface: Colors.black,
              error: Colors.red.shade700,
              onError: Colors.white,
            ),
          )
          .copyWith(
            sliderTheme: SliderThemeData(
              activeTrackColor: Colors.deepPurple,
              inactiveTrackColor: Colors.deepPurple.shade100,
              thumbColor: Color(0xFFB771E5),
            ),
            listTileTheme: ListTileThemeData(
              selectedColor: Colors.deepPurple,
              iconColor: Colors.deepPurple,
            ),
          ),
      darkTheme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.dark(
          primary: Colors.deepPurple,
          secondary: Color.fromARGB(255, 32, 31, 31),
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: Colors.deepPurple,
          inactiveTrackColor: Colors.deepPurple.shade100,
          thumbColor: Color(0xFFB771E5),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
          foregroundColor: Color.fromARGB(255, 255, 255, 255),
          backgroundColor: Color.fromARGB(255, 32, 31, 31),
        )),
        listTileTheme: ListTileThemeData(
          selectedColor: Colors.deepPurple,
          iconColor: Colors.deepPurple,
        ),
      ),
      home: HomePage(),
    );
  }
}

class OverlayClip {
  File file;
  Duration position;
  OverlayClip({required this.file, required this.position});
}

class AudioEditorPage extends StatefulWidget {
  final AudioPlayer player;
  const AudioEditorPage({required this.player, super.key});
  @override
  _AudioEditorPageState createState() => _AudioEditorPageState();
}

class TimelineEditor extends StatefulWidget {
  final Duration totalDuration;
  final Duration currentPosition;
  final List<RangeValues> removalSegments;
  final Function(Duration) onSeek;
  final Function(RangeValues) onAddRemovalSegment;

  const TimelineEditor({
    Key? key,
    required this.totalDuration,
    required this.currentPosition,
    required this.removalSegments,
    required this.onSeek,
    required this.onAddRemovalSegment,
  }) : super(key: key);

  @override
  _TimelineEditorState createState() => _TimelineEditorState();
}

class _TimelineEditorState extends State<TimelineEditor> {
  RangeValues _currentSelection = RangeValues(0, 0);

  @override
  void initState() {
    super.initState();
    _currentSelection =
        RangeValues(0, widget.totalDuration.inSeconds.toDouble());
  }

  @override
  void didUpdateWidget(TimelineEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.totalDuration != oldWidget.totalDuration) {
      _currentSelection =
          RangeValues(0, widget.totalDuration.inSeconds.toDouble());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTapDown: (details) {
            RenderBox box = context.findRenderObject() as RenderBox;
            double tapX = details.localPosition.dx;
            double ratio = tapX / box.size.width;
            Duration newPosition = Duration(
                seconds: (widget.totalDuration.inSeconds * ratio).toInt());
            widget.onSeek(newPosition);
          },
          child: Container(
            height: 50,
            width: double.infinity,
            color: Colors.grey[300],
            child: CustomPaint(
              painter: TimelinePainter(
                totalDuration: widget.totalDuration,
                currentPosition: widget.currentPosition,
                removalSegments: widget.removalSegments,
              ),
            ),
          ),
        ),
        SizedBox(height: 10),
        RangeSlider(
          values: _currentSelection,
          min: 0,
          max: widget.totalDuration.inSeconds.toDouble(),
          divisions: widget.totalDuration.inSeconds > 0
              ? widget.totalDuration.inSeconds
              : null,
          labels: RangeLabels('${_currentSelection.start.toInt()}s',
              '${_currentSelection.end.toInt()}s'),
          onChanged: (newRange) {
            setState(() {
              _currentSelection = newRange;
            });
          },
        ),
        ElevatedButton(
          onPressed: () {
            widget.onAddRemovalSegment(_currentSelection);
            setState(() {
              _currentSelection =
                  RangeValues(0, widget.totalDuration.inSeconds.toDouble());
            });
          },
          child: Text("Add Removal Segment"),
        ),
      ],
    );
  }
}

class TimelinePainter extends CustomPainter {
  final Color backgroundColor;
  final Color playedColor;
  final Color removalColor;
  final Duration totalDuration;
  final Duration currentPosition;
  final List<RangeValues> removalSegments;

  TimelinePainter({
    this.backgroundColor = const Color(0xFFEEEEEE),
    this.playedColor = Colors.blueGrey,
    this.removalColor = Colors.red,
    required this.totalDuration,
    required this.currentPosition,
    required this.removalSegments,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = backgroundColor;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);
    final progressPaint = Paint()..color = playedColor;
    double progressRatio = totalDuration.inSeconds > 0
        ? currentPosition.inSeconds / totalDuration.inSeconds
        : 0;
    double progressWidth = size.width * progressRatio;
    canvas.drawRect(
        Rect.fromLTWH(0, 0, progressWidth, size.height), progressPaint);
    final removalPaint = Paint()..color = removalColor.withValues(alpha: 0.6);
    for (var seg in removalSegments) {
      double startRatio = seg.start / totalDuration.inSeconds;
      double endRatio = seg.end / totalDuration.inSeconds;
      double segStartX = startRatio * size.width;
      double segWidth = (endRatio - startRatio) * size.width;
      canvas.drawRect(
          Rect.fromLTWH(segStartX, 0, segWidth, size.height), removalPaint);
    }
  }

  @override
  bool shouldRepaint(covariant TimelinePainter oldDelegate) {
    return oldDelegate.currentPosition != currentPosition ||
        oldDelegate.removalSegments != removalSegments;
  }
}

class _AudioEditorPageState extends State<AudioEditorPage> {
  AudioPlayer get _player => widget.player;
  File? _selectedFile;
  List<OverlayClip> _overlays = [];
  double _volume = 1.0;
  double _speed = 1.0;
  double _pitchSemitones = 0.0;
  double _effectStrength = 0.5;
  Duration _audioDuration = Duration.zero;
  Duration _currentPosition = Duration.zero;
  RangeValues _currentRemovalSelection = RangeValues(0, 0);
  List<RangeValues> _removalSegments = [];

  final List<String> _effects = [
    'None',
    'Echo',
    'LowPass',
    'Reverb',
    'Delay',
    'Distortion',
    'Boost Bass'
  ];
  String _selectedEffect = 'None';

  final List<String> _outputFormats = ['MP3', 'WAV', 'AAC'];
  String _selectedOutputFormat = 'MP3';

  @override
  void initState() {
    super.initState();
    _player.positionStream.listen((position) {
      if (mounted) setState(() => _currentPosition = position);
    });
  }

  Future<void> _pickAudioFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result != null && result.files.single.path != null) {
      _selectedFile = File(result.files.single.path!);

      await _player.setAudioSource(
        AudioSource.uri(
          Uri.file(_selectedFile!.path),
          tag: MediaItem(
            id: _selectedFile!.path,
            album: 'Edited Audio',
            title: p.basename(_selectedFile!.path),
            extras: {'notificationColor': 0xFF673AB7},
          ),
        ),
      );
      _audioDuration = _player.duration ?? Duration.zero;
      if (mounted) {
        setState(() {
          _currentRemovalSelection =
              RangeValues(0, _audioDuration.inSeconds.toDouble());
          _removalSegments = [];
          _overlays = [];
        });
      }
    }
  }

  Future<void> _pickOverlayFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result != null && result.files.single.path != null) {
      setState(() {
        _overlays.add(OverlayClip(
          file: File(result.files.single.path!),
          position: Duration.zero,
        ));
      });
    }
  }

  String _getOutputParams() {
    if (_selectedOutputFormat == 'MP3') {
      return "-c:a libmp3lame -ar 44100 -b:a 128k";
    } else if (_selectedOutputFormat == 'WAV') {
      return "-c:a pcm_s16le -ar 44100";
    } else if (_selectedOutputFormat == 'AAC') {
      return "-c:a aac -ar 44100 -b:a 128k";
    }
    return "";
  }

  String _getOutputExtension() {
    if (_selectedOutputFormat == 'MP3') return "mp3";
    if (_selectedOutputFormat == 'WAV') return "wav";
    if (_selectedOutputFormat == 'AAC') return "m4a";
    return "mp3";
  }

  String _getEffectFilter() {
    if (_selectedEffect == 'Echo') {
      double decay = 0.2 + 0.4 * _effectStrength;
      return "aecho=0.8:0.88:60:$decay";
    } else if (_selectedEffect == 'LowPass') {
      double cutoff = 3000 - (2700 * _effectStrength);
      return "lowpass=f=$cutoff";
    } else if (_selectedEffect == 'Reverb') {
      double decay = 0.3 * _effectStrength;
      return "aecho=0.8:0.9:50:$decay";
    } else if (_selectedEffect == 'Delay') {
      int delayMs = (500 * _effectStrength).toInt();
      return "adelay=${delayMs}|${delayMs}";
    } else if (_selectedEffect == 'Distortion') {
      double levelOut = 1 + _effectStrength;
      return "acrusher=level_in=0.5:level_out=$levelOut:bits=8:mode=log:aa=1";
    } else if (_selectedEffect == 'Boost Bass') {
      double gain = 10 * _effectStrength;
      return "equalizer=f=60:width_type=o:width=2:g=$gain";
    }
    return "";
  }

  String _buildFilterChain() {
    String chain = "volume=$_volume";
    if (_selectedEffect != 'None') {
      chain += ",${_getEffectFilter()}";
    }
    if (_pitchSemitones.abs() > 0.0001) {
      chain += ',${_getPitchFilter()}';
    }
    chain += ",atempo=$_speed,aresample=44100";
    return chain;
  }

  Future<void> _playPreview() async {
    final tempDir = await getTemporaryDirectory();
    final previewPath =
        p.join(tempDir.path, 'preview.${_getOutputExtension()}');
    await _runFilterAndMix(outputPath: previewPath, playWhenDone: true);
  }

  Future<String> _buildTrimmedFile() async {
    final tempDir = await getTemporaryDirectory();
    final trimmedPath = p.join(tempDir.path, 'trimmed.wav');

    final removes = _removalSegments.map((r) => [r.start, r.end]).toList()
      ..sort((a, b) => a[0].compareTo(b[0]));

    final merged = <List<double>>[];
    for (var seg in removes) {
      if (merged.isEmpty || seg[0] > merged.last[1]) {
        merged.add([seg[0], seg[1]]);
      } else {
        merged.last[1] = max(merged.last[1], seg[1]);
      }
    }

    final keeps = <List<double>>[];
    double cursor = 0.0;
    for (var rm in merged) {
      if (rm[0] > cursor) {
        keeps.add([cursor, rm[0]]);
      }
      cursor = rm[1];
    }

    final totalSec = _audioDuration.inSeconds.toDouble();
    if (cursor < totalSec) {
      keeps.add([cursor, totalSec]);
    }

    final sb = StringBuffer();
    for (int i = 0; i < keeps.length; i++) {
      final start = keeps[i][0].toStringAsFixed(3);
      final end = keeps[i][1].toStringAsFixed(3);
      sb.writeln('[0]atrim=start=$start:end=$end,'
          'asetpts=PTS-STARTPTS[s$i];');
    }

    for (int i = 0; i < keeps.length; i++) {
      sb.write('[s$i]');
    }
    sb.write('concat=n=${keeps.length}:v=0:a=1[trimmed]');

    final args = [
      '-y',
      '-i',
      _selectedFile!.path,
      '-filter_complex',
      sb.toString(),
      '-map',
      '[trimmed]',
      '-c:a',
      'pcm_s16le',
      trimmedPath,
    ];
    final session = await FFmpegKit.executeWithArguments(args);
    final rc = await session.getReturnCode();
    final logs = await session.getAllLogsAsString();
    if (rc == null || rc.getValue() != 0) {
      throw Exception('Trim failed: $logs');
    }

    return trimmedPath;
  }

  String _getPitchFilter() {
    final factor = pow(2, _pitchSemitones / 12);
    final inv = (1 / factor).toStringAsFixed(6);
    final rat = factor.toStringAsFixed(6);
    return 'asetrate=44100*$rat,aresample=44100,atempo=$inv';
  }

  Future<void> _runFilterAndMix({
    required String outputPath,
    bool playWhenDone = false,
  }) async {
    try {
      final f = File(outputPath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    String mainInput = _selectedFile!.path;
    if (_removalSegments.isNotEmpty) {
      mainInput = await _buildTrimmedFile();
    }
    final inputs = <String>[];
    inputs.add('-i "${mainInput}"');
    for (var ov in _overlays) {
      inputs.add('-i "${ov.file.path}"');
    }

    final baseFilters = _buildFilterChain();
    final fc = StringBuffer();
    for (int i = 0; i < _overlays.length; i++) {
      final ms = _overlays[i].position.inMilliseconds;
      fc.writeln('[${i + 1}]adelay=${ms}|${ms}[ovr$i];');
    }
    fc.writeln('[0]$baseFilters[main];');
    if (_overlays.isNotEmpty) {
      fc.writeln(
          '[main][ovr0]amix=inputs=2:duration=first:dropout_transition=2[mix0];');
      for (int i = 1; i < _overlays.length; i++) {
        fc.writeln('[mix${i - 1}][ovr$i]amix=inputs=2:'
            'duration=first:dropout_transition=2${i < _overlays.length - 1 ? ";" : ""}[mix$i]');
      }
    }

    final args = <String>[
      '-y',
      '-i',
      mainInput,
      for (var ov in _overlays) ...['-i', ov.file.path],
      '-filter_complex',
      _buildFilterComplex(),
      '-map',
      '[out]',
      ..._getOutputParams().split(' '),
      outputPath,
    ];

    print('FFmpeg args: $args');

    final session = await FFmpegKit.executeWithArguments(args);
    final rc = await session.getReturnCode();
    if (rc == null || rc.getValue() != 0) {
      final logs = await session.getAllLogsAsString();
      final trace = await session.getFailStackTrace();
      throw Exception('FFmpeg failed (code=${rc?.getValue()})\n$logs\n$trace');
    }

    if (playWhenDone) {
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.file(outputPath),
          tag: MediaItem(
            id: _selectedFile!.path,
            album: 'Edited Audio',
            title: p.basename(_selectedFile!.path),
            extras: {'notificationColor': 0xFF673AB7},
          ),
        ),
      );
      await _player.setVolume(_volume);
      await _player.setSpeed(_speed);
      _player.play();
    }
  }

  static Future<Directory> getExternalDocumentPath() async {
    // To check whether permission is given for this app or not.
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      // If not we will ask for permission first
      await Permission.storage.request();
    }
    Directory _directory = Directory("");
    if (Platform.isAndroid) {
      // Redirects it to download folder in android
      _directory = Directory("/storage/emulated/0/Music/EditedAudio");
    } else {
      _directory = await getApplicationDocumentsDirectory();
    }

    final exPath = _directory.path;
    final dir = Directory(p.join(exPath, 'EditedAudio'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Exports the final edited audio with removals, overlays, and concatenation.
  Future<void> _exportEditedAudio() async {
    if (_selectedFile == null) return;
    final name = await _askForFileName();
    if (name == null) return; // user cancelled or empty

    final exportDir = await getExternalDocumentPath();
    final outputPath = p.join(exportDir.path, '$name.${_getOutputExtension()}');

    try {
      await _runFilterAndMix(outputPath: outputPath, playWhenDone: false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Exported to $outputPath')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<String?> _askForFileName() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Save As'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: 'Enter file name'),
        ),
        actions: [
          TextButton(
            child: Text('Cancel'),
            onPressed: () => Navigator.of(dialogCtx).pop(null),
          ),
          ElevatedButton(
            child: Text('Save'),
            onPressed: () =>
                Navigator.of(dialogCtx).pop(controller.text.trim()),
          ),
        ],
      ),
    );
    // If user pressed Save with empty text, treat as cancelled
    if (result == null || result.isEmpty) return null;
    return result;
  }

  @override
  void dispose() {
    super.dispose();
  }

  String _buildFilterComplex() {
    final mainFilt = '${_buildFilterChain()}[main]';

    final delayLabels = <String>[];
    for (var i = 0; i < _overlays.length; i++) {
      final ms = _overlays[i].position.inMilliseconds;
      delayLabels.add('[${i + 1}]adelay=${ms}|${ms}[ovr$i]');
    }

    final inputs =
        ['[main]', for (var i = 0; i < _overlays.length; i++) '[ovr$i]'].join();
    final totalInputs = _overlays.length + 1;
    final amix =
        '$inputs amix=inputs=$totalInputs:duration=first:dropout_transition=2[out]';

    return ([mainFilt, ...delayLabels, amix]).join(';');
  }

  String formatDuration(Duration d) =>
      "${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:" +
      "${d.inSeconds.remainder(60).toString().padLeft(2, '0')}";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton(
                  onPressed: _pickAudioFile, child: Text('Pick Audio File')),
              if (_selectedFile != null) ...[
                SizedBox(height: 20),
                Row(
                  children: [
                    IconButton(
                        icon: Icon(Icons.play_arrow),
                        onPressed: () async {
                          await _player.setAudioSource(
                            AudioSource.uri(
                              Uri.file(_selectedFile!.path),
                              tag: MediaItem(
                                id: _selectedFile!.path,
                                album: 'Edited Audio',
                                title: p.basename(_selectedFile!.path),
                                extras: {'notificationColor': 0xFF673AB7},
                              ),
                            ),
                          );
                          _player
                            ..setVolume(_volume)
                            ..setSpeed(_speed)
                            ..play();
                        }),
                    IconButton(
                        icon: Icon(Icons.pause),
                        onPressed: () => _player.pause()),
                  ],
                ),
                SizedBox(height: 10),
                Text(
                    'Playback: ${formatDuration(_currentPosition)} / ${formatDuration(_audioDuration)}'),
                SizedBox(height: 10),
                TimelineEditor(
                  totalDuration: _audioDuration,
                  currentPosition: _currentPosition,
                  removalSegments: _removalSegments,
                  onSeek: (pos) async => _player.seek(pos),
                  onAddRemovalSegment: (seg) =>
                      setState(() => _removalSegments.add(seg)),
                ),
                SizedBox(height: 20),
                Text('Overlays', style: TextStyle(fontWeight: FontWeight.bold)),
                ElevatedButton.icon(
                  icon: Icon(Icons.add),
                  label: Text('Add Overlay'),
                  onPressed: _pickOverlayFile,
                ),
                for (int i = 0; i < _overlays.length; i++)
                  Card(
                    margin: EdgeInsets.symmetric(vertical: 8),
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(children: [
                            Expanded(
                                child:
                                    Text(p.basename(_overlays[i].file.path))),
                            IconButton(
                              icon: Icon(Icons.delete),
                              onPressed: () =>
                                  setState(() => _overlays.removeAt(i)),
                            )
                          ]),
                          Text(
                              'Insert at: ${formatDuration(_overlays[i].position)}'),
                          Slider(
                            min: 0,
                            max: _audioDuration.inMilliseconds.toDouble(),
                            value: _overlays[i]
                                .position
                                .inMilliseconds
                                .toDouble()
                                .clamp(0,
                                    _audioDuration.inMilliseconds.toDouble()),
                            onChanged: (v) => setState(() => _overlays[i]
                                .position = Duration(milliseconds: v.toInt())),
                          ),
                        ],
                      ),
                    ),
                  ),
                SizedBox(height: 10),
                Text('Volume'),
                Slider(
                    value: _volume,
                    min: 0,
                    max: 1,
                    onChanged: (v) {
                      setState(() => _volume = v);
                      _player.setVolume(v);
                    }),
                Text('Speed (x${_speed.toStringAsFixed(2)})'),
                Slider(
                    value: _speed,
                    min: 0.5,
                    max: 2.0,
                    onChanged: (v) => setState(() => _speed = v)),
                SizedBox(height: 10),
                Text(
                    'Pitch Shift (${_pitchSemitones.toStringAsFixed(1)} semitones)'),
                Slider(
                  min: -12,
                  max: 12,
                  divisions: 24,
                  value: _pitchSemitones,
                  label: '${_pitchSemitones.toStringAsFixed(1)}',
                  onChanged: (v) => setState(() => _pitchSemitones = v),
                ),
                Text('Effect'),
                DropdownButton<String>(
                  value: _selectedEffect,
                  isExpanded: true,
                  onChanged: (v) => setState(() => _selectedEffect = v!),
                  items: _effects
                      .map((e) => DropdownMenuItem(child: Text(e), value: e))
                      .toList(),
                ),
                Text(
                    'Effect Strength ${(_effectStrength * 10).toStringAsFixed(2)}'),
                Slider(
                    value: _effectStrength,
                    min: 0,
                    max: 1,
                    onChanged: (v) => setState(() => _effectStrength = v)),
                SizedBox(height: 10),
                Text('Output Format'),
                DropdownButton<String>(
                  value: _selectedOutputFormat,
                  isExpanded: true,
                  onChanged: (v) => setState(() => _selectedOutputFormat = v!),
                  items: _outputFormats
                      .map((f) => DropdownMenuItem(child: Text(f), value: f))
                      .toList(),
                ),
                ElevatedButton(
                    onPressed: _playPreview,
                    child: Text('Preview with Effect & Overlays')),
                ElevatedButton(
                    onPressed: _exportEditedAudio,
                    child: Text('Export Edited Audio')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
