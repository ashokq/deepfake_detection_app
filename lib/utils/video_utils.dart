import 'dart:io';
import 'dart:typed_data';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// Loads a VideoPlayerController (file path or network url) just to read duration.
Future<Duration> getVideoDuration(String path) async {
  final controller = VideoPlayerController.file(File(path));
  await controller.initialize();
  final d = controller.value.duration;
  await controller.dispose();
  return d;
}

/// Extracts up to [maxFrames] evenly spaced thumbnails from the video.
/// Returns raw PNG bytes for each frame.
Future<List<Uint8List>> extractSampledFrames(
    String videoPath, {
      int maxFrames = 24,
    }) async {
  final duration = await getVideoDuration(videoPath);
  if (duration.inMilliseconds <= 0) return [];

  final frames = <Uint8List>[];

  // Sample evenly across the full duration (skip very first/last few ms)
  final totalMs = duration.inMilliseconds;
  final step = (totalMs / (maxFrames + 1)).floor();

  for (int i = 1; i <= maxFrames; i++) {
    final timeMs = i * step;
    final bytes = await VideoThumbnail.thumbnailData(
      video: videoPath,
      imageFormat: ImageFormat.PNG,
      timeMs: timeMs,
      quality: 90,
    );
    if (bytes != null) frames.add(bytes);
  }
  return frames;
}
