import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/daily_pick.dart';

const _ink = PdfColor.fromInt(0xFF1C1917);
const _muted = PdfColor.fromInt(0xFF57534E);
const _accent = PdfColor.fromInt(0xFFEA580C);
const _win = PdfColor.fromInt(0xFF15803D);
const _loss = PdfColor.fromInt(0xFFB91C1C);
const _surface = PdfColor.fromInt(0xFFFAF8F6);
const _border = PdfColor.fromInt(0xFFE7E5E4);

Future<String> generateAndOpenAuditPdf({
  required List<DailyPick> ledgerPicks,
  required List<DailyPick> breakdownPool,
  required String reportTitle,
  required String scopeSubtitle,
}) async {
  final bytes = await _buildDocumentBytes(
    ledgerPicks: ledgerPicks,
    breakdownPool: breakdownPool,
    reportTitle: reportTitle,
    scopeSubtitle: scopeSubtitle,
  );

  final dir = await getTemporaryDirectory();
  final now = DateTime.now();
  final stamp =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  final file = File('${dir.path}/Noellyne_Audit_$stamp.pdf');
  await file.writeAsBytes(bytes, flush: true);

  await OpenFilex.open(file.path, type: 'application/pdf');
  return file.path;
}

Future<Uint8List> _buildDocumentBytes({
  required List<DailyPick> ledgerPicks,
  required List<DailyPick> breakdownPool,
  required String reportTitle,
  required String scopeSubtitle,
}) async {
  final doc = pw.Document(
    title: _safe(reportTitle),
    author: "David Erick Mwijage & Clemence W. N'gunda - Altraware Technology Ltd",
    creator: 'Noellyne Sports Intelligence Engine',
  );

  final graded = ledgerPicks.where((p) => p.isWon || p.isLost).toList();
  final stats = _computeStats(graded);
  final nowLocal = DateTime.now();
  final genLabel =
      '${_shortDate(nowLocal)} ${nowLocal.hour.toString().padLeft(2, '0')}:${nowLocal.minute.toString().padLeft(2, '0')}';

  final tierRows = <(String, _AuditStats)>[
    ('Sure 2+ (>=80%)', _computeStats(breakdownPool.where((p) => p.isSure2).toList())),
    ('Strong Tier', _computeStats(breakdownPool.where((p) => p.isStrong).toList())),
    ('High Odds (>=1.85)', _computeStats(breakdownPool.where((p) => p.isHighOdds).toList())),
    ('Football', _computeStats(breakdownPool.where((p) => !p.isBasketball).toList())),
    ('NBA Basketball', _computeStats(breakdownPool.where((p) => p.isBasketball).toList())),
  ];

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(26, 26, 26, 30),
      footer: (ctx) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 10),
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _border, width: 0.7)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              "Altraware Technology Ltd (David Erick Mwijage & Clemence W. N'gunda) | 18+ Responsible Play",
              style: pw.TextStyle(fontSize: 7.5, color: _muted),
            ),
            pw.Text(
              'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                color: _muted,
              ),
            ),
          ],
        ),
      ),
      build: (ctx) => [
        pw.Container(
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            color: _ink,
            borderRadius: pw.BorderRadius.circular(10),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      children: [
                        pw.Container(
                          width: 8,
                          height: 18,
                          decoration: pw.BoxDecoration(
                            color: _accent,
                            borderRadius: pw.BorderRadius.circular(3),
                          ),
                        ),
                        pw.SizedBox(width: 8),
                        pw.Text(
                          'NOELLYNE  |  VERIFIED PERFORMANCE AUDIT',
                          style: pw.TextStyle(
                            fontSize: 13,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      _safe('$reportTitle  ·  $scopeSubtitle'),
                      style: const pw.TextStyle(
                        fontSize: 9.5,
                        color: PdfColor.fromInt(0xFFD6D3D1),
                      ),
                    ),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'ALTRAWARE TECHNOLOGY LTD',
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: _accent,
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    'Generated: $genLabel',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColor.fromInt(0xFFA8A29E),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 14),
        pw.Row(
          children: [
            _kpiBox(
              'WIN RATE',
              '${stats.winRate.toStringAsFixed(1)}%',
              '${stats.wins}W - ${stats.losses}L (${stats.total} graded)',
              stats.winRate >= 55 ? _win : _ink,
            ),
            pw.SizedBox(width: 8),
            _kpiBox(
              'NET UNITS',
              '${stats.netUnits >= 0 ? '+' : ''}${stats.netUnits.toStringAsFixed(2)}u',
              '${stats.stakedUnits.toStringAsFixed(1)}u staked',
              stats.netUnits >= 0 ? _win : _loss,
            ),
            pw.SizedBox(width: 8),
            _kpiBox(
              'VERIFIED ROI',
              '${stats.roiPct >= 0 ? '+' : ''}${stats.roiPct.toStringAsFixed(1)}%',
              'Automated grading',
              stats.roiPct >= 0 ? _win : _loss,
            ),
            pw.SizedBox(width: 8),
            _kpiBox(
              'EST. P&L (1u=1k)',
              '${stats.netTzs >= 0 ? '+' : '-'}TZS ${_fmtTzs(stats.netTzs.abs())}',
              'Net bankroll',
              stats.netTzs >= 0 ? _win : _loss,
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Text(
          'CATEGORY ACCOUNTABILITY MATRIX',
          style: pw.TextStyle(
            fontSize: 9.5,
            fontWeight: pw.FontWeight.bold,
            color: _ink,
            letterSpacing: 0.6,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: _border, width: 0.6),
          columnWidths: {
            0: const pw.FlexColumnWidth(2.4),
            1: const pw.FlexColumnWidth(0.9),
            2: const pw.FlexColumnWidth(1.1),
            3: const pw.FlexColumnWidth(1.1),
            4: const pw.FlexColumnWidth(1.1),
            5: const pw.FlexColumnWidth(1.0),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _ink),
              children: [
                _th('Category'),
                _th('Picks', alignRight: true),
                _th('W - L', alignRight: true),
                _th('Win Rate', alignRight: true),
                _th('Net Units', alignRight: true),
                _th('ROI', alignRight: true),
              ],
            ),
            for (var i = 0; i < tierRows.length; i++)
              pw.TableRow(
                decoration: pw.BoxDecoration(
                  color: i.isOdd ? _surface : PdfColors.white,
                ),
                children: [
                  _td(tierRows[i].$1, bold: true),
                  _td('${tierRows[i].$2.total}', alignRight: true),
                  _td('${tierRows[i].$2.wins}W-${tierRows[i].$2.losses}L', alignRight: true),
                  _td(
                    tierRows[i].$2.total == 0
                        ? '-'
                        : '${tierRows[i].$2.winRate.toStringAsFixed(1)}%',
                    alignRight: true,
                    bold: true,
                    color: tierRows[i].$2.winRate >= 60 ? _win : _ink,
                  ),
                  _td(
                    '${tierRows[i].$2.netUnits >= 0 ? '+' : ''}${tierRows[i].$2.netUnits.toStringAsFixed(2)}u',
                    alignRight: true,
                    bold: true,
                    color: tierRows[i].$2.netUnits >= 0 ? _win : _loss,
                  ),
                  _td(
                    '${tierRows[i].$2.roiPct >= 0 ? '+' : ''}${tierRows[i].$2.roiPct.toStringAsFixed(1)}%',
                    alignRight: true,
                    color: tierRows[i].$2.roiPct >= 0 ? _win : _loss,
                  ),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Text(
          'SETTLED MATCH LEDGER (${ledgerPicks.length} PICKS)',
          style: pw.TextStyle(
            fontSize: 9.5,
            fontWeight: pw.FontWeight.bold,
            color: _ink,
            letterSpacing: 0.6,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: _border, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(0.95),
            1: const pw.FlexColumnWidth(2.6),
            2: const pw.FlexColumnWidth(1.15),
            3: const pw.FlexColumnWidth(2.0),
            4: const pw.FlexColumnWidth(1.05),
            5: const pw.FlexColumnWidth(0.75),
            6: const pw.FlexColumnWidth(0.9),
          },
          children: [
            pw.TableRow(
              repeat: true,
              decoration: const pw.BoxDecoration(color: _ink),
              children: [
                _th('Date'),
                _th('Match & League'),
                _th('Tier'),
                _th('Pick @ Odds'),
                _th('Score'),
                _th('Result', alignRight: true),
                _th('Net', alignRight: true),
              ],
            ),
            for (var i = 0; i < ledgerPicks.length; i++)
              _ledgerRow(ledgerPicks[i], shaded: i.isOdd),
          ],
        ),
      ],
    ),
  );

  return doc.save();
}

pw.TableRow _ledgerRow(DailyPick p, {required bool shaded}) {
  final dt = (p.kickoffTime ?? p.settledAt)?.toLocal();
  final dateTxt = dt == null ? '-' : _shortDate(dt);
  final tierBadges = <String>[
    if (p.isSure2) 'SURE 2+',
    if (p.isStrong) 'STRONG',
    if (p.isHighOdds) 'HIGH ODDS',
    if (!p.isSure2 && !p.isStrong && !p.isHighOdds && p.tier.isNotEmpty)
      p.tier.toUpperCase(),
  ];
  final tierTxt = tierBadges.isEmpty
      ? '${p.confidence}%'
      : '${tierBadges.take(2).join(' / ')} (${p.confidence}%)';
  final compactScore = _compactScore(p.score);
  final won = p.isWon;

  return pw.TableRow(
    decoration: pw.BoxDecoration(color: shaded ? _surface : PdfColors.white),
    children: [
      _td(dateTxt, fontSize: 7.5),
      _td('${_safe(p.match)}\n${_safe(p.league)}', fontSize: 7.5, boldFirstLine: true),
      _td(_safe(tierTxt), fontSize: 7),
      _td('${_safe(p.pick)} @ ${p.odds.toStringAsFixed(2)}', fontSize: 7.5),
      _td(_safe(compactScore), fontSize: 7.5),
      _td(
        won ? 'WON' : (p.isLost ? 'LOST' : 'VOID'),
        alignRight: true,
        bold: true,
        fontSize: 7.5,
        color: won ? _win : (p.isLost ? _loss : _muted),
      ),
      _td(
        '${p.profitUnits >= 0 ? '+' : ''}${p.profitUnits.toStringAsFixed(2)}u',
        alignRight: true,
        bold: true,
        fontSize: 7.5,
        color: p.profitUnits >= 0 ? _win : _loss,
      ),
    ],
  );
}

pw.Widget _kpiBox(String label, String value, String sub, PdfColor valueColor) {
  return pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _surface,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _border, width: 0.7),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
              color: _muted,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            _safe(value),
            style: pw.TextStyle(
              fontSize: 12.5,
              fontWeight: pw.FontWeight.bold,
              color: valueColor,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            _safe(sub),
            style: const pw.TextStyle(fontSize: 7, color: _muted),
          ),
        ],
      ),
    ),
  );
}

