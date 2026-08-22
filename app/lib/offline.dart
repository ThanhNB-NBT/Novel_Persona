import 'dart:io';
import 'dart:math';

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
    return openDatabase(path, version: 2,
        onCreate: (db, _) async {
      await db.execute('''
        create table novels(
          novel_id integer primary key, title text, author text,
          cover_url text, total integer, downloaded_at text)''');
      await db.execute('''
        create table chapters(
          novel_id integer, chapter_index integer, title_vi text, content_vi text,
          server_updated_at text,
          primary key(novel_id, chapter_index))''');
    }, onUpgrade: (db, oldV, newV) async {
      // v2: thêm mốc updated_at phía server để phát hiện bản offline stale
      if (oldV < 2) {
        await db.execute('alter table chapters add column server_updated_at text');
      }
    });
  }

  /// Tải mọi chương ĐÃ DỊCH của 1 truyện về máy. Trả số chương đã lưu. Lấy theo lô
  /// `range` để vượt cap ~1000 dòng/response (truyện mấy nghìn chương vẫn tải đủ).
  Future<int> downloadNovel(Rec novel) async {
    final id = novel['id'] as int;
    const chunk = 1000;
    final db = await _database;
    // Hỏi index trước, nội dung sau: bấm tải lại truyện 3000 chương từng kéo về nguyên
    // ~24MB content_vi dù máy đã có đủ. Danh sách index chỉ vài chục KB, phần thân chỉ
    // tải cho chương còn thiếu (chương chen giữa mới dịch xong cũng bắt được).
    final serverIdx = <int>[];
    for (var from = 0;; from += chunk) {
      final page = List<Rec>.from(await sb
          .from('chapters')
          .select('chapter_index')
          .eq('novel_id', id)
          .eq('translation_status', 'done')
          .order('chapter_index')
          .range(from, from + chunk - 1));
      serverIdx.addAll(page.map((r) => r['chapter_index'] as int));
      if (page.length < chunk) break;
    }
    final localIdx = {
      for (final r in await db.query('chapters',
          columns: ['chapter_index'], where: 'novel_id = ?', whereArgs: [id]))
        r['chapter_index'] as int
    };
    final missing = serverIdx.where((i) => !localIdx.contains(i)).toList();
    final rows = <Rec>[];
    for (var i = 0; i < missing.length; i += 200) {
      final batchIdx = missing.sublist(i, min(i + 200, missing.length));
      rows.addAll(List<Rec>.from(await sb
          .from('chapters')
          .select('chapter_index, title_vi, content_vi, updated_at')
          .eq('novel_id', id)
          .inFilter('chapter_index', batchIdx)));
    }
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'chapters',
        {
          'novel_id': id,
          'chapter_index': r['chapter_index'],
          'title_vi': r['title_vi'],
          'content_vi': r['content_vi'],
          'server_updated_at': r['updated_at'] as String?,
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
        'total': serverIdx.length,
        'downloaded_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await batch.commit(noResult: true);
    // Tổng chương đang có offline, không phải số vừa tải: bấm lại lần 2 mà chỉ thiếu 0
    // chương vẫn phải báo "đã tải 3000 chương", không phải "chưa có chương nào".
    return serverIdx.length;
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

  /// Kiểm tra NỀN 1 chương local còn khớp server không (so mốc updated_at).
  /// Server đổi (dịch lại/sửa/glossary patch) → đè bản mới xuống local và trả
  /// true để caller refetch. Mất mạng → false, đọc tiếp bản local như cũ.
  Future<bool> refreshIfStale(int novelId, int index) async {
    final db = await _database;
    final localRows = await db.query('chapters',
        columns: ['server_updated_at'],
        where: 'novel_id = ? and chapter_index = ?',
        whereArgs: [novelId, index],
        limit: 1);
    if (localRows.isEmpty) return false; // chưa tải offline — nhánh online lo
    final server = await sb
        .from('chapters')
        .select('title_vi, content_vi, updated_at, translation_status')
        .eq('novel_id', novelId)
        .eq('chapter_index', index)
        .maybeSingle();
    if (server == null || server['translation_status'] != 'done') {
      return false; // chương phía server bị reset — giữ bản đã tải cho đọc tiếp
    }
    if (server['updated_at'] == localRows.first['server_updated_at']) {
      return false; // chưa đổi, không tốn ghi DB
    }
    await db.insert(
      'chapters',
      {
        'novel_id': novelId,
        'chapter_index': index,
        'title_vi': server['title_vi'],
        'content_vi': server['content_vi'],
        'server_updated_at': server['updated_at'],
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return true;
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
