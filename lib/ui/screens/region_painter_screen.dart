import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/services.dart';
import '../../models/body_region.dart';
import '../widgets/tutorial_overlay.dart';

class RegionPainterScreen extends StatefulWidget {
  final BodyRegion region;
  final String imagePath;
  final String regionName;

  const RegionPainterScreen({
    super.key,
    required this.region,
    required this.imagePath,
    required this.regionName,
  });

  @override
  State<RegionPainterScreen> createState() => _RegionPainterScreenState();
}

class _RegionPainterScreenState extends State<RegionPainterScreen> {
  final GlobalKey _canvasKey = GlobalKey();

  final GlobalKey _toolbarKey = GlobalKey();
  bool _showTutorial = false;
  Rect? _tutorialTargetRect;

  bool _isLoading = true;
  ui.Image? _maskImage;
  ByteData? _imageBytes;
  int _totalAnatomyPixels = 0;

  List<DrawingPoint?> points = [];
  double strokeWidth = 25.0;
  bool _isEraserMode = false;

  @override
  void initState() {
    super.initState();
    _loadAndAnalyzeImage();
    _checkFirstLaunchPainter();
  }

  Future<void> _checkFirstLaunchPainter() async {
    final prefs = await SharedPreferences.getInstance();

    bool isFirstTime = true; // lasciare true per testare il tutorial : bool isFirstTime = prefs.getBool('isFirstLaunchPainter') ?? true;


    if (isFirstTime) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          final RenderBox? toolbarBox = _toolbarKey.currentContext?.findRenderObject() as RenderBox?;
          if (toolbarBox != null) {
            setState(() {
              _tutorialTargetRect = toolbarBox.localToGlobal(Offset.zero) & toolbarBox.size;
              _showTutorial = true;
            });
          }
        }
      });
    }
  }
  void _closeTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isFirstLaunchPainter', false);
    setState(() => _showTutorial = false);
  }

  Future<void> _loadAndAnalyzeImage() async {
    try {
      final ByteData data = await rootBundle.load(widget.imagePath);
      final Uint8List list = data.buffer.asUint8List();
      final ui.Codec codec = await ui.instantiateImageCodec(list);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image img = frameInfo.image;

      final ByteData? imgBytes = await img.toByteData(format: ui.ImageByteFormat.rawRgba);

      int opaqueCount = 0;
      if (imgBytes != null) {
        for (int i = 3; i < imgBytes.lengthInBytes; i += 4) {
          if (imgBytes.getUint8(i) > 10) opaqueCount++;
        }
      }

      setState(() {
        _maskImage = img;
        _imageBytes = imgBytes;
        _totalAnatomyPixels = opaqueCount;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _clearCanvas() => setState(() => points.clear());

  void _calculateAndReturn() {
    if (points.isEmpty || _maskImage == null || _imageBytes == null || _totalAnatomyPixels == 0) {
      Navigator.pop(context, 0.0);
      return;
    }

    RenderBox? renderBox = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    double screenW = renderBox.size.width;
    double screenH = renderBox.size.height;
    double imgW = _maskImage!.width.toDouble();
    double imgH = _maskImage!.height.toDouble();

    double scale = min(screenW / imgW, screenH / imgH);
    double drawW = imgW * scale;
    double drawH = imgH * scale;
    double dx = (screenW - drawW) / 2;
    double dy = (screenH - drawH) / 2;

    double cellSize = 3.0;
    Set<String> coloredScreenCells = {};

    for (int i = 0; i < points.length; i++) {
      var p = points[i];
      if (p != null) {
        double radius = p.strokeWidth / 2;
        DrawingPoint? prevP = (i > 0) ? points[i - 1] : null;

        if (prevP != null && prevP.isEraser == p.isEraser) {
          double dist = sqrt(pow(p.offset.dx - prevP.offset.dx, 2) + pow(p.offset.dy - prevP.offset.dy, 2));
          int steps = max((dist / radius).ceil(), 1);
          for (int s = 0; s <= steps; s++) {
            double t = s / steps;
            double lerpX = prevP.offset.dx + (p.offset.dx - prevP.offset.dx) * t;
            double lerpY = prevP.offset.dy + (p.offset.dy - prevP.offset.dy) * t;
            _markCells(lerpX, lerpY, radius, cellSize, coloredScreenCells, screenW, screenH, p.isEraser);
          }
        } else {
          _markCells(p.offset.dx, p.offset.dy, radius, cellSize, coloredScreenCells, screenW, screenH, p.isEraser);
        }
      }
    }

    int validPaintedCells = 0;
    for (String cell in coloredScreenCells) {
      List<String> parts = cell.split('_');
      double cx = int.parse(parts[0]) * cellSize + (cellSize / 2);
      double cy = int.parse(parts[1]) * cellSize + (cellSize / 2);

      double ix = (cx - dx) / scale;
      double iy = (cy - dy) / scale;

      if (ix >= 0 && ix < imgW && iy >= 0 && iy < imgH) {
        int pixelX = ix.floor();
        int pixelY = iy.floor();
        int byteIndex = (pixelY * _maskImage!.width + pixelX) * 4;

        if (_imageBytes!.getUint8(byteIndex + 3) > 10) validPaintedCells++;
      }
    }

    double screenAnatomyArea = _totalAnatomyPixels * (scale * scale);
    double paintedValidArea = validPaintedCells * (cellSize * cellSize);

    double estimatedCoverage = (paintedValidArea / screenAnatomyArea) * 100;
    if (estimatedCoverage > 100) estimatedCoverage = 100.0;

    Navigator.pop(context, estimatedCoverage);
  }

  void _markCells(double cx, double cy, double radius, double cellSize, Set<String> cells, double maxW, double maxH, bool isEraser) {
    int minX = ((cx - radius) / cellSize).floor();
    int maxX = ((cx + radius) / cellSize).ceil();
    int minY = ((cy - radius) / cellSize).floor();
    int maxY = ((cy + radius) / cellSize).ceil();

    for (int x = minX; x <= maxX; x++) {
      for (int y = minY; y <= maxY; y++) {
        double cellX = x * cellSize;
        double cellY = y * cellSize;
        if (cellX < 0 || cellX > maxW || cellY < 0 || cellY > maxH) continue;

        if (pow(cellX - cx, 2) + pow(cellY - cy, 2) <= radius * radius) {
          if (isEraser) {
            cells.remove('${x}_${y}');
          } else {
            cells.add('${x}_${y}');
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: Text(widget.regionName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            backgroundColor: Theme.of(context).colorScheme.primary,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: _clearCanvas,
                tooltip: 'Svuota tutto',
              ),
            ],
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : Column(
            children: [
              Container(
                key: _toolbarKey,
                color: Colors.grey[900],
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.brush, color: !_isEraserMode ? Colors.redAccent : Colors.grey),
                      onPressed: () => setState(() => _isEraserMode = false),
                    ),
                    IconButton(
                      icon: Icon(Icons.cleaning_services, color: _isEraserMode ? Colors.white : Colors.grey),
                      onPressed: () => setState(() => _isEraserMode = true),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Slider(
                        value: strokeWidth,
                        min: 10.0,
                        max: 80.0,
                        activeColor: _isEraserMode ? Colors.white : Theme.of(context).colorScheme.primary,
                        inactiveColor: Colors.grey[700],
                        onChanged: (val) {
                          setState(() => strokeWidth = val);
                        },
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: Center(
                  child: Stack(
                    key: _canvasKey,
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          onPanStart: (details) => _addPoint(details.localPosition),
                          onPanUpdate: (details) => _addPoint(details.localPosition),
                          onPanEnd: (details) {
                            setState(() {
                              points.add(null);
                            });
                          },
                          child: CustomPaint(
                            painter: MaskedSketcher(
                              points: points,
                              maskImage: _maskImage,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              Container(
                color: Colors.black,
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle_outline, color: Colors.white),
                    label: const Text('SALVA AREA COLORATA', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _calculateAndReturn,
                  ),
                ),
              ),
            ],
          ),
        ),

        if (_showTutorial && _tutorialTargetRect != null)
          TutorialOverlay(
            highlightRect: _tutorialTargetRect!,
            instructionText: 'Usa questi strumenti! Il pennello per colorare, la gomma per cancellare eventuali sbavature sulla pelle, e lo slider per regolare lo spessore del tratto.',
            onTap: _closeTutorial,
          ),
      ],
    );
  }

  void _addPoint(Offset localPosition) {
    if (localPosition.dx < 0 || localPosition.dy < 0) return;
    setState(() {
      points.add(DrawingPoint(
        offset: localPosition,
        strokeWidth: strokeWidth,
        isEraser: _isEraserMode,
      ));
    });
  }
}

class DrawingPoint {
  final Offset offset;
  final double strokeWidth;
  final bool isEraser;
  DrawingPoint({required this.offset, required this.strokeWidth, this.isEraser = false});
}

class MaskedSketcher extends CustomPainter {
  final List<DrawingPoint?> points;
  final ui.Image? maskImage;

  MaskedSketcher({required this.points, required this.maskImage});

  @override
  void paint(Canvas canvas, Size size) {
    if (maskImage == null) return;
    Rect rect = Offset.zero & size;

    canvas.saveLayer(rect, Paint());
    paintImage(
      canvas: canvas,
      rect: rect,
      image: maskImage!,
      fit: BoxFit.contain,
    );

    canvas.saveLayer(rect, Paint()..blendMode = BlendMode.srcATop);

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        Paint p = Paint()
          ..color = points[i]!.isEraser ? Colors.transparent : Colors.red.withOpacity(0.75)
          ..strokeWidth = points[i]!.strokeWidth
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true
          ..blendMode = points[i]!.isEraser ? BlendMode.clear : BlendMode.srcOver;

        canvas.drawLine(points[i]!.offset, points[i + 1]!.offset, p);
      } else if (points[i] != null && points[i + 1] == null) {
        Paint p = Paint()
          ..color = points[i]!.isEraser ? Colors.transparent : Colors.red.withOpacity(0.75)
          ..strokeWidth = points[i]!.strokeWidth
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true
          ..blendMode = points[i]!.isEraser ? BlendMode.clear : BlendMode.srcOver;

        canvas.drawPoints(ui.PointMode.points, [points[i]!.offset], p);
      }
    }

    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant MaskedSketcher oldDelegate) => true;
}