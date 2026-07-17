import 'package:flutter/material.dart';

class TutorialOverlay extends StatelessWidget {
  final Rect highlightRect;
  final String instructionText;
  final VoidCallback onTap;
  final bool requireTapInsideHole;

  const TutorialOverlay({
    super.key,
    required this.highlightRect,
    required this.instructionText,
    required this.onTap,
    this.requireTapInsideHole = false,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final bool showAbove = highlightRect.bottom > screenSize.height * 0.55;

    return GestureDetector(

      onTapDown: (details) {
        if (requireTapInsideHole) {
          if (highlightRect.inflate(15.0).contains(details.globalPosition)) {
            onTap();
          } else {
          }
        } else {
          onTap();
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          CustomPaint(
            size: Size.infinite,
            painter: _HolePainter(highlightRect),
          ),
          Positioned(
            top: showAbove ? null : highlightRect.bottom + 15,
            bottom: showAbove ? (screenSize.height - highlightRect.top) + 15 : null,
            left: 20,
            right: 20,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      instructionText,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          requireTapInsideHole
                              ? 'Tocca l\'area evidenziata'
                              : 'Tocca per continuare ',
                          style: const TextStyle(color: Colors.white70, fontSize: 13, fontStyle: FontStyle.italic),
                        ),
                        if (!requireTapInsideHole)
                          const Icon(Icons.arrow_forward, color: Colors.white70, size: 14),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HolePainter extends CustomPainter {
  final Rect holeRect;
  _HolePainter(this.holeRect);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawColor(Colors.black.withOpacity(0.80), BlendMode.srcOver);

    Paint clearPaint = Paint()
      ..blendMode = BlendMode.clear
      ..isAntiAlias = true;

    canvas.drawRRect(
      RRect.fromRectAndRadius(holeRect.inflate(6.0), const Radius.circular(12)),
      clearPaint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HolePainter oldDelegate) => true;
}