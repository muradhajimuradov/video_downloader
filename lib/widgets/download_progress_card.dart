import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../models/video_model.dart';
import '../theme/app_theme.dart';

class DownloadProgressCard extends StatelessWidget {
  final DownloadProgressData progress;
  final bool isDownloading;
  final VoidCallback onCancel;

  const DownloadProgressCard({
    super.key,
    required this.progress,
    required this.isDownloading,
    required this.onCancel,
  });

  void _openFile(BuildContext context) async {
    if (progress.savedFilePath != null) {
      final res = await OpenFilex.open(progress.savedFilePath!);
      if (res.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось открыть файл: ${res.message}')),
        );
      }
    }
  }

  void _shareFile() async {
    if (progress.savedFilePath != null) {
      await SharePlus.instance.share(ShareParams(files: [XFile(progress.savedFilePath!)]));
    }
  }

  @override
  Widget build(BuildContext context) {
    final percent = progress.percent;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  progress.isDone
                      ? Icons.check_circle_rounded
                      : (progress.isError ? Icons.error_outline_rounded : Icons.downloading_rounded),
                  color: progress.isDone
                      ? AppColors.accentGreen
                      : (progress.isError ? const Color(0xFFEF4444) : AppColors.primary),
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    progress.statusMessage,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: progress.isDone
                          ? AppColors.accentGreen
                          : (progress.isError ? const Color(0xFFEF4444) : AppColors.textPrimary),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${percent.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Прогресс-бар
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress.isDone ? 1.0 : (percent / 100.0).clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: AppColors.surface,
                valueColor: AlwaysStoppedAnimation<Color>(
                  progress.isDone
                      ? AppColors.accentGreen
                      : (progress.isError ? const Color(0xFFEF4444) : AppColors.primary),
                ),
              ),
            ),
            const SizedBox(height: 14),
            // Метрики (Скорость, Скачано, ETA)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.cardBorder.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _MetricItem(
                    label: 'Скорость',
                    value: progress.speedText,
                    icon: Icons.speed_rounded,
                  ),
                  Container(width: 1, height: 28, color: AppColors.cardBorder),
                  _MetricItem(
                    label: 'Объем',
                    value: '${progress.downloadedText} / ${progress.totalText}',
                    icon: Icons.pie_chart_outline_rounded,
                  ),
                  Container(width: 1, height: 28, color: AppColors.cardBorder),
                  _MetricItem(
                    label: 'Осталось',
                    value: progress.etaText,
                    icon: Icons.timer_outlined,
                  ),
                ],
              ),
            ),
            if (isDownloading) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.cancel_rounded, size: 18, color: Color(0xFFEF4444)),
                  label: const Text(
                    'Отменить загрузку',
                    style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0x55EF4444)),
                  ),
                ),
              ),
            ],
            if (progress.isDone && progress.savedFilePath != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _openFile(context),
                      icon: const Icon(Icons.play_circle_fill_rounded, size: 18),
                      label: const Text('Открыть файл'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentGreen,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    onPressed: _shareFile,
                    icon: const Icon(Icons.share_rounded, color: AppColors.textPrimary),
                    tooltip: 'Поделиться',
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppColors.cardBorder),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MetricItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: AppColors.textTertiary),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
