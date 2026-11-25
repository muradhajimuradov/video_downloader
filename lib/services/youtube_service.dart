import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/video_model.dart';

class YouTubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  static final RegExp _youtubeUrlRegex = RegExp(
    r'^(https?://)?(www\.|m\.|music\.)?(youtube\.com/(watch\?v=|shorts/|live/|embed/)|youtu\.be/)[a-zA-Z0-9_\-]+',
    caseSensitive: false,
  );

  static final RegExp _youtubeUrlExtractorRegex = RegExp(
    r'(https?://)?(www\.|m\.|music\.)?(youtube\.com/(watch\?v=|shorts/|live/|embed/)|youtu\.be/)[a-zA-Z0-9_\-]+',
    caseSensitive: false,
  );

  static bool isYouTubeUrl(String url) {
    if (url.trim().isEmpty) return false;
    return _youtubeUrlRegex.hasMatch(url.trim());
  }

  static String? extractYouTubeUrl(String text) {
    if (text.trim().isEmpty) return null;
    final match = _youtubeUrlExtractorRegex.firstMatch(text.trim());
    return match?.group(0);
  }

  /// Клиент VisionOS (используется современным yt-dlp)
  /// Исключает 403 Forbidden и зависания на чанках свыше 10 МБ,
  /// в отличие от стандартного androidSdkless, который YouTube блокирует при фрагментированной загрузке.
  static final YoutubeApiClient visionosClient = YoutubeApiClient(
    {
      'context': {
        'client': {
          'clientName': 'VISIONOS',
          'clientVersion': '1.02',
          'deviceMake': 'Apple',
          'deviceModel': 'RealityDevice17,1',
          'userAgent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15',
          'osName': 'visionOS',
          'osVersion': '26.5.23O471',
          'hl': 'en',
          'gl': 'US',
        },
      },
    },
    'https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
  );

  Future<VideoDetailsModel> fetchVideoDetails(String rawUrl) async {
    final cleanUrl = rawUrl.trim();
    final videoId = VideoId(cleanUrl);

    // Получаем метаданные видео
    final video = await _yt.videos.get(videoId);

    // Получаем манифест доступных потоков через VisionOS (быстро, без 403 и зависаний)
    StreamManifest manifest;
    try {
      manifest = await _yt.videos.streamsClient.getManifest(
        videoId,
        ytClients: [visionosClient],
      );
    } catch (_) {
      manifest = await _yt.videos.streamsClient.getManifest(videoId);
    }

    // 1. Извлекаем и группируем все звуковые дорожки
    final Map<String, List<AudioStreamInfo>> tracksMap = {};
    for (final a in manifest.audioOnly) {
      final track = a.audioTrack;
      final trackId = track?.id ?? 'default';
      tracksMap.putIfAbsent(trackId, () => []).add(a);
    }

    final List<AudioTrackModel> audioTracks = [];
    for (final entry in tracksMap.entries) {
      final streams = entry.value;
      final first = streams.first;
      final track = first.audioTrack;
      final rawName = track?.displayName ?? 'Оригинальный звук (Default)';
      final isOriginal = (track == null) ||
          track.audioIsDefault ||
          rawName.toLowerCase().contains('original');

      // Ищем лучший AAC / M4A поток (для мгновенного прямого слияния в MP4 без перекодирования)
      AudioStreamInfo? aacStream;
      for (final s in streams) {
        if (s.container.name == 'mp4' || s.audioCodec.contains('mp4a')) {
          if (aacStream == null || s.bitrate.bitsPerSecond > aacStream.bitrate.bitsPerSecond) {
            aacStream = s;
          }
        }
      }

      // Лучший поток по битрейту (может быть Opus для MP3 320k)
      final bestStream = streams.sortByBitrate().first;

      final displayName = isOriginal && !rawName.toLowerCase().contains('original')
          ? '$rawName (Оригинал)'
          : rawName;

      audioTracks.add(AudioTrackModel(
        id: entry.key,
        displayName: displayName,
        isOriginal: isOriginal,
        bestStream: bestStream,
        aacStream: aacStream,
      ));
    }

    // Сортировка звуковых дорожек: Оригинал на 1-м месте, затем Русский (если есть), затем остальные
    audioTracks.sort((a, b) {
      if (a.isOriginal && !b.isOriginal) return -1;
      if (!a.isOriginal && b.isOriginal) return 1;
      final aRu = a.displayName.toLowerCase().contains('russian') || a.displayName.toLowerCase().contains('русск');
      final bRu = b.displayName.toLowerCase().contains('russian') || b.displayName.toLowerCase().contains('русск');
      if (aRu && !bRu) return -1;
      if (!aRu && bRu) return 1;
      return a.displayName.compareTo(b.displayName);
    });

    final defaultAudioTrack = audioTracks.isNotEmpty ? audioTracks.first : null;
    final selectedAudioStream = defaultAudioTrack?.preferredStream;
    final selectedAudioSize = selectedAudioStream?.size.totalBytes ?? 0;

    final List<DownloadOption> options = [];

    // Резолюции с красивыми названиями на русском (как в Python-версии)
    final resNames = {
      4320: "8K UHD (4320p)",
      2160: "4K UHD (2160p)",
      1440: "2K QHD (1440p)",
      1080: "Full HD (1080p)",
      720: "HD (720p)",
      480: "480p",
      360: "360p",
      240: "240p",
      144: "144p",
    };

    // 2. Группируем раздельные видеопотоки высокого качества
    // Приоритет отдаем H.264 (avc1) в контейнере MP4 для мгновенного слияния и 100% совместимости
    final Map<int, VideoStreamInfo> highestStreamsByHeight = {};

    for (final v in manifest.videoOnly) {
      final h = v.videoResolution.height;
      final existing = highestStreamsByHeight[h];
      if (existing == null) {
        highestStreamsByHeight[h] = v;
      } else {
        final isExistingAvc = existing.container.name == 'mp4' && existing.videoCodec.startsWith('avc');
        final isCurrentAvc = v.container.name == 'mp4' && v.videoCodec.startsWith('avc');

        bool isBetter = false;
        if (isCurrentAvc && !isExistingAvc) {
          isBetter = true;
        } else if (!isCurrentAvc && isExistingAvc) {
          isBetter = false;
        } else {
          isBetter = v.bitrate.bitsPerSecond > existing.bitrate.bitsPerSecond;
        }

        if (isBetter) {
          highestStreamsByHeight[h] = v;
        }
      }
    }

    // Сортируем разрешения по убыванию (1080p, 720p и т.д. первыми)
    final sortedHeights = highestStreamsByHeight.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    for (final h in sortedHeights) {
      final vStream = highestStreamsByHeight[h]!;
      final name = resNames[h] ?? "${h}p";
      final approxSize = vStream.size.totalBytes + selectedAudioSize;
      final approxSizeStr = formatBytes(approxSize);
      final fps = vStream.framerate.framesPerSecond.round();
      final fpsStr = fps > 30 ? " • ${fps}fps" : "";

      options.add(DownloadOption(
        id: "video_${h}_${vStream.container.name}",
        label: "$name$fpsStr • ~$approxSizeStr",
        type: DownloadOptionType.mergedVideoAudio,
        height: h,
        fps: fps,
        approxSizeBytes: approxSize,
        extension: "mp4",
        videoStreamInfo: vStream,
        audioStreamInfo: selectedAudioStream,
      ));
    }

    // 3. Совмещенный (Muxed) поток (если доступен)
    if (manifest.muxed.isNotEmpty) {
      final bestMuxed = manifest.muxed.withHighestBitrate();
      final muxHeight = bestMuxed.videoResolution.height;
      final muxName = resNames[muxHeight] ?? "${muxHeight}p";
      final muxSizeStr = formatBytes(bestMuxed.size.totalBytes);

      options.add(DownloadOption(
        id: "best_muxed",
        label: "⚡ Быстрое скачивание: $muxName (Готовый файл $muxSizeStr)",
        type: DownloadOptionType.muxedVideo,
        height: muxHeight,
        fps: 30,
        approxSizeBytes: bestMuxed.size.totalBytes,
        extension: bestMuxed.container.name,
        muxedStreamInfo: bestMuxed,
      ));
    }

    // 4. Аудио-варианты (на основе выбранной звуковой дорожки)
    if (selectedAudioStream != null) {
      final audioSizeStr = formatBytes(selectedAudioStream.size.totalBytes);
      options.add(DownloadOption(
        id: "audio_m4a",
        label: "🎵 Только аудио (M4A / AAC — Без перекодирования • ~$audioSizeStr)",
        type: DownloadOptionType.audioM4a,
        approxSizeBytes: selectedAudioStream.size.totalBytes,
        extension: "m4a",
        audioStreamInfo: selectedAudioStream,
      ));

      final bestAudioForMp3 = defaultAudioTrack?.bestStream ?? selectedAudioStream;
      options.add(DownloadOption(
        id: "audio_mp3",
        label: "🎵 Только аудио (MP3 320 kbps — Высокое качество • ~$audioSizeStr)",
        type: DownloadOptionType.audioMp3,
        approxSizeBytes: bestAudioForMp3.size.totalBytes,
        extension: "mp3",
        audioStreamInfo: bestAudioForMp3,
      ));
    }

    return VideoDetailsModel(
      id: video.id.value,
      title: video.title,
      author: video.author,
      duration: video.duration,
      thumbnailUrl: video.thumbnails.highResUrl.isNotEmpty
          ? video.thumbnails.highResUrl
          : video.thumbnails.standardResUrl,
      webpageUrl: cleanUrl,
      options: options,
      audioTracks: audioTracks,
      selectedAudioTrack: defaultAudioTrack,
    );
  }

  List<DownloadOption> updateOptionsForAudioTrack(
    VideoDetailsModel details,
    AudioTrackModel track,
  ) {
    final selectedAudioStream = track.preferredStream;
    final bestMp3Stream = track.bestStream;

    return details.options.map((option) {
      if (option.type == DownloadOptionType.mergedVideoAudio) {
        return option.copyWith(
          audioStreamInfo: selectedAudioStream,
        );
      } else if (option.type == DownloadOptionType.audioM4a) {
        return option.copyWith(
          audioStreamInfo: selectedAudioStream,
        );
      } else if (option.type == DownloadOptionType.audioMp3) {
        return option.copyWith(
          audioStreamInfo: bestMp3Stream,
        );
      }
      return option;
    }).toList();
  }

  void dispose() {
    _yt.close();
  }
}
