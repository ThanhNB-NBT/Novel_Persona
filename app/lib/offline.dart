import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
// sqflite_common_ffi re-export toàn bộ API sqflite (openDatabase/getDatabasesPath/
// ConflictAlgorithm/databaseFactory). Mobile dùng factory mặc định của plugin sqflite
// (vẫn có trong pubspec); desktop set databaseFactoryFfi ở _open().
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'data.dart';

/// Lưu chương đã dịch xuống SQLite để đọc offline. sqflite chạy Android/iOS; desktop
/// (Windows/Linux/macOS — máy dev) cần khởi tạo ffi. Chỉ lưu chương `done` (có content_vi).
class OfflineStore {
  Database? _db;

  Future<Database> get _database async => _db ??= await _open();

  Future<Database> _open() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final path = p.join(await getDatabasesPath(), 'offline.db');
    return openDatabase(path, version: 1, onCreate: (db, _) async {
      await db.execute('''
        create table novels(
          novel_id integer primary key, title text, author text,
          cover_url text, total integer, downloaded_at text)''');
      await db.execute('''
        create table chapters(
          novel_id integer, chapter_index integer, title_vi text, content_vi text,
          primary key(novel_id, chapter_index))''');
    });
  }

  /// Tải mọi chương ĐÃ DỊCH của 1 truyện về máy. Trả số chương đã lưu. Lấy theo lô
  /// `range` để vượt cap ~1000 dòng/response (truyện mấy nghìn chương vẫn tải đủ).
  Future<int> downloadNovel(Rec novel) async {
    final id = novel['id'] as int;
    const chunk = 1000;
    final rows = <Rec>[];
    for (var from = 0;; from += chunk) {
      final page = List<Rec>.from(await sb
          .from('chapters')
          .select('chapter_index, title_vi, content_vi')
          .eq('novel_id', id)
          .eq('translation_status', 'done')
          .order('chapter_index')
          .range(from, from + chunk - 1));
      rows.addAll(page);
      if (page.length < chunk) break;
    }
    final db = await _database;
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'chapters',
        {
          'novel_id': id,
          'chapter_index': r['chapter_index'],
          'title_vi': r['title_vi'],
          'content_vi': r['content_vi'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    batch.insert(
      'novels',
      {
        'novel_id': id,
        'title': novel['title_vi'] ?? novel['title_zh'],
        'author': novel['author_vi'] ?? novel['author_zh'],
        'cover_url': novel['cover_url'],
        'total': rows.length,
        'downloaded_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await batch.commit(noResult: true);
    return rows.length;
  }

  /// 1 chương local — trả dạng khớp chapterProvider (title_vi/content_vi/status).
  Future<Rec?> getChapter(int novelId, int index) async {
    final db = await _database;
    final rows = await db.query('chapters',
        columns: ['chapter_index', 'title_vi', 'content_vi'],
        where: 'novel_id = ? and chapter_index = ?',
        whereArgs: [novelId, index],
        limit: 1);
    if (rows.isEmpty) return null;
    return {...rows.first, 'translation_status': 'done'};
  }

  Future<bool> hasNovel(int novelId) async {
    final db = await _database;
    final r = await db.query('novels',
        columns: ['novel_id'], where: 'novel_id = ?', whereArgs: [novelId], limit: 1);
    return r.isNotEmpty;
  }

  Future<List<Rec>> listNovels() async {
    final db = await _database;
    return List<Rec>.from(
        await db.query('novels', orderBy: 'downloaded_at desc'));
  }

  Future<void> deleteNovel(int novelId) async {
    final db = await _database;
    await db.delete('chapters', where: 'novel_id = ?', whereArgs: [novelId]);
    await db.delete('novels', where: 'novel_id = ?', whereArgs: [novelId]);
  }

  /// Dung lượng file DB offline (byte) — hiển thị tổng "đã dùng".
  Future<int> totalSizeBytes() async {
    final f = File(p.join(await getDatabasesPath(), 'offline.db'));
    return await f.exists() ? await f.length() : 0;
  }
}

final offlineStore = OfflineStore();

/// Truyện đã tải offline (cho danh sách + xóa).
final offlineNovelsProvider =
    FutureProvider.autoDispose<List<Rec>>((ref) => offlineStore.listNovels());

/// 1 truyện đã tải offline chưa (cho nút Tải/Xóa ở màn chi tiết).
final isDownloadedProvider = FutureProvider.autoDispose.family<bool, int>(
    (ref, novelId) => offlineStore.hasNovel(novelId));

/// Tổng dung lượng bản offline (byte).
final offlineSizeProvider =
    FutureProvider.autoDispose<int>((ref) => offlineStore.totalSizeBytes());
