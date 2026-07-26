import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'receipt_printer.dart';

class ThermalReceiptPreview extends StatelessWidget {
  const ThermalReceiptPreview({
    super.key,
    required this.receipt,
    this.maxWidth = 320,
    this.fontSize = 10,
    this.compact = false,
    this.fitToContent = true,
    this.fillAvailableWidth = false,
    this.usePrintLayout = false,
  });

  final ReceiptData receipt;
  final double maxWidth;
  final double fontSize;
  final bool compact;
  final bool fitToContent;
  /// Scale text to use the full width offered by the parent.
  final bool fillAvailableWidth;
  /// When false, uses the same centered preview layout as the web admin.
  final bool usePrintLayout;

  @override
  Widget build(BuildContext context) {
    if (fillAvailableWidth) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          if (!availableWidth.isFinite || availableWidth <= 0) {
            return _buildReceipt(fontSize);
          }

          final horizontalPad = compact ? 8.0 : 10.0;
          final basePaperWidth = _thermalPaperWidth(_monoStyle(fontSize));
          final baseContentWidth = basePaperWidth + (horizontalPad * 2);
          final scale = (availableWidth / baseContentWidth).clamp(1.0, 4.0);

          return Align(
            alignment: Alignment.topCenter,
            child: _buildReceipt(
              fontSize * scale,
              containerWidth: availableWidth,
            ),
          );
        },
      );
    }

    if (fitToContent) {
      return Center(
        child: IntrinsicWidth(child: _buildReceipt(fontSize)),
      );
    }

    return Center(child: _buildReceipt(fontSize));
  }

  Widget _buildReceipt(
    double effectiveFontSize, {
    double? containerWidth,
  }) {
    final layout = ThermalReceiptLayout(receipt);
    final lines = (usePrintLayout ? layout.buildLines() : layout.buildPreviewLines())
        .where((line) => line.trim().isNotEmpty);
    final store = receipt.store;
    final mono = _monoStyle(effectiveFontSize);
    final boldMono = mono.copyWith(fontWeight: FontWeight.w800);
    final paperWidth = fitToContent ? _thermalPaperWidth(mono) : maxWidth;
    final horizontalPad = compact ? 8.0 : 10.0;
    final verticalPad = compact ? 6.0 : 8.0;
    final resolvedWidth = containerWidth ??
        (fitToContent ? paperWidth + (horizontalPad * 2) : null);

    return Container(
      width: resolvedWidth,
      constraints: resolvedWidth == null
          ? BoxConstraints(maxWidth: maxWidth)
          : null,
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPad,
        vertical: verticalPad,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_hasLogoImage(store.logoImagePath))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(
                    File(store.logoImagePath!),
                    width: paperWidth,
                    height: compact ? 36 : 44,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          for (final line in lines)
            _ReceiptLineText(
              line: line,
              style: _lineStyle(line, receipt, mono, boldMono),
              center: !usePrintLayout,
            ),
        ],
      ),
    );
  }

  TextStyle _monoStyle(double size) {
    return TextStyle(
      fontFamily: 'monospace',
      fontSize: size,
      height: compact ? 1.12 : 1.18,
      color: Colors.black87,
    );
  }

  static double _thermalPaperWidth(TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(
        text: List.filled(kThermalWidth, '0').join(),
        style: style,
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  static bool _hasLogoImage(String? path) {
    if (kIsWeb || path == null || path.isEmpty) return false;
    return File(path).existsSync();
  }

  static TextStyle _lineStyle(
    String line,
    ReceiptData receipt,
    TextStyle mono,
    TextStyle boldMono,
  ) {
    final trimmed = line.trim();
    if (trimmed == receipt.store.storeName ||
        trimmed == 'INVOICE' ||
        trimmed.startsWith('TOTAL') ||
        trimmed == kReceiptFooterThanks) {
      return boldMono;
    }
    return mono;
  }
}

class _ReceiptLineText extends StatelessWidget {
  const _ReceiptLineText({
    required this.line,
    required this.style,
    this.center = false,
  });

  final String line;
  final TextStyle style;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      line.trim(),
      style: style,
      softWrap: false,
      maxLines: 1,
      overflow: TextOverflow.clip,
      textAlign: center ? TextAlign.center : TextAlign.left,
    );

    if (!center) return text;

    return SizedBox(width: double.infinity, child: text);
  }
}
