import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class StorageService {
  static Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      if (sdkInt >= 33) {
        // Android 13+
        final videoStatus = await Permission.videos.request();
        final audioStatus = await Permission.audio.request();
        return videoStatus.isGranted || audioStatus.isGranted;
      } else if (sdkInt >= 30) {
        // Android 11-12
        var status = await Permission.storage.request();
        if (!status.isGranted) {
          status = await Permission.manageExternalStorage.request();
        }
        return status.isGranted;
      } else {
        // Android 10 and lower
        final status = await Permission.storage.request();
        return status.isGranted;
      }
    } catch (e) {
      // Fallback
      return true;
    }
  }

  static Future<Directory> getDownloadDirectory() async {
    if (Platform.isAndroid) {
      // Пытаемся получить общедоступную системную папку Download
      final standardDownloadDir = Directory('/storage/emulated/0/Download/YouTubeDownloader');
      try {
        if (!await standardDownloadDir.exists()) {
          await standardDownloadDir.create(recursive: true);
        }
        return standardDownloadDir;
      } catch (_) {
        // Если доступ ограничен scoped storage, пробуем стандартную папку Download
        try {
          final rootDownloadDir = Directory('/storage/emulated/0/Download');
          if (await rootDownloadDir.exists()) {
            return rootDownloadDir;
          }
        } catch (_) {}
      }

      // Fallback: path_provider downloads or external storage
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        final target = Directory('${extDir.path}/YouTubeDownloader');
        if (!await target.exists()) {
          await target.create(recursive: true);
        }
        return target;
      }
    }

    final fallback = await getApplicationDocumentsDirectory();
    return fallback;
  }

  static Future<Directory> getTempDirectory() async {
    final downloadDir = await getDownloadDirectory();
    final tempDir = Directory('${downloadDir.path}/.temp');
    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }
    return tempDir;
  }

  static String sanitizeFileName(String name) {
    // Удаляем или заменяем запрещенные символы в имени файла
    var clean = name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // Ограничиваем длину имени (Android FS лимит 255 байт; русский текст 2 байта/символ)
    if (clean.length > 80) {
      clean = clean.substring(0, 80).trim();
    }
    return clean.isEmpty ? 'video' : clean;
  }
}
