import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/inference_result.dart';

class HFService {
  // 👉 Paste your token here (keep private in production!)
  static const String HF_API_TOKEN = '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';

  // Default image deepfake model (binary: fake vs real)
  static const String defaultModelId = 'dima806/deepfake_vs_real_image_detection';

  final String modelId;

  HFService({String? modelId}) : modelId = modelId ?? defaultModelId;

  Future<InferenceResult> classifyImageBytes(Uint8List imageBytes) async {
    final uri = Uri.parse('https://api-inference.huggingface.co/models/$modelId');

    final res = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $HF_API_TOKEN',
        'Content-Type': 'application/octet-stream',
        'Accept': 'application/json', // 👈 prevents HTML response
      },
      body: imageBytes,
    );

    // ✅ Success case
    if (res.statusCode == 200) {
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is List && decoded.isNotEmpty) {
          // sort by score, pick best
          decoded.sort((a, b) => (b['score'] as num).compareTo(a['score'] as num));
          final top = decoded.first;
          return InferenceResult(
            label: (top['label'] as String).toLowerCase(),
            score: (top['score'] as num).toDouble(),
          );
        }
        throw Exception('Empty response from Hugging Face');
      } catch (e) {
        throw Exception('Invalid JSON from Hugging Face: ${res.body}');
      }
    }

    // ✅ Handle cold start (503) → retry once
    if (res.statusCode == 503) {
      await Future.delayed(const Duration(seconds: 3));
      return classifyImageBytes(imageBytes);
    }

    // ❌ If HF returned HTML or other error
    if (res.headers['content-type']?.contains('text/html') == true) {
      throw Exception('Unexpected HTML response (check model/task): ${res.body.substring(0, 100)}...');
    }

    throw Exception('HF API error ${res.statusCode}: ${res.body}');
  }

  /// Aggregate multiple frame results (video) into single decision.
  /// Strategy: average fake probability vs real probability.
  InferenceResult aggregateFrames(List<InferenceResult> frames) {
    if (frames.isEmpty) {
      return InferenceResult(label: 'unknown', score: 0.0);
    }
    double fakeSum = 0, realSum = 0;
    for (final r in frames) {
      if (r.isFake) {
        fakeSum += r.score;
      } else {
        realSum += r.score;
      }
    }
    final fakeAvg = fakeSum / frames.length;
    final realAvg = realSum / frames.length;

    if (fakeAvg >= realAvg) {
      return InferenceResult(label: 'fake', score: fakeAvg.clamp(0, 1));
    } else {
      return InferenceResult(label: 'real', score: realAvg.clamp(0, 1));
    }
  }
}
