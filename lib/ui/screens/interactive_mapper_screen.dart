import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../models/body_region.dart';
import '../../utils/bsa_calculator.dart';
import 'region_painter_screen.dart';
import 'map_widget.dart';
import '../widgets/tutorial_overlay.dart';

class InteractiveMapperScreen extends StatefulWidget {
  const InteractiveMapperScreen({super.key});

  @override
  State<InteractiveMapperScreen> createState() => _InteractiveMapperScreenState();
}

class _InteractiveMapperScreenState extends State<InteractiveMapperScreen> {
  static bool _hasShownMainTutorial = false;

  bool _isFrontView = true;
  String _selectedDisease = 'Dermatite Atopica';

  final Map<String, Map<BodyRegion, double>> _diseaseCoverages = {
    'Psoriasi': {},
    'Dermatite Atopica': {},
  };
  final Map<String, Map<BodyRegion, List<DrawingPoint?>>> _diseasePoints = {
    'Psoriasi': {},
    'Dermatite Atopica': {},
  };

  // Metadati di rendering per ogni regione (dimensioni SVG e canvas)
  final Map<String, Map<BodyRegion, Map<String, dynamic>>> _regionRenderInfo = {
    'Psoriasi': {},
    'Dermatite Atopica': {},
  };

  // Coordinate hitbox per le viste anteriore e posteriore (frazioni 0-1)
  // Usate per il rendering delle immagini nel PDF
  static const Map<BodyRegion, ({double left, double top, double width, double height})> _frontCoords = {
    BodyRegion.headFront: (left: 0.40, top: 0.03, width: 0.19, height: 0.12),
    BodyRegion.neckFront: (left: 0.43, top: 0.14, width: 0.14, height: 0.04),
    BodyRegion.chest: (left: 0.33, top: 0.18, width: 0.33, height: 0.16),
    BodyRegion.abdomen: (left: 0.35, top: 0.34, width: 0.30, height: 0.11),
    BodyRegion.genitals: (left: 0.42, top: 0.44, width: 0.15, height: 0.06),
    BodyRegion.upperArmLeftFront: (left: 0.65, top: 0.19, width: 0.11, height: 0.15),
    BodyRegion.forearmLeftFront: (left: 0.70, top: 0.34, width: 0.12, height: 0.14),
    BodyRegion.handLeftFront: (left: 0.79, top: 0.47, width: 0.13, height: 0.08),
    BodyRegion.upperArmRightFront: (left: 0.23, top: 0.19, width: 0.11, height: 0.15),
    BodyRegion.forearmRightFront: (left: 0.15, top: 0.34, width: 0.12, height: 0.14),
    BodyRegion.handRightFront: (left: 0.07, top: 0.47, width: 0.13, height: 0.08),
    BodyRegion.thighLeftFront: (left: 0.51, top: 0.47, width: 0.18, height: 0.20),
    BodyRegion.lowerLegLeftFront: (left: 0.53, top: 0.67, width: 0.12, height: 0.16),
    BodyRegion.footLeftFront: (left: 0.54, top: 0.83, width: 0.12, height: 0.10),
    BodyRegion.thighRightFront: (left: 0.30, top: 0.47, width: 0.18, height: 0.20),
    BodyRegion.lowerLegRightFront: (left: 0.34, top: 0.67, width: 0.12, height: 0.16),
    BodyRegion.footRightFront: (left: 0.34, top: 0.83, width: 0.12, height: 0.10),
  };

