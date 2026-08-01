import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/endpoint.dart';

void main() {
  test('ưu tiên active, giữ fallback và tương thích JSON cũ', () {
    final endpoints = endpointConfigCandidates(
      {
        'active': {'url': 'https://db-new.example.com/', 'anonKey': 'new'},
        'fallbacks': [
          {'url': 'https://db-old.example.com', 'anonKey': 'old'},
          {'url': 'http://public.example.com', 'anonKey': 'không-an-toàn'},
        ],
      },
      allowedHosts: {'db-new.example.com', 'db-old.example.com'},
    );
    expect(endpoints, [
      (url: 'https://db-new.example.com', anonKey: 'new'),
      (url: 'https://db-old.example.com', anonKey: 'old'),
    ]);
    expect(
      endpointConfigCandidates(
        {'url': 'https://legacy.example.com', 'anonKey': 'legacy'},
        allowedHosts: {'legacy.example.com'},
      ),
      [(url: 'https://legacy.example.com', anonKey: 'legacy')],
    );
    // JSON gõ sai (fallbacks không phải mảng) chỉ bị bỏ qua, KHÔNG ném lỗi treo app.
    expect(
      endpointConfigCandidates(
        {
          'active': {'url': 'https://db-new.example.com', 'anonKey': 'new'},
          'fallbacks': 'gõ-nhầm',
        },
        allowedHosts: {'db-new.example.com'},
      ),
      [(url: 'https://db-new.example.com', anonKey: 'new')],
    );
  });

  test('bỏ endpoint ngoài allowlist kể cả khi dùng HTTPS', () {
    final allowed = endpointAllowedHosts(
      'https://primary.supabase.co',
      'backup.example.com, BACKUP.example.com ',
    );
    expect(allowed, {'primary.supabase.co', 'backup.example.com'});
    expect(
      endpointConfigCandidates({
        'active': {'url': 'https://evil.example.com', 'anonKey': 'evil'},
        'fallbacks': [
          {'url': 'https://backup.example.com', 'anonKey': 'backup'},
        ],
      }, allowedHosts: allowed),
      [(url: 'https://backup.example.com', anonKey: 'backup')],
    );
  });

  test('đổi host Storage sau khi mirror nhưng giữ nguyên object path', () {
    activeEndpointUrl = 'https://db-new.example.com';
    expect(
      endpointStorageUrl(
        'https://old.supabase.co/storage/v1/object/public/covers/42.webp',
      ),
      'https://db-new.example.com/storage/v1/object/public/covers/42.webp',
    );
    expect(
      endpointStorageUrl('https://cdn.example.com/42.webp'),
      'https://cdn.example.com/42.webp',
    );
  });

  test('phiên đăng nhập được tách riêng theo host backend', () {
    expect(
      endpointAuthStorageKey('https://api.one.example.com'),
      isNot(endpointAuthStorageKey('https://api.two.example.com')),
    );
  });
}
