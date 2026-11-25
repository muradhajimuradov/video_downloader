import 'dart:async';
import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/video_model.dart';
import 'storage_service.dart';
import 'history_service.dart';

typedef ProgressCallback = void Function(DownloadProgressData progress);

class DownloadService {
  final YoutubeExplode _yt = YoutubeExplode();
  bool _isCancelled = false;
  StreamSubscription<List<int>>? _currentSubscription;
  File? _currentActiveFile;

  void cancel() {
    _isCancelled = true;
    _currentSubscription?.cancel();
    _currentSubscription = null;
    try {
      if (_currentActiveFile != null && _currentActiveFile!.existsSync()) {
        _currentActiveFile!.deleteSync();
      }
    } catch (_) {}
  }

  Future<String> startDownload({
    required VideoDetailsModel video,
    required DownloadOption option,
    required ProgressCallback onProgress,
  }) async {
    _isCancelled = false;

    // Включаем WakeLock чтобы экран и процессор не засыпали при скачивании больших файлов
    try {
      await WakelockPlus.enable();
    } catch (_) {}

    try {
      // Запрашиваем разрешения на хранилище
      await StorageService.requestStoragePermission();

      // Папка сохранения
      final downloadDir = await StorageService.getDownloadDirectory();
      final sanitizedTitle = StorageService.sanitizeFileName(video.title);
      final finalFileName = "$sanitizedTitle.${option.extension}";
      final finalFilePath = "${downloadDir.path}/$finalFileName";

      // Временная папка на общем накопителе (вдоволь свободного места под большие файлы)
      final tempDir = await StorageService.getTempDirectory();

      onProgress(DownloadProgressData(
        percent: 0.0,
        statusMessage: "Подготовка к загрузке...",
      ));

      if (option.type == DownloadOptionType.muxedVideo) {
        // Прямой совмещенный поток (видео + аудио)
        await _downloadSingleStream(
          streamInfo: option.muxedStreamInfo!,
          targetPath: finalFilePath,
          statusPrefix: "Загрузка видео",
          onProgress: onProgress,
        );
      } else if (option.type == DownloadOptionType.audioM4a) {
        // Прямой поток аудио M4A
        await _downloadSingleStream(
          streamInfo: option.audioStreamInfo!,
          targetPath: finalFilePath,
          statusPrefix: "Загрузка аудио",
          onProgress: onProgress,
        );
      } else if (option.type == DownloadOptionType.audioMp3) {
        // Загрузка аудио во временный файл и конвертация через FFmpeg в MP3 320 kbps
        final ext = option.audioStreamInfo!.container.name;
        final tempAudioPath = "${tempDir.path}/temp_${DateTime.now().millisecondsSinceEpoch}.$ext";

        await _downloadSingleStream(
          streamInfo: option.audioStreamInfo!,
          targetPath: tempAudioPath,
          statusPrefix: "Загрузка исходного аудио",
          onProgress: (p) {
            onProgress(p.copyWith(
              percent: p.percent * 0.85, // 85% загрузка, 15% конвертация
            ));
          },
        );

        if (_isCancelled) throw Exception("Загрузка отменена пользователем");

        onProgress(DownloadProgressData(
          percent: 90.0,
          speedText: "--",
          etaText: "--:--",
          statusMessage: "Конвертация в MP3 (320 kbps) через FFmpeg...",
        ));

        final args = [
          '-y',
          '-i', tempAudioPath,
          '-vn',
          '-ar', '44100',
          '-ac', '2',
          '-b:a', '320k',
          finalFilePath,
        ];
        final session = await FFmpegKit.executeWithArguments(args);
        final returnCode = await session.getReturnCode();

        // Удаляем временный файл
        try {
          final tempF = File(tempAudioPath);
          if (await tempF.exists()) await tempF.delete();
        } catch (_) {}

        if (!ReturnCode.isSuccess(returnCode)) {
          final logs = await session.getLogsAsString();
          throw Exception("Ошибка конвертации FFmpeg: $logs");
        }
      } else if (option.type == DownloadOptionType.mergedVideoAudio) {
        // Раздельные потоки видео + аудио -> скачивание обоих и слияние через FFmpeg
        final vExt = option.videoStreamInfo!.container.name;
        final aExt = option.audioStreamInfo!.container.name;
        final tempVideoPath = "${tempDir.path}/temp_v_${DateTime.now().millisecondsSinceEpoch}.$vExt";
        final tempAudioPath = "${tempDir.path}/temp_a_${DateTime.now().millisecondsSinceEpoch}.$aExt";

        final vSize = option.videoStreamInfo!.size.totalBytes;
        final aSize = option.audioStreamInfo!.size.totalBytes;
        final totalSize = vSize + aSize;

        final vRatio = totalSize > 0 ? (vSize / totalSize) * 0.92 : 0.80;
        final aRatio = totalSize > 0 ? (aSize / totalSize) * 0.92 : 0.12;

        // 1. Скачиваем видеопоток
        await _downloadSingleStream(
          streamInfo: option.videoStreamInfo!,
          targetPath: tempVideoPath,
          statusPrefix: "Загрузка видеопотока (${option.height}p)",
          onProgress: (p) {
            final overallPercent = (p.percent / 100.0) * vRatio * 100.0;
            onProgress(p.copyWith(percent: overallPercent));
          },
        );

        if (_isCancelled) throw Exception("Загрузка отменена пользователем");

        // 2. Скачиваем аудиопоток
        await _downloadSingleStream(
          streamInfo: option.audioStreamInfo!,
          targetPath: tempAudioPath,
          statusPrefix: "Загрузка аудиодорожки",
          onProgress: (p) {
            final overallPercent = (vRatio * 100.0) + ((p.percent / 100.0) * aRatio * 100.0);
            onProgress(p.copyWith(percent: overallPercent));
          },
        );

        if (_isCancelled) throw Exception("Загрузка отменена пользователем");

        // 3. Объединение через FFmpeg
        onProgress(DownloadProgressData(
          percent: 94.0,
          speedText: "--",
          etaText: "--:--",
          statusMessage: "Мгновенное объединение в MP4 через FFmpeg...",
        ));

        // Если оба потока MP4/M4A, то делаем прямое копирование без перекодирования (-c copy) за 1 секунду
        final bool canFastCopyAudio = (aExt == 'mp4' || option.audioStreamInfo!.audioCodec.contains('mp4a'));

        final List<String> args = [
          '-y',
          '-i', tempVideoPath,
          '-i', tempAudioPath,
          '-c:v', 'copy',
          '-c:a', canFastCopyAudio ? 'copy' : 'aac',
          finalFilePath,
        ];

        final session = await FFmpegKit.executeWithArguments(args);
        final returnCode = await session.getReturnCode();

        // Удаляем временные файлы
        try {
          final tv = File(tempVideoPath);
          final ta = File(tempAudioPath);
          if (await tv.exists()) await tv.delete();
          if (await ta.exists()) await ta.delete();
        } catch (_) {}

        if (!ReturnCode.isSuccess(returnCode)) {
          final logs = await session.getLogsAsString();
          throw Exception("Ошибка слияния FFmpeg: $logs");
        }
      }

      final downloadedFile = File(finalFilePath);
      final finalSize = await downloadedFile.length();

      // Сохраняем в историю
      await HistoryService.addHistory(HistoryItem(
        id: "${video.id}_${DateTime.now().millisecondsSinceEpoch}",
        title: video.title,
        author: video.author,
        filePath: finalFilePath,
        fileSize: finalSize,
        downloadDate: DateTime.now(),
        thumbnailUrl: video.thumbnailUrl,
        isAudio: option.isAudioOnly,
      ));

      onProgress(DownloadProgressData(
        percent: 100.0,
        speedText: "-- МБ/с",
        downloadedText: formatBytes(finalSize),
        totalText: formatBytes(finalSize),
        etaText: "00:00",
        statusMessage: "Загрузка успешно завершена!",
        isDone: true,
        savedFilePath: finalFilePath,
      ));

      return finalFilePath;
    } catch (e) {
      if (_isCancelled) {
        onProgress(DownloadProgressData(
          percent: 0.0,
          isError: true,
          errorMessage: "Загрузка отменена пользователем.",
          statusMessage: "Загрузка отменена.",
        ));
      } else {
        onProgress(DownloadProgressData(
          percent: 0.0,
          isError: true,
          errorMessage: e.toString(),
          statusMessage: "Ошибка загрузки.",
        ));
      }
      rethrow;
    } finally {
      // Отключаем WakeLock после завершения или ошибки
      try {
        await WakelockPlus.disable();
      } catch (_) {}
    }
  }

