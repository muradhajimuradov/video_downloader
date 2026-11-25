import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/video_model.dart';

class HistoryService {
  static const String _storageKey = 'download_history_items';

  static Future<List<HistoryItem>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_storageKey) ?? [];
    return rawList.map((str) {
      try {
        final map = jsonDecode(str) as Map<String, dynamic>;
        return HistoryItem.fromJson(map);
      } catch (_) {
        return null;
      }
    }).whereType<HistoryItem>().toList();
  }

  static Future<void> addHistory(HistoryItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await getHistory();
    // Вставляем в начало, избегая дубликатов по ID и filePath
    items.removeWhere((x) => x.id == item.id || x.filePath == item.filePath);
    items.insert(0, item);

    // Ограничиваем историю последними 50 записями
    if (items.length > 50) {
      items.removeRange(50, items.length);
    }

    final rawList = items.map((x) => jsonEncode(x.toJson())).toList();
    await prefs.setStringList(_storageKey, rawList);
  }

  static Future<void> removeItem(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await getHistory();
    items.removeWhere((x) => x.id == id);
    final rawList = items.map((x) => jsonEncode(x.toJson())).toList();
    await prefs.setStringList(_storageKey, rawList);
  }

  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