pw.Widget _th(String text, {bool alignRight = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(
        text,
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: 7.5,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
      ),
    );

pw.Widget _td(
  String text, {
  bool alignRight = false,
  bool bold = false,
  bool boldFirstLine = false,
  double fontSize = 8,
  PdfColor color = _ink,
}) {
  if (boldFirstLine && text.contains('\n')) {
    final parts = text.split('\n');
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            parts.first,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
          pw.Text(
            parts.skip(1).join(' '),
            style: pw.TextStyle(fontSize: fontSize - 0.8, color: _muted),
          ),
        ],
      ),
    );
  }
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    child: pw.Text(
      text,
      textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
      style: pw.TextStyle(
        fontSize: fontSize,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: color,
      ),
    ),
  );
}

_AuditStats _computeStats(List<DailyPick> input) {
  final graded = input.where((p) => p.isWon || p.isLost).toList();
  final wins = graded.where((p) => p.isWon).length;
  final losses = graded.length - wins;
  final wr = graded.isEmpty ? 0.0 : (wins / graded.length) * 100;
  final net = graded.fold<double>(0, (a, p) => a + p.profitUnits);
  final staked = graded.fold<double>(
    0,
    (a, p) => a + (p.units > 0 ? p.units : 1.0),
  );
  final roi = staked > 0 ? (net / staked) * 100 : 0.0;
  return _AuditStats(
    total: graded.length,
    wins: wins,
    losses: losses,
    winRate: wr,
    netUnits: net,
    stakedUnits: staked,
    roiPct: roi,
    netTzs: (net * 1000).round(),
  );
}

