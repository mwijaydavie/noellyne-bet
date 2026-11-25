import '../models/daily_pick.dart';
import 'weekly_audit_pdf_service_stub.dart'
    if (dart.library.io) 'weekly_audit_pdf_service_io.dart' as impl;

/// Generates an institutional-grade, shareable Weekly / Filtered Verified
/// Performance Audit PDF directly on-device (works 100% offline on mobile).
class WeeklyAuditPdfService {
  const WeeklyAuditPdfService._();

  static Future<String> generateAndOpen({
    required List<DailyPick> ledgerPicks,
    required List<DailyPick> breakdownPool,
    required String reportTitle,
    required String scopeSubtitle,
  }) =>
      impl.generateAndOpenAuditPdf(
        ledgerPicks: ledgerPicks,
        breakdownPool: breakdownPool,
        reportTitle: reportTitle,
        scopeSubtitle: scopeSubtitle,
      );
}
