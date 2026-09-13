import 'dart:convert';

/// Controls what application context may leave the process. Filtering is
/// recursive, so tags in segments, markers and worst-frame evidence agree.
class TelemetryExportPolicy {
  /// Null allows all tag keys; an empty set removes every tag. Redaction may
  /// remove a value by returning null. Exports exceeding maxBytes fail closed.
  TelemetryExportPolicy(
      {Set<String>? allowedTags, this.redact, this.maxBytes = 262144})
      : allowedTags =
            allowedTags == null ? null : Set.unmodifiable(allowedTags) {
    if (maxBytes < 256) throw ArgumentError.value(maxBytes, 'maxBytes');
  }

  /// Keys explicitly permitted inside tag dictionaries.
  final Set<String>? allowedTags;

  /// Applies to every string value, including names and reproduction details.
  final String? Function(String path, String value)? redact;

  /// Maximum UTF-8 bytes; no silently truncated or invalid JSON is returned.
  final int maxBytes;

  /// Makes a filtered copy without changing the caller's original evidence.
  Object? filter(Object? value, [String path = r'$']) {
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          if (!(path.endsWith('.tags') &&
              allowedTags != null &&
              !allowedTags!.contains(entry.key.toString())))
            entry.key.toString(): filter(entry.value, '$path.${entry.key}')
      };
    }
    if (value is Iterable) {
      return [for (final item in value) filter(item, '$path[]')];
    }
    if (value is String && redact != null) return redact!(path, value);
    return value;
  }

  /// Valid JSON within the configured byte budget, or an explicit size error.
  String encode(Object? value) {
    final result = jsonEncode(filter(value));
    if (utf8.encode(result).length > maxBytes) {
      throw StateError('Telemetry export exceeds $maxBytes bytes');
    }
    return result;
  }
}
