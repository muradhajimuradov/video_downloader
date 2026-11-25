import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/models/video_model.dart';
import 'package:youtube_downloader/services/youtube_service.dart';

void main() {
  group('Formatters & Validators', () {
    test('formatBytes formats properly', () {
      expect(formatBytes(0), 'Н/Д');
      expect(formatBytes(1024), '1.0 КБ');
      expect(formatBytes(1024 * 1024 * 15.5), '15.5 МБ');
    });

    test('formatDuration formats properly', () {
      expect(formatDuration(const Duration(seconds: 45)), '00:45');
      expect(formatDuration(const Duration(minutes: 3, seconds: 20)), '03:20');
      expect(formatDuration(const Duration(hours: 1, minutes: 12, seconds: 5)), '01:12:05');
    });

    test('YouTube URL regex works accurately', () {
      expect(YouTubeService.isYouTubeUrl('https://www.youtube.com/watch?v=dQw4w9WgXcQ'), true);
      expect(YouTubeService.isYouTubeUrl('https://youtu.be/dQw4w9WgXcQ'), true);
      expect(YouTubeService.isYouTubeUrl('https://youtube.com/shorts/abcdef12345'), true);
      expect(YouTubeService.isYouTubeUrl('https://m.youtube.com/watch?v=dQw4w9WgXcQ'), true);
      expect(YouTubeService.isYouTubeUrl('https://google.com'), false);
      expect(YouTubeService.isYouTubeUrl('not a url'), false);
    });
  });
}
