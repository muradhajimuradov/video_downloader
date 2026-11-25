import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../models/video_model.dart';
import '../services/history_service.dart';
import '../theme/app_theme.dart';

class DownloadHistorySheet extends StatefulWidget {
  final VoidCallback onHistoryChanged;

  const DownloadHistorySheet({
    super.key,
    required this.onHistoryChanged,
  });

  @override
  State<DownloadHistorySheet> createState() => _DownloadHistorySheetState();
}

class _DownloadHistorySheetState extends State<DownloadHistorySheet> {
  List<HistoryItem> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await HistoryService.getHistory();
    if (mounted) {
      setState(() {
        _items = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteItem(HistoryItem item) async {
    await HistoryService.removeItem(item.id);
    widget.onHistoryChanged();
    _load();
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Очистить историю?'),
        content: const Text('Записи будут удалены из истории приложения (сами файлы останутся на диске).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await HistoryService.clearHistory();
      widget.onHistoryChanged();
      _load();
    }
  }

  void _openFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Файл не найден на устройстве (возможно, был перемещен или удален).')),
        );
      }
      return;
    }
    await OpenFilex.open(path);
  }

  void _shareFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.cardBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Заголовок
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.history_rounded, color: AppColors.primary, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'История загрузок',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                if (_items.isNotEmpty)
                  TextButton.icon(
                    onPressed: _clearAll,
                    icon: const Icon(Icons.delete_sweep_rounded, size: 18, color: Color(0xFFEF4444)),
                    label: const Text('Очистить', style: TextStyle(color: Color(0xFFEF4444))),
                  ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.cardBorder),
          // Список
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _items.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.folder_open_rounded, size: 48, color: AppColors.textTertiary),
                            SizedBox(height: 12),
                            Text(
                              'История загрузок пуста',
                              style: TextStyle(
                                fontSize: 15,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Скачанные видео и треки появятся здесь',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                children: [
                                  // Миниатюра
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox(
                                      width: 60,
                                      height: 60,
                                      child: item.thumbnailUrl != null
                                          ? Image.network(
                                              item.thumbnailUrl!,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) => Container(
                                                color: AppColors.surface,
                                                child: Icon(
                                                  item.isAudio ? Icons.music_note_rounded : Icons.videocam_rounded,
                                                  color: AppColors.textSecondary,
                                                ),
                                              ),
                                            )
                                          : Container(
                                              color: AppColors.surface,
                                              child: Icon(
                                                item.isAudio ? Icons.music_note_rounded : Icons.videocam_rounded,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Информация
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          '${item.author} • ${formatBytes(item.fileSize)}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Кнопки действий
                                  IconButton(
                                    icon: const Icon(Icons.play_circle_fill_rounded, color: AppColors.accentGreen),
                                    tooltip: 'Открыть',
                                    onPressed: () => _openFile(item.filePath),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.share_rounded, size: 20, color: AppColors.textSecondary),
                                    tooltip: 'Поделиться',
                                    onPressed: () => _shareFile(item.filePath),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textTertiary),
                                    tooltip: 'Удалить из списка',
                                    onPressed: () => _deleteItem(item),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
