String redactSensitiveText(String value) {
  var sanitized = value.trim();
  if (sanitized.isEmpty) {
    return sanitized;
  }

  final replacements = <Pattern, String>{
    RegExp(r'Bearer\s+[A-Za-z0-9\-._~+/]+=*', caseSensitive: false):
        '[redacted bearer]',
    RegExp(r'https?:\/\/\S+', caseSensitive: false): '[redacted url]',
    RegExp(r'\b[A-Za-z0-9_-]{24,}\b'): '[redacted secret]',
    RegExp(
        r'\b(?:transferToken|signature|nonce|ciphertext|authPublicKey|authPrivateKey)\b\s*[:=]\s*\S+',
        caseSensitive: false): '[redacted field]',
  };

  for (final entry in replacements.entries) {
    sanitized = sanitized.replaceAll(entry.key, entry.value);
  }

  return sanitized;
}

String summarizeSensitiveUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    return 'Short-lived local ticket';
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null) {
    return 'Short-lived local ticket';
  }

  final host = uri.host.isEmpty ? 'local endpoint' : uri.host;
  final lastSegment =
      uri.pathSegments.isEmpty ? 'ticket' : uri.pathSegments.last;
  final shortSegment = lastSegment.length <= 12
      ? lastSegment
      : '...${lastSegment.substring(lastSegment.length - 12)}';
  return '$host / $shortSegment';
}