  static const Map<BodyRegion, ({double left, double top, double width, double height})> _backCoords = {
    BodyRegion.headBack: (left: 0.40, top: 0.04, width: 0.20, height: 0.10),
    BodyRegion.neckBack: (left: 0.43, top: 0.14, width: 0.14, height: 0.03),
    BodyRegion.upperBack: (left: 0.35, top: 0.17, width: 0.30, height: 0.17),
    BodyRegion.lowerBack: (left: 0.35, top: 0.35, width: 0.31, height: 0.07),
    BodyRegion.buttockRight: (left: 0.32, top: 0.43, width: 0.18, height: 0.09),
    BodyRegion.buttockLeft: (left: 0.52, top: 0.43, width: 0.18, height: 0.09),
    BodyRegion.upperArmLeftBack: (left: 0.23, top: 0.20, width: 0.11, height: 0.15),
    BodyRegion.forearmLeftBack: (left: 0.13, top: 0.35, width: 0.15, height: 0.13),
    BodyRegion.handLeftBack: (left: 0.07, top: 0.48, width: 0.12, height: 0.08),
    BodyRegion.upperArmRightBack: (left: 0.67, top: 0.20, width: 0.11, height: 0.15),
    BodyRegion.forearmRightBack: (left: 0.73, top: 0.35, width: 0.15, height: 0.13),
    BodyRegion.handRightBack: (left: 0.83, top: 0.48, width: 0.12, height: 0.08),
    BodyRegion.thighLeftBack: (left: 0.32, top: 0.52, width: 0.17, height: 0.17),
    BodyRegion.lowerLegLeftBack: (left: 0.35, top: 0.69, width: 0.13, height: 0.17),
    BodyRegion.footLeftBack: (left: 0.35, top: 0.86, width: 0.12, height: 0.10),
    BodyRegion.thighRightBack: (left: 0.53, top: 0.52, width: 0.17, height: 0.17),
    BodyRegion.lowerLegRightBack: (left: 0.54, top: 0.69, width: 0.13, height: 0.17),
    BodyRegion.footRightBack: (left: 0.54, top: 0.86, width: 0.12, height: 0.10),
  };

  // Correzione empirica per allineare le sagome SVG nel PDF.
  // I valori sono in pixel canvas (2x) e compensano il disallineamento
  // tra le coordinate hitbox (usate per il tap) e la posizione reale
  // delle sagome SVG sul corpo.
  static const double _svgCorrectionX = 2.0;  // sposta dx (verso destra)
  static const double _svgCorrectionY = -6.0; // sposta dy (verso l'alto)

  // CHIAVI DI TRACCIAMENTO PER IL TUTORIAL A SCELTA MULTIPLA
  final GlobalKey _totalBsaKey = GlobalKey();
  final GlobalKey _selectorKey = GlobalKey();
  final GlobalKey _headKey = GlobalKey();

  int _tutorialStep = 0;
  final Map<int, Rect> _tutorialRects = {};

