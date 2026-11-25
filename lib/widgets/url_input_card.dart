import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/youtube_service.dart';
import '../theme/app_theme.dart';

class UrlInputCard extends StatelessWidget {
  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback onAnalyze;
  final VoidCallback onClear;
  final Function(String) onUrlPasted;

  const UrlInputCard({
    super.key,
    required this.controller,
    required this.isLoading,
    required this.onAnalyze,
    required this.onClear,
    required this.onUrlPasted,
  });

  Future<void> _handlePaste() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboardData?.text?.trim() ?? '';
    if (text.isNotEmpty) {
      controller.text = text;
      onUrlPasted(text);
      if (YouTubeService.isYouTubeUrl(text)) {
        onAnalyze();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.link_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Ссылка на видео:',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: isLoading ? null : _handlePaste,
                  icon: const Icon(Icons.content_paste_rounded, size: 16),
                  label: const Text('Вставить'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accentBlue,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              enabled: !isLoading,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'https://www.youtube.com/watch?v=... или youtu.be/...',
                hintStyle: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 13,
                ),
                filled: true,
                fillColor: AppColors.inputBackground,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.inputBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.inputBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.inputBorderFocused, width: 1.5),
                ),
                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: onClear,
                        color: AppColors.textSecondary,
                      )
                    : null,
              ),
              onChanged: (val) {
                onUrlPasted(val);
              },
              onSubmitted: (_) {
                if (!isLoading && controller.text.isNotEmpty) {
                  onAnalyze();
                }
              },
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isLoading || controller.text.trim().isEmpty ? null : onAnalyze,
                icon: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.search_rounded, size: 18),
                label: Text(
                  isLoading ? 'Анализ видео...' : 'Анализировать видео',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.35),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
