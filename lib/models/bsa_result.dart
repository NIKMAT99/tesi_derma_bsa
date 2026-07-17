import 'body_region.dart';

class BsaResult {
  final BodyRegion region;
  final int lesionAreaPixels;
  final int regionTotalAreaPixels;
  final double finalInvolvedPercentage;

  BsaResult({
    required this.region,
    required this.lesionAreaPixels,
    required this.regionTotalAreaPixels,
    required this.finalInvolvedPercentage,
  });
}