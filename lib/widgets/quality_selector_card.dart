import 'package:flutter/material.dart';
import '../models/video_model.dart';
import '../theme/app_theme.dart';

class QualitySelectorCard extends StatelessWidget {
  final List<DownloadOption> options;
  final DownloadOption? selectedOption;
  final ValueChanged<DownloadOption?> onChanged;
  final List<AudioTrackModel> audioTracks;
  final AudioTrackModel? selectedAudioTrack;
  final ValueChanged<AudioTrackModel?>? onAudioTrackChanged;
  final bool isDownloading;

  const QualitySelectorCard({
    super.key,
    required this.options,
    required this.selectedOption,
    required this.onChanged,
    this.audioTracks = const [],
    this.selectedAudioTrack,
    this.onAudioTrackChanged,
    required this.isDownloading,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.tune_rounded,
                  color: AppColors.accentBlue,
                  size: 20,
                ),
                SizedBox(width: 8),
                Text(
                  'Качество и формат:',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.inputBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.inputBorder),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<DownloadOption>(
                  value: selectedOption,
                  isExpanded: true,
                  icon: const Icon(Icons.arrow_drop_down_rounded, color: AppColors.textPrimary),
                  dropdownColor: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  items: options.map((option) {
                    final isAudio = option.isAudioOnly;
                    return DropdownMenuItem<DownloadOption>(
                      value: option,
                      child: Row(
                        children: [
                          Icon(
                            isAudio ? Icons.music_note_rounded : Icons.video_file_rounded,
                            size: 18,
                            color: isAudio ? AppColors.accentAmber : AppColors.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              option.label,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: isDownloading ? null : onChanged,
                ),
              ),
            ),
            if (selectedOption != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Text(
                      'Формат: .${selectedOption!.extension.toUpperCase()}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (selectedOption!.requiresFFmpeg)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.accentBlue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.accentBlue.withValues(alpha: 0.3)),
                      ),
                      child: const Text(
                        'Обработка FFmpeg',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.accentBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.accentGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.accentGreen.withValues(alpha: 0.3)),
                      ),
                      child: const Text(
                        'Быстрое скачивание (без перекодирования)',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.accentGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (audioTracks.length > 1) ...[
              const SizedBox(height: 14),
              const Row(
                children: [
                  Icon(
                    Icons.audiotrack_rounded,
                    color: AppColors.accentAmber,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Звуковая дорожка (язык):',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.inputBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.inputBorder),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<AudioTrackModel>(
                    value: selectedAudioTrack ?? (audioTracks.isNotEmpty ? audioTracks.first : null),
                    isExpanded: true,
                    icon: const Icon(Icons.arrow_drop_down_rounded, color: AppColors.textPrimary),
                    dropdownColor: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    items: audioTracks.map((track) {
                      return DropdownMenuItem<AudioTrackModel>(
                        value: track,
                        child: Row(
                          children: [
                            Icon(
                              track.isOriginal ? Icons.star_rounded : Icons.translate_rounded,
                              size: 16,
                              color: track.isOriginal ? AppColors.accentAmber : AppColors.accentBlue,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                track.displayName,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textPrimary,
                                  fontWeight: track.isOriginal ? FontWeight.bold : FontWeight.normal,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: isDownloading ? null : onAudioTrackChanged,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