  Future<void> _downloadSingleStream({
    required StreamInfo streamInfo,
    required String targetPath,
    required String statusPrefix,
    required ProgressCallback onProgress,
  }) async {
    final stream = _yt.videos.streamsClient.get(streamInfo);
    final targetFile = File(targetPath);
    _currentActiveFile = targetFile;

    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    final output = targetFile.openWrite();
    final totalBytes = streamInfo.size.totalBytes;
    int downloadedBytes = 0;

    final stopwatch = Stopwatch()..start();
    int lastDownloadedBytes = 0;
    int lastCheckTimeMs = 0;
    double currentSpeed = 0.0;

    final completer = Completer<void>();

    _currentSubscription = stream.listen(
      (chunk) {
        if (_isCancelled) {
          _currentSubscription?.cancel();
          output.close();
          completer.completeError(Exception("Загрузка отменена пользователем"));
          return;
        }

        output.add(chunk);
        downloadedBytes += chunk.length;

        final elapsedMs = stopwatch.elapsedMilliseconds;
        // Пересчитываем скорость раз в 400 мс для плавности
        if (elapsedMs - lastCheckTimeMs >= 400) {
          final timeDiffSec = (elapsedMs - lastCheckTimeMs) / 1000.0;
          final bytesDiff = downloadedBytes - lastDownloadedBytes;
          if (timeDiffSec > 0) {
            currentSpeed = bytesDiff / timeDiffSec;
          }
          lastDownloadedBytes = downloadedBytes;
          lastCheckTimeMs = elapsedMs;
        }

        final percent = totalBytes > 0 ? (downloadedBytes / totalBytes) * 100.0 : 0.0;
        final remainingBytes = totalBytes - downloadedBytes;
        final etaSec = currentSpeed > 0 ? (remainingBytes / currentSpeed).round() : 0;

        onProgress(DownloadProgressData(
          percent: percent.clamp(0.0, 100.0),
          speedText: formatSpeed(currentSpeed),
          downloadedText: formatBytes(downloadedBytes),
          totalText: formatBytes(totalBytes),
          etaText: formatEta(etaSec),
          statusMessage: "$statusPrefix: ${percent.toStringAsFixed(1)}%",
        ));
      },
      onDone: () async {
        await output.flush();
        await output.close();
        _currentActiveFile = null;
        completer.complete();
      },
      onError: (err) async {
        await output.close();
        _currentActiveFile = null;
        completer.completeError(err);
      },
      cancelOnError: true,
    );

    return completer.future;
  }

  void dispose() {
    _yt.close();
  }
}