String _compactScore(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return 'FT';
  final m = RegExp(r'(\d+\s*-\s*\d+)').firstMatch(s);
  if (m != null) return m.group(1)!.replaceAll(RegExp(r'\s+'), ' ');
  return s.length > 14 ? '${s.substring(0, 13)}...' : s;
}

String _shortDate(DateTime dt) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]}';
}

String _fmtTzs(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

String _safe(String input) {
  final replaced = input
      .replaceAll('—', '-')
      .replaceAll('–', '-')
      .replaceAll('•', '·')
      .replaceAll('’', "'")
      .replaceAll('‘', "'")
      .replaceAll('“', '"')
      .replaceAll('”', '"');
  final buf = StringBuffer();
  for (final rune in replaced.runes) {
    if (rune >= 0x20 && rune <= 0xFF) {
      buf.writeCharCode(rune);
    } else if (rune == 0x0A) {
      buf.write('\n');
    }
  }
  return buf.toString().trim();
}

class _AuditStats {
  const _AuditStats({
    required this.total,
    required this.wins,
    required this.losses,
    required this.winRate,
    required this.netUnits,
    required this.stakedUnits,
    required this.roiPct,
    required this.netTzs,
  });

  final int total;
  final int wins;
  final int losses;
  final double winRate;
  final double netUnits;
  final double stakedUnits;
  final double roiPct;
  final int netTzs;
}
