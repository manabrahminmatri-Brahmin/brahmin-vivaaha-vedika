import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

/// Builds dynamic watermark text lines for a protected profile photo.
class ProfilePhotoWatermarkLines {
  ProfilePhotoWatermarkLines._();

  static const String appName = 'MANA VIVAAHA VEDIKA';

  static List<String> build({
    required String viewerId,
    required String sessionToken,
    String? ownerId,
    DateTime? timestamp,
  }) {
    final ts = timestamp ?? DateTime.now();
    final formatted = DateFormat('d-MMM-yyyy hh:mm a').format(ts);
    final viewer = viewerId.trim().isEmpty ? 'UNKNOWN' : viewerId.trim();
    final token = sessionToken.trim().isEmpty ? '----' : sessionToken.trim();
    final lines = <String>[
      appName,
      'Viewer: $viewer',
      formatted,
      'Token: $token',
      'CONFIDENTIAL',
    ];
    if (ownerId != null && ownerId.trim().isNotEmpty) {
      lines.insert(2, 'Profile: ${ownerId.trim()}');
    }
    return lines;
  }
}

/// Tiled diagonal semi-transparent watermark across the full image.
class ProfilePhotoWatermarkPainter extends CustomPainter {
  ProfilePhotoWatermarkPainter({
    required this.lines,
    this.opacity = 0.28,
    this.rotationRadians = -0.52,
    this.tileSpacing = 140,
  });

  final List<String> lines;
  final double opacity;
  final double rotationRadians;
  final double tileSpacing;

  @override
  void paint(Canvas canvas, Size size) {
    if (lines.isEmpty || size.isEmpty) return;

    final textStyle = TextStyle(
      color: Colors.white.withValues(alpha: opacity.clamp(0.12, 0.45)),
      fontSize: 11,
      fontWeight: FontWeight.w700,
      height: 1.25,
      letterSpacing: 0.4,
    );

    final lineHeight = 14.0;
    final blockHeight = lines.length * lineHeight + 8;
    final blockWidth = lines
            .map((l) => _measureText(l, textStyle))
            .reduce((a, b) => a > b ? a : b) +
        16;

    final stepX = tileSpacing + blockWidth;
    final stepY = tileSpacing + blockHeight;

    canvas.save();
    for (var row = -2; row < (size.height / stepY).ceil() + 3; row++) {
      for (var col = -2; col < (size.width / stepX).ceil() + 3; col++) {
        final offsetX = col * stepX + (row.isOdd ? stepX * 0.45 : 0);
        final offsetY = row * stepY;
        canvas.save();
        canvas.translate(offsetX, offsetY);
        canvas.rotate(rotationRadians);
        _drawBlock(canvas, lines, textStyle, lineHeight);
        canvas.restore();
      }
    }
    canvas.restore();
  }

  static double _measureText(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }

  static void _drawBlock(
    Canvas canvas,
    List<String> lines,
    TextStyle style,
    double lineHeight,
  ) {
    for (var i = 0; i < lines.length; i++) {
      final painter = TextPainter(
        text: TextSpan(text: lines[i], style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(0, i * lineHeight));
    }
  }

  @override
  bool shouldRepaint(covariant ProfilePhotoWatermarkPainter oldDelegate) {
    return oldDelegate.lines != lines ||
        oldDelegate.opacity != opacity ||
        oldDelegate.rotationRadians != rotationRadians;
  }
}
