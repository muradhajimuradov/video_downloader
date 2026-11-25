import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/video_model.dart';
import 'services/youtube_service.dart';
import 'services/download_service.dart';
import 'services/storage_service.dart';
import 'services/history_service.dart';
import 'theme/app_theme.dart';
import 'widgets/header_widget.dart';
import 'widgets/url_input_card.dart';
import 'widgets/video_info_card.dart';
import 'widgets/quality_selector_card.dart';
import 'widgets/storage_card.dart';
import 'widgets/download_progress_card.dart';
import 'widgets/download_history_sheet.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const YouTubeDownloaderApp());
}

class YouTubeDownloaderApp extends StatelessWidget {
  const YouTubeDownloaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YouTube Downloader',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const MethodChannel _shareChannel =
      MethodChannel('com.example.youtube_downloader/share');

  final TextEditingController _urlController = TextEditingController();
  final YouTubeService _ytService = YouTubeService();
  final DownloadService _downloadService = DownloadService();

  bool _isAnalyzing = false;
  bool _isDownloading = false;
  VideoDetailsModel? _videoDetails;
  DownloadOption? _selectedOption;
  DownloadProgressData? _downloadProgress;

  String _savePath = '';
  int _historyCount = 0;
  String _lastCheckedClipboard = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initApp();
    _initShareReceiver();
  }

  void _initShareReceiver() {
    // 1. Проверяем, было ли приложение запущено через кнопку "Поделиться"
    _checkInitialSharedText();

    // 2. Слушаем события "Поделиться", если приложение уже открыто в фоне
    _shareChannel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedTextReceived') {
        final text = call.arguments as String?;
        if (text != null && mounted) {
          _handleSharedContent(text);
        }
      }
    });
  }

  Future<void> _checkInitialSharedText() async {
    try {
      final sharedText =
          await _shareChannel.invokeMethod<String>('getInitialSharedText');
      if (sharedText != null && sharedText.isNotEmpty && mounted) {
        _handleSharedContent(sharedText);
      }
    } catch (_) {}
  }

  void _handleSharedContent(String text) {
    final extractedUrl = YouTubeService.extractYouTubeUrl(text);
    if (extractedUrl != null && extractedUrl.isNotEmpty) {
      _urlController.text = extractedUrl;
      _analyzeUrl(extractedUrl);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _urlController.dispose();
    _ytService.dispose();
    _downloadService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkClipboard();
    }
  }

  Future<void> _initApp() async {
    // Получаем путь сохранения
    final dir = await StorageService.getDownloadDirectory();
    setState(() {
      _savePath = dir.path;
    });

    _refreshHistoryCount();

    // Проверяем буфер обмена при первом запуске через небольшую задержку
    Future.delayed(const Duration(milliseconds: 400), _checkClipboard);
  }

  Future<void> _refreshHistoryCount() async {
    final list = await HistoryService.getHistory();
    if (mounted) {
      setState(() {
        _historyCount = list.length;
      });
    }
  }

  Future<void> _checkClipboard() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clipboardData?.text?.trim() ?? '';
      if (text.isNotEmpty &&
          text != _lastCheckedClipboard &&
          YouTubeService.isYouTubeUrl(text) &&
          _urlController.text.trim().isEmpty) {
        _lastCheckedClipboard = text;
        if (mounted) {
          _urlController.text = text;
          _analyzeUrl(text);
        }
      }
    } catch (_) {}
  }

  Future<void> _analyzeUrl([String? directUrl]) async {
    final url = (directUrl ?? _urlController.text).trim();
    if (url.isEmpty) return;

    if (!YouTubeService.isYouTubeUrl(url)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Пожалуйста, введите корректную ссылку на видео YouTube.'),
        ),
      );
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _downloadProgress = null;
    });

    // Скрываем клавиатуру
    FocusScope.of(context).unfocus();

    try {
      final details = await _ytService.fetchVideoDetails(url);

      // Выбираем рекомендуемое качество по умолчанию: 1080p, затем 720p, либо первое доступное
      DownloadOption? defaultOption;
      if (details.options.isNotEmpty) {
        defaultOption = details.options.firstWhere(
          (o) => o.type == DownloadOptionType.mergedVideoAudio && o.height == 1080,
          orElse: () => details.options.firstWhere(
            (o) => o.type == DownloadOptionType.mergedVideoAudio && o.height == 720,
            orElse: () => details.options.first,
          ),
        );
      }

      setState(() {
        _videoDetails = details;
        _selectedOption = defaultOption;
        _isAnalyzing = false;
      });
    } catch (e) {
      setState(() {
        _isAnalyzing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка анализа видео: ${e.toString()}'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  void _onAudioTrackChanged(AudioTrackModel? newTrack) {
    if (_videoDetails == null || newTrack == null) return;
    final updatedOptions =
        _ytService.updateOptionsForAudioTrack(_videoDetails!, newTrack);

    DownloadOption? newSelectedOption;
    if (_selectedOption != null) {
      newSelectedOption = updatedOptions.firstWhere(
        (o) => o.id == _selectedOption!.id,
        orElse: () => updatedOptions.first,
      );
    } else {
      newSelectedOption = updatedOptions.first;
    }

    setState(() {
      _videoDetails = _videoDetails!.copyWith(
        options: updatedOptions,
        selectedAudioTrack: newTrack,
      );
      _selectedOption = newSelectedOption;
    });
  }

  Future<void> _startDownload() async {
    if (_videoDetails == null || _selectedOption == null) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = DownloadProgressData(
        percent: 0.0,
        statusMessage: 'Подготовка к загрузке...',
      );
    });

    try {
      await _downloadService.startDownload(
        video: _videoDetails!,
        option: _selectedOption!,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
            });
          }
        },
      );

      _refreshHistoryCount();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Видео успешно загружено!'),
            backgroundColor: AppColors.accentGreen,
          ),
        );
      }
    } catch (e) {
      // Ошибка обрабатывается внутри сервиса и обновляет прогресс
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  void _cancelDownload() {
    _downloadService.cancel();
    setState(() {
      _isDownloading = false;
    });
  }

  void _clearUrl() {
    _urlController.clear();
    setState(() {
      _videoDetails = null;
      _selectedOption = null;
      _downloadProgress = null;
    });
  }

  void _openHistorySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DownloadHistorySheet(
        onHistoryChanged: _refreshHistoryCount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          HeaderWidget(
            onOpenHistory: _openHistorySheet,
            historyCount: _historyCount,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  UrlInputCard(
                    controller: _urlController,
                    isLoading: _isAnalyzing,
                    onAnalyze: () => _analyzeUrl(),
                    onClear: _clearUrl,
                    onUrlPasted: (url) {
                      setState(() {});
                    },
                  ),
                  if (_videoDetails != null) ...[
                    const SizedBox(height: 14),
                    VideoInfoCard(video: _videoDetails!),
                    const SizedBox(height: 14),
                    QualitySelectorCard(
                      options: _videoDetails!.options,
                      selectedOption: _selectedOption,
                      onChanged: (opt) {
                        setState(() {
                          _selectedOption = opt;
                        });
                      },
                      audioTracks: _videoDetails!.audioTracks,
                      selectedAudioTrack: _videoDetails!.selectedAudioTrack,
                      onAudioTrackChanged: _onAudioTrackChanged,
                      isDownloading: _isDownloading,
                    ),
                    const SizedBox(height: 14),
                    StorageCard(savePath: _savePath),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _isDownloading ? null : _startDownload,
                        icon: const Icon(Icons.download_rounded, size: 22),
                        label: Text(
                          _selectedOption?.isAudioOnly == true
                              ? 'Скачать аудио'
                              : 'Скачать видео',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (_downloadProgress != null) ...[
                    const SizedBox(height: 16),
                    DownloadProgressCard(
                      progress: _downloadProgress!,
                      isDownloading: _isDownloading,
                      onCancel: _cancelDownload,
                    ),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
