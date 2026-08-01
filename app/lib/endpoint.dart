typedef Endpoint = ({String url, String anonKey});

String activeEndpointUrl = '';

Endpoint? endpointFromValues(
  Object? rawUrl,
  Object? rawKey, {
  Set<String>? allowedHosts,
}) {
  var url = rawUrl is String ? rawUrl.trim() : '';
  final anonKey = rawKey is String ? rawKey.trim() : '';
  if (url.endsWith('/')) url = url.substring(0, url.length - 1);
  final uri = Uri.tryParse(url);
  final local =
      uri != null &&
      {'localhost', '127.0.0.1', '::1', '10.0.2.2'}.contains(uri.host);
  if (anonKey.isEmpty ||
      uri == null ||
      uri.host.isEmpty ||
      (allowedHosts != null &&
          !allowedHosts.contains(uri.host.toLowerCase())) ||
      !(uri.scheme == 'https' || (uri.scheme == 'http' && local))) {
    return null;
  }
  return (url: url, anonKey: anonKey);
}

Set<String> endpointAllowedHosts(String builtInUrl, String extraHosts) {
  final hosts = extraHosts
      .split(',')
      .map((host) => host.trim().toLowerCase())
      .where((host) => host.isNotEmpty)
      .toSet();
  final builtInHost = Uri.tryParse(builtInUrl)?.host.toLowerCase();
  if (builtInHost != null && builtInHost.isNotEmpty) hosts.add(builtInHost);
  return hosts;
}

/// Nhận cả JSON cũ `{url, anonKey}` lẫn JSON chuyển đổi có active + fallbacks.
List<Endpoint> endpointConfigCandidates(
  Map<String, dynamic>? config, {
  required Set<String> allowedHosts,
}) {
  if (config == null) return const [];
  final fallbacks = config['fallbacks'];
  final raw = <Object?>[
    config.containsKey('active') ? config['active'] : config,
    // `is List` chứ không `as List?`: JSON gõ sai (fallbacks là chuỗi/object) chỉ bị
    // bỏ qua, KHÔNG ném lỗi làm treo app lúc khởi động — đây là file dùng để dọn nhà.
    if (fallbacks is List) ...fallbacks,
  ];
  final result = <Endpoint>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final ep = endpointFromValues(
      item['url'],
      item['anonKey'],
      allowedHosts: allowedHosts,
    );
    if (ep != null && !result.any((e) => e.url == ep.url)) {
      result.add(ep);
    }
  }
  return result;
}

String endpointAuthStorageKey(String url) {
  final authority = Uri.parse(
    url,
  ).authority.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
  return 'sb-$authority-auth-token';
}

/// Dump DB giữ URL Storage cũ; nếu đã mirror cùng object path thì đổi host lúc render.
String? endpointStorageUrl(String? url) {
  if (url == null || url.isEmpty || activeEndpointUrl.isEmpty) return url;
  const marker = '/storage/v1/object/';
  final markerAt = url.indexOf(marker);
  return markerAt < 0
      ? url
      : '${activeEndpointUrl.replaceAll(RegExp(r'/+$'), '')}${url.substring(markerAt)}';
}
