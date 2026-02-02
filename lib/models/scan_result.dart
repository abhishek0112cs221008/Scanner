class ScanResult {
  final String code;
  final DateTime timestamp;
  final bool isUrl;

  ScanResult({
    required this.code,
    required this.timestamp,
    required this.isUrl,
  });
}

List<ScanResult> scanHistory = [];
