import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models/inference_result.dart';
import 'services/hf_service.dart';
import 'utils/video_utils.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DeepfakeApp());
}

class DeepfakeApp extends StatelessWidget {
  const DeepfakeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Deepfake Detector',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _picker = ImagePicker();
  final _hf = HFService(); // uses default model id

  File? _pickedFile;
  bool _isVideo = false;
  String _status = 'Pick an image or a video to start';
  InferenceResult? _finalResult;
  List<InferenceResult> _frameResults = [];
  bool _busy = false;

  Future<void> _pickImage() async {
    setState(() {
      _busy = true;
      _finalResult = null;
      _frameResults.clear();
      _status = 'Picking image...';
    });

    try {
      final xfile = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 100);
      if (xfile == null) {
        setState(() {
          _busy = false;
          _status = 'Image picking cancelled';
        });
        return;
      }
      _pickedFile = File(xfile.path);
      _isVideo = false;

      final bytes = await _pickedFile!.readAsBytes();
      setState(() => _status = 'Sending to model...');

      final res = await _hf.classifyImageBytes(bytes);
      setState(() {
        _finalResult = res;
        _status = 'Done';
      });
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
      });
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _pickVideo() async {
    setState(() {
      _busy = true;
      _finalResult = null;
      _frameResults.clear();
      _status = 'Picking video...';
    });

    try {
      final xfile = await _picker.pickVideo(source: ImageSource.gallery);
      if (xfile == null) {
        setState(() {
          _busy = false;
          _status = 'Video picking cancelled';
        });
        return;
      }

      _pickedFile = File(xfile.path);
      _isVideo = true;

      setState(() => _status = 'Extracting frames...');
      final frames = await extractSampledFrames(_pickedFile!.path, maxFrames: 24);

      if (frames.isEmpty) {
        setState(() {
          _status = 'Could not extract frames from this video.';
          _busy = false;
        });
        return;
      }

      // (Optional) cache a thumbnail to show
      await _savePreviewFrame(frames.first);

      // Send frames sequentially (simple + safe for free plans)
      _frameResults.clear();
      for (int i = 0; i < frames.length; i++) {
        setState(() => _status = 'Analyzing frame ${i + 1}/${frames.length}...');
        final r = await _hf.classifyImageBytes(frames[i]);
        _frameResults.add(r);
      }

      final agg = _hf.aggregateFrames(_frameResults);
      setState(() {
        _finalResult = agg;
        _status = 'Done';
      });
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _savePreviewFrame(Uint8List pngBytes) async {
    try {
      final dir = await getTemporaryDirectory();
      final fp = p.join(dir.path, 'preview.png');
      final f = File(fp);
      await f.writeAsBytes(pngBytes, flush: true);
      // no-op: we keep it only if you want to display later
    } catch (_) {}
  }

  Color _badgeColor(InferenceResult? r) {
    if (r == null) return Colors.grey;
    return r.isFake ? Colors.red : Colors.green;
  }

  String _explain(InferenceResult? r) {
    if (r == null) return '—';
    final pct = (r.score * 100).toStringAsFixed(1);
    return r.isFake
        ? 'Prediction: FAKE ($pct%)'
        : 'Prediction: REAL ($pct%)';
  }

  Widget _buildResultCard() {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Result', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _badgeColor(_finalResult).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    _finalResult == null ? '—' : _finalResult!.label.toUpperCase(),
                    style: TextStyle(
                      color: _badgeColor(_finalResult),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(_explain(_finalResult)),
              ],
            ),
            const SizedBox(height: 12),
            if (_isVideo && _frameResults.isNotEmpty)
              Text('Frames analyzed: ${_frameResults.length}'),
            if (_isVideo && _frameResults.isNotEmpty)
              const SizedBox(height: 6),
            if (_isVideo && _frameResults.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _frameResults.take(6).map((r) {
                  final c = r.isFake ? Colors.red : Colors.green;
                  return Chip(
                    label: Text('${r.label} ${(r.score * 100).toStringAsFixed(0)}%'),
                    backgroundColor: c.withOpacity(0.12),
                    labelStyle: TextStyle(color: c),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canRun = HFService.HF_API_TOKEN.startsWith('hf_') && HFService.HF_API_TOKEN.length > 10;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Deepfake Detector'),
        actions: [
          IconButton(
            tooltip: 'Model',
            onPressed: () {
              showAboutDialog(
                context: context,
                applicationName: 'Deepfake Detector',
                applicationVersion: '1.0.0',
                children: const [
                  Text('Uses Hugging Face model: prithivMLmods/deepfake-detector-model-v1'),
                  SizedBox(height: 8),
                  Text('For video, it samples frames and aggregates predictions.'),
                ],
              );
            },
            icon: const Icon(Icons.info_outline),
          )
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _status,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (_busy) const SizedBox(width: 12),
                            if (_busy)
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildResultCard(),
                  ],
                ),
              ),
              if (!canRun)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '⚠️ Add your Hugging Face token in lib/services/hf_service.dart (HF_API_TOKEN).',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: canRun && !_busy ? _pickImage : null,
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Pick Image'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: canRun && !_busy ? _pickVideo : null,
                      icon: const Icon(Icons.video_library_outlined),
                      label: const Text('Pick Video'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),

    );
  }
}
