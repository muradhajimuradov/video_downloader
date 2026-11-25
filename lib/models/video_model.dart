import 'dart:math';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

enum DownloadOptionType {
  muxedVideo,       // Already has both video and audio in a single stream (e.g. 720p, 360p)
  mergedVideoAudio, // Separate high-def video stream + best audio stream merged via FFmpeg (e.g. 1080p, 1440p, 4K)
  audioM4a,         // Direct M4A/AAC stream
  audioMp3,         // Converted to MP3 320 kbps via FFmpeg
}

class AudioTrackModel {
  final String id;
  final String displayName;
  final bool isOriginal;
  final AudioStreamInfo bestStream;
  final AudioStreamInfo? aacStream; // Preferred M4A/AAC for lossless fast copy

  AudioTrackModel({
    required this.id,
    required this.displayName,
    required this.isOriginal,
    required this.bestStream,
    this.aacStream,
  });

  AudioStreamInfo get preferredStream => aacStream ?? bestStream;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioTrackModel &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class DownloadOption {
  final String id;
  final String label;
  final DownloadOptionType type;
  final int? height;
  final int? fps;
  final int? approxSizeBytes;
  final String extension;
  final VideoStreamInfo? videoStreamInfo;
  final AudioStreamInfo? audioStreamInfo;
  final MuxedStreamInfo? muxedStreamInfo;

  DownloadOption({
    required this.id,
    required this.label,
    required this.type,
    this.height,
    this.fps,
    this.approxSizeBytes,
    required this.extension,
    this.videoStreamInfo,
    this.audioStreamInfo,
    this.muxedStreamInfo,
  });

  DownloadOption copyWith({
    AudioStreamInfo? audioStreamInfo,
  }) {
    return DownloadOption(
      id: id,
      label: label,
      type: type,
      height: height,
      fps: fps,
      approxSizeBytes: approxSizeBytes,
      extension: extension,
      videoStreamInfo: videoStreamInfo,
      audioStreamInfo: audioStreamInfo ?? this.audioStreamInfo,
      muxedStreamInfo: muxedStreamInfo,
    );
  }

  bool get isAudioOnly =>
      type == DownloadOptionType.audioM4a || type == DownloadOptionType.audioMp3;

  bool get requiresFFmpeg =>
      type == DownloadOptionType.mergedVideoAudio ||
      type == DownloadOptionType.audioMp3;
}

class VideoDetailsModel {
  final String id;
  final String title;
  final String author;
  final Duration? duration;
  final String thumbnailUrl;
  final String webpageUrl;
  final List<DownloadOption> options;
  final List<AudioTrackModel> audioTracks;
  final AudioTrackModel? selectedAudioTrack;

  VideoDetailsModel({
    required this.id,
    required this.title,
    required this.author,
    required this.duration,
    required this.thumbnailUrl,
    required this.webpageUrl,
    required this.options,
    this.audioTracks = const [],
    this.selectedAudioTrack,
  });

  VideoDetailsModel copyWith({
    List<DownloadOption>? options,
    List<AudioTrackModel>? audioTracks,
    AudioTrackModel? selectedAudioTrack,
  }) {
    return VideoDetailsModel(
      id: id,
      title: title,
      author: author,
      duration: duration,
      thumbnailUrl: thumbnailUrl,
      webpageUrl: webpageUrl,
      options: options ?? this.options,
      audioTracks: audioTracks ?? this.audioTracks,
      selectedAudioTrack: selectedAudioTrack ?? this.selectedAudioTrack,
    );
  }

  String get formattedDuration => formatDuration(duration);
}

class DownloadProgressData {
  final double percent;
  final String speedText;
  final String downloadedText;
  final String totalText;
  final String etaText;
  final String statusMessage;
  final bool isDone;
  final bool isError;
  final String? errorMessage;
  final String? savedFilePath;

  DownloadProgressData({
    this.percent = 0.0,
    this.speedText = "-- МБ/с",
    this.downloadedText = "0 Б",
    this.totalText = "0 Б",
    this.etaText = "--:--",
    this.statusMessage = "Ожидание...",
    this.isDone = false,
    this.isError = false,
    this.errorMessage,
    this.savedFilePath,
  });

  DownloadProgressData copyWith({
    double? percent,
    String? speedText,
    String? downloadedText,
    String? totalText,
    String? etaText,
    String? statusMessage,
    bool? isDone,
    bool? isError,
    String? errorMessage,
    String? savedFilePath,
  }) {
    return DownloadProgressData(
      percent: percent ?? this.percent,
      speedText: speedText ?? this.speedText,
      downloadedText: downloadedText ?? this.downloadedText,
      totalText: totalText ?? this.totalText,
      etaText: etaText ?? this.etaText,
      statusMessage: statusMessage ?? this.statusMessage,
      isDone: isDone ?? this.isDone,
      isError: isError ?? this.isError,
      errorMessage: errorMessage ?? this.errorMessage,
      savedFilePath: savedFilePath ?? this.savedFilePath,
    );
  }
}

class HistoryItem {
  final String id;
  final String title;
  final String author;
  final String filePath;
  final int fileSize;
  final DateTime downloadDate;
  final String? thumbnailUrl;
  final bool isAudio;

  HistoryItem({
    required this.id,
    required this.title,
    required this.author,
    required this.filePath,
    required this.fileSize,
    required this.downloadDate,
    this.thumbnailUrl,
    required this.isAudio,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'filePath': filePath,
        'fileSize': fileSize,
        'downloadDate': downloadDate.toIso8601String(),
        'thumbnailUrl': thumbnailUrl,
        'isAudio': isAudio,
      };

  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        author: json['author'] as String? ?? '',
        filePath: json['filePath'] as String? ?? '',
        fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
        downloadDate: json['downloadDate'] != null
            ? DateTime.tryParse(json['downloadDate'] as String) ?? DateTime.now()
            : DateTime.now(),
        thumbnailUrl: json['thumbnailUrl'] as String?,
        isAudio: json['isAudio'] as bool? ?? false,
      );
}

// Утилиты форматирования (аналогичные Python-версии)
String formatBytes(num? sizeBytes) {
  if (sizeBytes == null || sizeBytes <= 0) return "Н/Д";
  const sizeNames = ["Б", "КБ", "МБ", "ГБ", "ТБ"];
  int i = (log(sizeBytes) / log(1024)).floor();
  if (i < 0) i = 0;
  if (i >= sizeNames.length) i = sizeNames.length - 1;
  double p = pow(1024, i).toDouble();
  double s = sizeBytes / p;
  return "${s.toStringAsFixed(1)} ${sizeNames[i]}";
}

String formatDuration(Duration? duration) {
  if (duration == null) return "00:00";
  int totalSeconds = duration.inSeconds;
  int h = totalSeconds ~/ 3600;
  int m = (totalSeconds % 3600) ~/ 60;
  int s = totalSeconds % 60;
  if (h > 0) {
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

String formatSpeed(double? bytesPerSec) {
  if (bytesPerSec == null || bytesPerSec <= 0) return "-- МБ/с";
  if (bytesPerSec >= 1024 * 1024) {
    return "${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} МБ/с";
  }
  return "${(bytesPerSec / 1024).toStringAsFixed(0)} КБ/с";
}

String formatEta(int? etaSeconds) {
  if (etaSeconds == null || etaSeconds <= 0) return "--:--";
  int m = etaSeconds ~/ 60;
  int s = etaSeconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
