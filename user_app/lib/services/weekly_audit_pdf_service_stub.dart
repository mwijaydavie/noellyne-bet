import '../models/daily_pick.dart';

Future<String> generateAndOpenAuditPdf({
  required List<DailyPick> ledgerPicks,
  required List<DailyPick> breakdownPool,
  required String reportTitle,
  required String scopeSubtitle,
}) async {
  throw UnsupportedError('PDF export is available on the Android & iOS app.');
}