  @override
  void initState() {
    super.initState();
    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    if (_hasShownMainTutorial) return;

    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        _calculateAllTutorialCoordinates();
      }
    });
  }

  void _calculateAllTutorialCoordinates() {
    final RenderBox? bsaBox = _totalBsaKey.currentContext?.findRenderObject() as RenderBox?;
    final RenderBox? selectorBox = _selectorKey.currentContext?.findRenderObject() as RenderBox?;
    final RenderBox? headBox = _headKey.currentContext?.findRenderObject() as RenderBox?;

    setState(() {
      if (selectorBox != null) {
        _tutorialRects[1] = selectorBox.localToGlobal(Offset.zero) & selectorBox.size;
      }
      if (headBox != null) {
        _tutorialRects[2] = headBox.localToGlobal(Offset.zero) & headBox.size;
      }
      if (bsaBox != null) {
        _tutorialRects[3] = bsaBox.localToGlobal(Offset.zero) & bsaBox.size;
      }

      _tutorialStep = 1;
    });
  }

  void _handleTutorialTap() async {
    if (_tutorialStep == 1) {
      setState(() => _tutorialStep = 2);
    }
    else if (_tutorialStep == 2) {
      setState(() => _tutorialStep = 0);

      await _showCoverageSlider(BodyRegion.headFront);

      setState(() {
        _tutorialStep = 3;
      });
    }
    else if (_tutorialStep == 3) {
      _hasShownMainTutorial = true;
      setState(() => _tutorialStep = 0);
    }
  }

  void _skipTutorial() {
    setState(() {
      _hasShownMainTutorial = true;
      _tutorialStep = 0;
    });
  }

  String _getTutorialText(int step) {
    switch (step) {
      case 1:
        return 'Usa questo selettore per passare dalla vista anteriore a quella posteriore.';
      case 2:
        return 'COME SELEZIONARE: Tocca esattamente la testa (l\'area evidenziata) per aprire la schermata di colorazione!';
      case 3:
        return 'IL CALCOLO: Qui vedrai la BSA Totale aggiornarsi in tempo reale. Tocca le altre parti del corpo per completare la mappatura!';
      default:
        return '';
    }
  }

  double get _totalBsa {
    double total = 0.0;
    final currentCoverages = _diseaseCoverages[_selectedDisease] ?? {};
    currentCoverages.forEach((region, coveragePercent) {
      if (coveragePercent > 0) {
        double maxRegionBsa = BsaCalculator.getRegionPercentage(region);
        total += (coveragePercent / 100.0) * maxRegionBsa;
      }
    });
    return total;
  }

  void _resetAll() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conferma Reset'),
        content: Text('Stai per cancellare tutte le parti colorate di $_selectedDisease, sei sicuro di procedere?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _diseaseCoverages[_selectedDisease]?.clear();
                _diseasePoints[_selectedDisease]?.clear();
              });
              Navigator.pop(context);
            },
            child: const Text('Resetta', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showDetails() {
    final currentCoverages = _diseaseCoverages[_selectedDisease] ?? {};
    final breakdown = BsaCalculator.calculateBreakdown(currentCoverages);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Dettagli BSA per $_selectedDisease'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...breakdown.entries.map((e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(e.key),
                  Text('${e.value.toStringAsFixed(2)} %', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            )),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('BSA Totale', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('${_totalBsa.toStringAsFixed(2)} %', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Il BSA rappresenta esclusivamente la percentuale stimata di superficie corporea interessata e non sostituisce una valutazione dermatologica.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Chiudi')),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'export') _handlePdfAction(false);
              if (value == 'share') _handlePdfAction(true);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.picture_as_pdf, size: 20),
                    SizedBox(width: 8),
                    Text('Esporta PDF (Salva/Stampa)'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.share, size: 20),
                    SizedBox(width: 8),
                    Text('Condividi PDF'),
                  ],
                ),
              ),
            ],
            child: ElevatedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Opzioni PDF'),
              style: ElevatedButton.styleFrom(
                disabledBackgroundColor: Theme.of(context).colorScheme.primary,
                disabledForegroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Rendering del corpo (fronte o retro) con sagome SVG colorate
  /// in immagine PNG.
  Future<Uint8List?> _renderBodyPreviewForPdf(bool isFrontView) async {
    try {
      // Caricamento immagine corpo
      final bodyAsset = isFrontView ? 'assets/images/body_front.png' : 'assets/images/body_back.png';
      final bodyBytes = (await rootBundle.load(bodyAsset)).buffer.asUint8List();
      final codec = await ui.instantiateImageCodec(bodyBytes);
      final frameInfo = await codec.getNextFrame();
      final ui.Image bodyImage = frameInfo.image;
      codec.dispose();

      final double bodyW = bodyImage.width.toDouble();
      final double bodyH = bodyImage.height.toDouble();

      // Rendering
      const double scaleFactor = 2.0;
      final int canvasW = (bodyW * scaleFactor).round();
      final int canvasH = (bodyH * scaleFactor).round();

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, canvasW.toDouble(), canvasH.toDouble()));

      // Disegno corpo e sagome colorate
      final paintHi = Paint()..filterQuality = FilterQuality.high;
      final Offset appOffset = isFrontView
          ? const Offset(-10, -17)
          : const Offset(6, -13);
      const double appScale = 1.08;

      canvas.save();
      canvas.translate(canvasW / 2.0, canvasH / 2.0);
      canvas.scale(appScale);
      canvas.translate(-canvasW / 2.0, -canvasH / 2.0);
      canvas.translate(appOffset.dx * scaleFactor, appOffset.dy * scaleFactor);
      canvas.drawImageRect(
        bodyImage,
        Rect.fromLTWH(0, 0, bodyW, bodyH),
        Rect.fromLTWH(0, 0, canvasW.toDouble(), canvasH.toDouble()),
        paintHi,
      );
      canvas.restore();

      // Singole sagome SVG
      final coords = isFrontView ? _frontCoords : _backCoords;
      final Color diseaseColor = _getDiseaseColor(_selectedDisease);

      for (final entry in coords.entries) {
        final region = entry.key;
        final coverage = _diseaseCoverages[_selectedDisease]?[region] ?? 0.0;
        if (coverage <= 0.0) continue;

        final coord = entry.value;
        final double hitboxLeft = canvasW * coord.left;
        final double hitboxTop = canvasH * coord.top;
        final double hitboxW = canvasW * coord.width;
        final double hitboxH = canvasH * coord.height;

        String svgPath = _getRegionOverlayPath(region);
        svgPath = svgPath.replaceFirst('assets/images/', 'assets/svg/');
        svgPath = svgPath.replaceAll('.png', '.svg');

        final pictureInfo = await vg.loadPicture(SvgAssetLoader(svgPath), null);
        final double svgNativeW = pictureInfo.size.width;
        final double svgNativeH = pictureInfo.size.height;

        final double scale = math.min(hitboxW / svgNativeW, hitboxH / svgNativeH);
        final double drawW = svgNativeW * scale;
        final double drawH = svgNativeH * scale;
        final double drawLeft = hitboxLeft + (hitboxW - drawW) / 2;
        final double drawTop = hitboxTop + (hitboxH - drawH) / 2;

        canvas.save();
        canvas.translate(drawLeft + _svgCorrectionX, drawTop + _svgCorrectionY);
        canvas.scale(scale);

        canvas.drawPicture(pictureInfo.picture);

        final double opacity = (coverage / 100.0) * 0.8;
        canvas.saveLayer(
          Rect.fromLTWH(0, 0, svgNativeW, svgNativeH),
          Paint()..blendMode = BlendMode.srcATop,
        );
        canvas.drawRect(
          Rect.fromLTWH(0, 0, svgNativeW, svgNativeH),
          Paint()..color = diseaseColor.withValues(alpha: opacity),
        );
        canvas.restore();

        //TODO: Disegna anche i tratti dell'utente se presenti
        final points = _diseasePoints[_selectedDisease]?[region] ?? [];
        final renderInfo = _regionRenderInfo[_selectedDisease]?[region];
        if (points.isNotEmpty && renderInfo != null) {
          final double svgImgW = (renderInfo['svgWidth'] as num).toDouble();
          final double svgImgH = (renderInfo['svgHeight'] as num).toDouble();
          final double canvasW2 = (renderInfo['canvasWidth'] as num).toDouble();
          final double canvasH2 = (renderInfo['canvasHeight'] as num).toDouble();

          if (svgImgW > 0 && svgImgH > 0 && canvasW2 > 0 && canvasH2 > 0) {
            final double fitScale = math.min(canvasW2 / svgImgW, canvasH2 / svgImgH);
            final double dx = (canvasW2 - svgImgW * fitScale) / 2;
            final double dy = (canvasH2 - svgImgH * fitScale) / 2;

            canvas.saveLayer(
              Rect.fromLTWH(0, 0, svgNativeW, svgNativeH),
              Paint()..blendMode = BlendMode.srcATop,
            );

            final Color strokeColor = diseaseColor;
            for (int i = 0; i < points.length - 1; i++) {
              final p = points[i];
              final nextP = points[i + 1];
              if (p != null && nextP != null) {
                final double x1 = (p.offset.dx - dx) / fitScale;
                final double y1 = (p.offset.dy - dy) / fitScale;
                final double x2 = (nextP.offset.dx - dx) / fitScale;
                final double y2 = (nextP.offset.dy - dy) / fitScale;

                final Paint strokePaint = Paint()
                  ..color = p.isEraser ? const Color(0x00000000) : strokeColor.withValues(alpha: 0.75)
                  ..strokeWidth = p.strokeWidth / fitScale
                  ..strokeCap = StrokeCap.round
                  ..isAntiAlias = true
                  ..style = PaintingStyle.stroke;
                if (p.isEraser) strokePaint.blendMode = BlendMode.clear;

                canvas.drawLine(Offset(x1, y1), Offset(x2, y2), strokePaint);
              } else if (p != null) {
                final double x1 = (p.offset.dx - dx) / fitScale;
                final double y1 = (p.offset.dy - dy) / fitScale;

                final Paint strokePaint = Paint()
                  ..color = p.isEraser ? const Color(0x00000000) : strokeColor.withValues(alpha: 0.75)
                  ..strokeWidth = p.strokeWidth / fitScale
                  ..strokeCap = StrokeCap.round
                  ..isAntiAlias = true
                  ..style = PaintingStyle.stroke;
                if (p.isEraser) strokePaint.blendMode = BlendMode.clear;

                canvas.drawPoints(ui.PointMode.points, [Offset(x1, y1)], strokePaint);
              }
            }
            canvas.restore();
          }
        }

        canvas.restore();
        pictureInfo.picture.dispose();
      }

      // Generazione immagine finale
      final ui.Image resultImage = await recorder.endRecording().toImage(canvasW, canvasH);
      bodyImage.dispose();
      final byteData = await resultImage.toByteData(format: ui.ImageByteFormat.png);
      resultImage.dispose();
      debugPrint('PDF: rendered body view (${byteData!.lengthInBytes} bytes)');
      return byteData.buffer.asUint8List();
    } catch (e, stack) {
      debugPrint('PDF: ERRORE rendering corpo: $e\\n$stack');
      return null;
    }
  }

  Future<pw.Document> _buildPdfReport() async {
    final pdf = pw.Document();
    final currentCoverages = _diseaseCoverages[_selectedDisease] ?? {};
    final breakdown = BsaCalculator.calculateBreakdown(currentCoverages);

    // Rendering immagini composite (corpo con sagome SVG colorate)
    final frontRendered = await _renderBodyPreviewForPdf(true);
    final backRendered = await _renderBodyPreviewForPdf(false);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(48),
        build: (pw.Context context) => [
          pw.Header(level: 0, child: pw.Text('Report Valutazione BSA - $_selectedDisease')),
          pw.SizedBox(height: 16),
          pw.Text('Data: ${DateTime.now().toString().split('.')[0]}'),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: ['Regione', 'BSA (%)'],
            data: breakdown.entries.map((e) => [e.key, '${e.value.toStringAsFixed(2)} %']).toList(),
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('BSA Totale Stimata:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
              pw.Text('${_totalBsa.toStringAsFixed(2)} %', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
            ],
          ),
          // Immagini composite del corpo con sagome colorate
          if (frontRendered != null || backRendered != null) ...[
            pw.SizedBox(height: 16),
            pw.Divider(),
            pw.Header(level: 1, child: pw.Text('Rappresentazione visiva')),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (frontRendered != null)
                  pw.Column(
                    mainAxisSize: pw.MainAxisSize.min,
                    children: [
                      pw.Text('Vista anteriore',
                          style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                      pw.SizedBox(height: 4),
                      pw.SizedBox(
                        width: 180,
                        height: 180 / 0.45,
                        child: pw.Image(pw.MemoryImage(frontRendered), fit: pw.BoxFit.contain),
                      ),
                    ],
                  ),
                if (frontRendered != null && backRendered != null)
                  pw.SizedBox(width: 16),
                if (backRendered != null)
                  pw.Column(
                    mainAxisSize: pw.MainAxisSize.min,
                    children: [
                      pw.Text('Vista posteriore',
                          style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                      pw.SizedBox(height: 4),
                      pw.SizedBox(
                        width: 180,
                        height: 180 / 0.45,
                        child: pw.Image(pw.MemoryImage(backRendered), fit: pw.BoxFit.contain),
                      ),
                    ],
                  ),
              ],
            ),
          ],
          pw.SizedBox(height: 30),
          pw.Divider(),
          pw.SizedBox(height: 8),
          pw.Text(
            'Disclaimer: Il BSA rappresenta esclusivamente la percentuale stimata di superficie corporea interessata e non sostituisce una valutazione dermatologica.',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.Text(
            "L'app non richiede registrazione e non memorizza dati personali o risultati delle valutazioni.",
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    );
    return pdf;
  }

  Future<void> _handlePdfAction(bool isShare) async {
    final pdf = await _buildPdfReport();
    final filename = 'report_bsa_${_selectedDisease.replaceAll(' ', '_')}.pdf';

    if (isShare) {
      await Printing.sharePdf(bytes: await pdf.save(), filename: filename);
    } else {
      await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
        name: filename,
      );
    }
  }

  Future<void> _navigateToMap() async {
    geo.Position? position;
    try {
      // Verifica i permessi prima di richiedere la posizione
      geo.LocationPermission permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
      }

      if (permission == geo.LocationPermission.whileInUse || permission == geo.LocationPermission.always) {
        position = await geo.Geolocator.getCurrentPosition(
          desiredAccuracy: geo.LocationAccuracy.high,
        );
      }
    } catch (e) {
      debugPrint("Errore geolocalizzazione: $e");
    }

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DermatogistsMapWidget(
          initialDisease: _selectedDisease,
          currentPosition: position,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: Text('Mappatura $_selectedDisease', style: const TextStyle(color: Colors.white)),
            backgroundColor: Theme.of(context).colorScheme.primary,
            actions: [
              IconButton(
                icon: const Icon(Icons.map, color: Colors.white),
                onPressed: _navigateToMap,
                tooltip: 'Mappa Centri',
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: _resetAll,
                tooltip: 'Resetta',
              )
            ],
          ),
          body: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.grey[100],
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Patologia: ', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _selectedDisease,
                      items: ['Psoriasi', 'Dermatite Atopica'].map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (newValue) {
                        if (newValue != null) {
                          setState(() => _selectedDisease = newValue);
                        }
                      },
                    ),
                  ],
                ),
              ),
              Container(
                key: _totalBsaKey,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  border: Border(bottom: BorderSide(color: Colors.grey[300]!, width: 1)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('BSA Totale Stimata:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text(
                          '${_totalBsa.toStringAsFixed(2)} %',
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _showDetails,
                        icon: const Icon(Icons.list_alt),
                        label: const Text('VEDI DETTAGLI'),
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text(
                  'L\'app non richiede registrazione e non memorizza dati personali o risultati delle valutazioni',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: SegmentedButton<bool>(
                  key: _selectorKey,
                  segments: const [
                    ButtonSegment(value: true, label: Text('Fronte')),
                    ButtonSegment(value: false, label: Text('Retro')),
                  ],
                  selected: {_isFrontView},
                  onSelectionChanged: (selection) {
                    setState(() => _isFrontView = selection.first);
                  },
                ),
              ),

              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 0.45,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final w = constraints.maxWidth;
                        final h = constraints.maxHeight;

                        final Offset currentOffset = _isFrontView
                            ? const Offset(-10, -17)
                            : const Offset(6, -13);

                        final double currentScale = _isFrontView
                            ? 1.08
                            : 1.08;

                        return Stack(
                          children: [
                            Positioned.fill(
                              child: Transform.scale(
                                scale: currentScale,
                                child: Transform.translate(
                                  offset: currentOffset,
                                  child: Image.asset(
                                    _isFrontView ? 'assets/images/body_front.png' : 'assets/images/body_back.png',
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),

                            if (_isFrontView) ..._buildFrontHitboxes(w, h)
                            else ..._buildBackHitboxes(w, h),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_tutorialStep > 0 && _tutorialRects[_tutorialStep] != null)
          TutorialOverlay(
            highlightRect: _tutorialRects[_tutorialStep]!,
            instructionText: _getTutorialText(_tutorialStep),
            requireTapInsideHole: _tutorialStep == 2,
            onTap: _handleTutorialTap,
            onSkip: _skipTutorial,
          ),
      ],
    );
  }


  String _getRegionOverlayPath(BodyRegion region) {
    switch (region) {
      case BodyRegion.headFront: return 'assets/images/overlay_head_f.png';
      case BodyRegion.headBack: return 'assets/images/overlay_head_b.png';
      case BodyRegion.neckFront: return 'assets/images/overlay_neck_f.png';
      case BodyRegion.neckBack: return 'assets/images/overlay_neck_b.png';
      case BodyRegion.chest: return 'assets/images/overlay_petto_f.png';
      case BodyRegion.abdomen: return 'assets/images/overlay_addome_f.png';
      case BodyRegion.upperBack: return 'assets/images/overlay_tronco_b.png';
      case BodyRegion.lowerBack: return 'assets/images/overlay_lower_b.png';
      case BodyRegion.upperArmLeftFront: return 'assets/images/overlay_upper_arm_fsx.png';
      case BodyRegion.upperArmRightFront: return 'assets/images/overlay_upper_arm_fdx.png';
      case BodyRegion.upperArmLeftBack: return 'assets/images/overlay_upper_arm_bsx.png';
      case BodyRegion.upperArmRightBack: return 'assets/images/overlay_upper_arm_bdx.png';
      case BodyRegion.forearmLeftFront: return 'assets/images/overlay_forearm_fsx.png';
      case BodyRegion.forearmRightFront: return 'assets/images/overlay_forearm_fdx.png';
      case BodyRegion.forearmLeftBack: return 'assets/images/overlay_forearm_bsx.png';
      case BodyRegion.forearmRightBack: return 'assets/images/overlay_forearm_bdx.png';
      case BodyRegion.handLeftFront: return 'assets/images/overlay_hand_fsx.png';
      case BodyRegion.handRightFront: return 'assets/images/overlay_hand_fdx.png';
      case BodyRegion.handLeftBack: return 'assets/images/overlay_hand_bsx.png';
      case BodyRegion.handRightBack: return 'assets/images/overlay_hand_bdx.png';
      case BodyRegion.genitals: return 'assets/images/overlay_gen.png';
      case BodyRegion.buttockLeft: return 'assets/images/overlay_buttock_sx.png';
      case BodyRegion.buttockRight: return 'assets/images/overlay_buttock_dx.png';
      case BodyRegion.thighLeftFront: return 'assets/images/overlay_thigh_fsx.png';
      case BodyRegion.thighRightFront: return 'assets/images/overlay_thigh_fdx.png';
      case BodyRegion.thighLeftBack: return 'assets/images/overlay_thigh_bsx.png';
      case BodyRegion.thighRightBack: return 'assets/images/overlay_thigh_bdx.png';
      case BodyRegion.lowerLegLeftFront: return 'assets/images/overlay_leg_fsx.png';
      case BodyRegion.lowerLegRightFront: return 'assets/images/overlay_leg_fdx.png';
      case BodyRegion.lowerLegLeftBack: return 'assets/images/overlay_leg_bsx.png';
      case BodyRegion.lowerLegRightBack: return 'assets/images/overlay_leg_bdx.png';
      case BodyRegion.footLeftFront: return 'assets/images/overlay_foot_fsx.png';
      case BodyRegion.footRightFront: return 'assets/images/overlay_foot_fdx.png';
      case BodyRegion.footLeftBack: return 'assets/images/overlay_foot_bsx.png';
      case BodyRegion.footRightBack: return 'assets/images/overlay_foot_bdx.png';
    }
  }

  Color _getDiseaseColor(String disease) {
    return disease == 'Psoriasi' ? Colors.red : Colors.orange;
  }

  Future<void> _showCoverageSlider(BodyRegion region) async {
    String regionName = region.name.replaceAll('_', ' ').toUpperCase();
    String specificOverlayPath = _getRegionOverlayPath(region);

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RegionPainterScreen(
          region: region,
          imagePath: specificOverlayPath,
          regionName: regionName,
          initialPoints: _diseasePoints[_selectedDisease]?[region],
          activeColor: _getDiseaseColor(_selectedDisease),
        ),
      ),
    );

    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        _diseaseCoverages[_selectedDisease]![region] = result['coverage'] as double;
        _diseasePoints[_selectedDisease]![region] = result['points'] as List<DrawingPoint?>;
        _regionRenderInfo[_selectedDisease]![region] = {
          'svgWidth': (result['svgWidth'] as num).toDouble(),
          'svgHeight': (result['svgHeight'] as num).toDouble(),
          'canvasWidth': (result['canvasWidth'] as num).toDouble(),
          'canvasHeight': (result['canvasHeight'] as num).toDouble(),
        };
      });
    }
  }

  Widget _buildHitbox(BodyRegion region, double w, double h, {required double top, required double left, required double width, required double height, BorderRadius? borderRadius}) {
    double coverage = _diseaseCoverages[_selectedDisease]?[region] ?? 0.0;

    Color diseaseColor = _getDiseaseColor(_selectedDisease);
    Color overlayColor = diseaseColor.withOpacity((coverage / 100.0) * 0.8);

    return Positioned(
      top: h * top,
      left: w * left,
      width: w * width,
      height: h * height,
      child: Container(
        key: region == BodyRegion.headFront ? _headKey : null,
        child: GestureDetector(
          onTap: () => _showCoverageSlider(region),
          child: Container(
            decoration: BoxDecoration(
              color: coverage > 0 ? overlayColor : Colors.transparent,
              border: Border.all(color: Colors.grey.withOpacity(0.2), width: 0.5),
              borderRadius: borderRadius ?? BorderRadius.circular(50),
            ),
          ),
        ),
      ),
    );
  }


  // COORDINATE FRONTALI E POSTERIORI
  List<Widget> _buildFrontHitboxes(double w, double h) {
    return [
      _buildHitbox(BodyRegion.headFront, w, h, top: 0.03, left: 0.40, width: 0.19, height: 0.12),
      _buildHitbox(BodyRegion.neckFront, w, h, top: 0.14, left: 0.43, width: 0.14, height: 0.04),
      _buildHitbox(BodyRegion.chest, w, h, top: 0.18, left: 0.33, width: 0.33, height: 0.16, borderRadius: BorderRadius.circular(10)),
      _buildHitbox(BodyRegion.abdomen, w, h, top: 0.34, left: 0.35, width: 0.30, height: 0.11, borderRadius: BorderRadius.circular(10)),
      _buildHitbox(BodyRegion.genitals, w, h, top: 0.44, left: 0.42, width: 0.15, height: 0.06),
      _buildHitbox(BodyRegion.upperArmLeftFront, w, h, top: 0.19, left: 0.65, width: 0.11, height: 0.15),
      _buildHitbox(BodyRegion.forearmLeftFront, w, h, top: 0.34, left: 0.70, width: 0.12, height: 0.14),
      _buildHitbox(BodyRegion.handLeftFront, w, h, top: 0.47, left: 0.79, width: 0.13, height: 0.08),
      _buildHitbox(BodyRegion.upperArmRightFront, w, h, top: 0.19, left: 0.23, width: 0.11, height: 0.15),
      _buildHitbox(BodyRegion.forearmRightFront, w, h, top: 0.34, left: 0.15, width: 0.12, height: 0.14),
      _buildHitbox(BodyRegion.handRightFront, w, h, top: 0.47, left: 0.07, width: 0.13, height: 0.08),
      _buildHitbox(BodyRegion.thighLeftFront, w, h, top: 0.47, left: 0.51, width: 0.18, height: 0.20, borderRadius: BorderRadius.circular(10)),
      _buildHitbox(BodyRegion.lowerLegLeftFront, w, h, top: 0.67, left: 0.53, width: 0.12, height: 0.16, borderRadius: BorderRadius.circular(10)),
      _buildHitbox(BodyRegion.footLeftFront, w, h, top: 0.83, left: 0.54, width: 0.12, height: 0.10),
      _buildHitbox(BodyRegion.thighRightFront, w, h, top: 0.47, left: 0.30, width: 0.18, height: 0.20, borderRadius: BorderRadius.circular(10)),
      _buildHitbox(BodyRegion.lowerLegRightFront, w, h, top: 0.67, left: 0.34, width: 0.12, height: 0.16, borderRadius: BorderRadius.circular(10)),
      _buildHitbox(BodyRegion.footRightFront, w, h, top: 0.83, left: 0.34, width: 0.12, height: 0.10),
    ];
  }

  List<Widget> _buildBackHitboxes(double w, double h) {
    return [
      _buildHitbox(BodyRegion.headBack, w, h, top: 0.04, left: 0.40, width: 0.20, height: 0.10),
      _buildHitbox(BodyRegion.neckBack, w, h, top: 0.14, left: 0.43, width: 0.14, height: 0.03),
      _buildHitbox(BodyRegion.upperBack, w, h, top: 0.17, left: 0.35, width: 0.30, height: 0.17, borderRadius: BorderRadius.circular(10)),
      _buildHitbox(BodyRegion.lowerBack, w, h, top: 0.35, left: 0.35, width: 0.31, height: 0.07, borderRadius: BorderRadius.circular(10)),
      _buildHitbox(BodyRegion.buttockRight, w, h, top: 0.43, left: 0.32, width: 0.18, height: 0.09),
      _buildHitbox(BodyRegion.buttockLeft, w, h, top: 0.43, left: 0.52, width: 0.18, height: 0.09),
      _buildHitbox(BodyRegion.upperArmLeftBack, w, h, top: 0.20, left: 0.23, width: 0.11, height: 0.15),
      _buildHitbox(BodyRegion.forearmLeftBack, w, h, top: 0.35, left: 0.13, width: 0.15, height: 0.13),
      _buildHitbox(BodyRegion.handLeftBack, w, h, top: 0.48, left: 0.07, width: 0.12, height: 0.08),
      _buildHitbox(BodyRegion.upperArmRightBack, w, h, top: 0.20, left: 0.67, width: 0.11, height: 0.15),
      _buildHitbox(BodyRegion.forearmRightBack, w, h, top: 0.35, left: 0.73, width: 0.15, height: 0.13),
      _buildHitbox(BodyRegion.handRightBack, w, h, top: 0.48, left: 0.83, width: 0.12, height: 0.08),
      _buildHitbox(BodyRegion.thighLeftBack, w, h, top: 0.52, left: 0.32, width: 0.17, height: 0.17, borderRadius: BorderRadius.circular(10)),
      _buildHitbox(BodyRegion.lowerLegLeftBack, w, h, top: 0.69, left: 0.35, width: 0.13, height: 0.17, borderRadius: BorderRadius.circular(10)),
      _buildHitbox(BodyRegion.footLeftBack, w, h, top: 0.86, left: 0.35, width: 0.12, height: 0.10),
      _buildHitbox(BodyRegion.thighRightBack, w, h, top: 0.52, left: 0.53, width: 0.17, height: 0.17, borderRadius: BorderRadius.circular(10)),
      _buildHitbox(BodyRegion.lowerLegRightBack, w, h, top: 0.69, left: 0.54, width: 0.13, height: 0.17, borderRadius: BorderRadius.circular(10)),
      _buildHitbox(BodyRegion.footRightBack, w, h, top: 0.86, left: 0.54, width: 0.12, height: 0.10),
    ];
  }
}