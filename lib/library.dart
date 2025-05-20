import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

class ExportedFilesPage extends StatefulWidget {
  final AudioPlayer player;
  const ExportedFilesPage({required this.player, super.key});
  @override
  ExportedFilesPageState createState() => ExportedFilesPageState();
}

class ExportedFilesPageState extends State<ExportedFilesPage> {
  List<File> _editedFiles = [];
  AudioPlayer get _player => widget.player;
  String? _currentPlayingFilePath;
  bool _isPlaying = false;

  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    loadEditedFiles();
    _player.durationStream.listen((d) {
      if (d != null && mounted) setState(() => _duration = d);
    });
    _player.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _player.playingStream.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });
    _player.currentIndexStream.listen((newIndex) {
      if (mounted && newIndex != null) {
        setState(() {
          _currentPlayingFilePath = _editedFiles[newIndex].path;
        });
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
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

  Future<void> loadEditedFiles() async {
    final exportDir = await getExternalDocumentPath();

    final files = exportDir.listSync().whereType<File>().toList();
    if (!mounted) return;
    setState(() => _editedFiles = files);

    final playlist = files.map((file) {
      return AudioSource.uri(
        Uri.file(file.path),
        tag: MediaItem(
          id: file.path,
          album: 'Edited Audio',
          title: p.basename(file.path),
        ),
      );
    }).toList();

    if (playlist.isNotEmpty) {
      await _player.setAudioSource(
        ConcatenatingAudioSource(children: playlist),
        initialIndex: 0,
        initialPosition: Duration.zero,
      );
      _player.setLoopMode(LoopMode.all);
    }
  }

  Future<void> _deleteSong(File file) async {
    if (_currentPlayingFilePath == file.path) {
      await _player.stop();
      if (mounted) setState(() => _resetPlayerState());
    }
    await file.delete();
    await loadEditedFiles();
  }

  void _resetPlayerState() {
    _currentPlayingFilePath = null;
    _isPlaying = false;
    _duration = Duration.zero;
    _position = Duration.zero;
  }

  Future<void> _togglePlayPause(File file) async {
    final index = _editedFiles.indexWhere((f) => f.path == file.path);
    if (index < 0) return;

    if (_currentPlayingFilePath != file.path) {
      setState(() => _currentPlayingFilePath = file.path);
      await _player.seek(Duration.zero, index: index);
      _player.play();
    } else {
      if (_player.playing) {
        _player.pause();
      } else {
        _player.play();
      }
    }
  }

  Future<void> _playPrevious() async {
    if (_currentPlayingFilePath == null || _editedFiles.isEmpty) return;
    int currentIndex =
        _editedFiles.indexWhere((f) => f.path == _currentPlayingFilePath);
    int prevIndex = (currentIndex - 1) % _editedFiles.length;
    final prevFile = _editedFiles[prevIndex];
    await _togglePlayPause(prevFile);
  }

  Future<void> _playNext() async {
    if (_currentPlayingFilePath == null || _editedFiles.isEmpty) return;
    int currentIndex =
        _editedFiles.indexWhere((f) => f.path == _currentPlayingFilePath);
    int nextIndex = (currentIndex + 1) % _editedFiles.length;
    final nextFile = _editedFiles[nextIndex];
    await _togglePlayPause(nextFile);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _editedFiles.length,
              itemBuilder: (context, index) {
                final file = _editedFiles[index];
                final fileName = p.basename(file.path);
                final isCurrent = _currentPlayingFilePath == file.path;
                return ListTile(
                  title: Text(fileName),
                  leading: isCurrent
                      ? Icon(Icons.graphic_eq, color: Colors.green)
                      : Icon(Icons.music_note),
                  onTap: () async => await _togglePlayPause(file),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(isCurrent
                            ? (_isPlaying ? Icons.pause : Icons.play_arrow)
                            : Icons.play_arrow),
                        onPressed: () async => await _togglePlayPause(file),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete),
                        onPressed: () async => await _deleteSong(file),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (_currentPlayingFilePath != null) _buildBottomPlayer(),
        ],
      ),
    );
  }

  Widget _buildBottomPlayer() {
    final fileName = p.basename(_currentPlayingFilePath!);
    return Container(
      color: Theme.of(context).colorScheme.secondary,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  fileName,
                  style: TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: Icon(Icons.skip_previous),
                onPressed: _playPrevious,
              ),
              IconButton(
                icon: Icon(_isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled),
                iconSize: 36,
                onPressed: () async {
                  if (_currentPlayingFilePath != null) {
                    await _togglePlayPause(File(_currentPlayingFilePath!));
                  }
                },
              ),
              IconButton(
                icon: Icon(Icons.skip_next),
                onPressed: _playNext,
              ),
            ],
          ),
          Row(
            children: [
              Text(_formatDuration(_position)),
              Expanded(
                child: Slider(
                  min: 0,
                  max: _duration.inMilliseconds.toDouble(),
                  value: _position.inMilliseconds
                      .clamp(0, _duration.inMilliseconds)
                      .toDouble(),
                  onChanged: (value) async {
                    final newPos = Duration(milliseconds: value.toInt());
                    await _player.seek(newPos);
                  },
                ),
              ),
              Text(_formatDuration(_duration)),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }
}
