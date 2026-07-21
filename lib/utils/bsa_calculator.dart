
import 'dart:math';
import '../models/body_region.dart';
import '../models/bsa_result.dart';

class BsaCalculator {
  static double getRegionPercentage(BodyRegion region) {
    switch (region) {
      case BodyRegion.headFront:
      case BodyRegion.headBack:
        return 3.5;
      case BodyRegion.neckFront:
      case BodyRegion.neckBack:
        return 1.0;

      case BodyRegion.chest:
      case BodyRegion.abdomen:
      case BodyRegion.upperBack:
      case BodyRegion.lowerBack:
        return 6.5;

      case BodyRegion.upperArmLeftFront:
      case BodyRegion.upperArmRightFront:
      case BodyRegion.upperArmLeftBack:
      case BodyRegion.upperArmRightBack:
        return 2.0;
      case BodyRegion.forearmLeftFront:
      case BodyRegion.forearmRightFront:
      case BodyRegion.forearmLeftBack:
      case BodyRegion.forearmRightBack:
        return 1.5;
      case BodyRegion.handLeftFront:
      case BodyRegion.handRightFront:
      case BodyRegion.handLeftBack:
      case BodyRegion.handRightBack:
        return 1.25;

      case BodyRegion.genitals:
        return 1.0;
      case BodyRegion.buttockLeft:
      case BodyRegion.buttockRight:
        return 2.5;

      case BodyRegion.thighLeftFront:
      case BodyRegion.thighRightFront:
      case BodyRegion.thighLeftBack:
      case BodyRegion.thighRightBack:
        return 4.5;
      case BodyRegion.lowerLegLeftFront:
      case BodyRegion.lowerLegRightFront:
      case BodyRegion.lowerLegLeftBack:
      case BodyRegion.lowerLegRightBack:
        return 4.0;
      case BodyRegion.footLeftFront:
      case BodyRegion.footRightFront:
      case BodyRegion.footLeftBack:
      case BodyRegion.footRightBack:
        return 1.5;
    }
  }

  static BsaResult calculateLesionBsa(BodyRegion region, int lesionAreaPixels, int regionTotalAreaPixels) {
    double regionMaxBsa = getRegionPercentage(region);

    double coverageFraction = regionTotalAreaPixels > 0
        ? lesionAreaPixels.toDouble() / regionTotalAreaPixels.toDouble()
        : 0.0;

    double calculatedBsa = coverageFraction * regionMaxBsa;

    return BsaResult(
      region: region,
      lesionAreaPixels: lesionAreaPixels,
      regionTotalAreaPixels: regionTotalAreaPixels,
      finalInvolvedPercentage: min(calculatedBsa, regionMaxBsa),
    );
  }

  static Map<String, double> calculateBreakdown(Map<BodyRegion, double> regionCoverages) {
    double headAndNeck = 0;
    double upperLimbs = 0;
    double trunk = 0;
    double lowerLimbs = 0;

    regionCoverages.forEach((region, coveragePercent) {
      if (coveragePercent <= 0) return;
      double maxRegionBsa = getRegionPercentage(region);
      double actualBsa = (coveragePercent / 100.0) * maxRegionBsa;

      switch (region) {
        case BodyRegion.headFront:
        case BodyRegion.headBack:
        case BodyRegion.neckFront:
        case BodyRegion.neckBack:
          headAndNeck += actualBsa;
          break;

        case BodyRegion.upperArmLeftFront:
        case BodyRegion.upperArmRightFront:
        case BodyRegion.upperArmLeftBack:
        case BodyRegion.upperArmRightBack:
        case BodyRegion.forearmLeftFront:
        case BodyRegion.forearmRightFront:
        case BodyRegion.forearmLeftBack:
        case BodyRegion.forearmRightBack:
        case BodyRegion.handLeftFront:
        case BodyRegion.handRightFront:
        case BodyRegion.handLeftBack:
        case BodyRegion.handRightBack:
          upperLimbs += actualBsa;
          break;

        case BodyRegion.chest:
        case BodyRegion.abdomen:
        case BodyRegion.upperBack:
        case BodyRegion.lowerBack:
        case BodyRegion.genitals:
        case BodyRegion.buttockLeft:
        case BodyRegion.buttockRight:
          trunk += actualBsa;
          break;

        case BodyRegion.thighLeftFront:
        case BodyRegion.thighRightFront:
        case BodyRegion.thighLeftBack:
        case BodyRegion.thighRightBack:
        case BodyRegion.lowerLegLeftFront:
        case BodyRegion.lowerLegRightFront:
        case BodyRegion.lowerLegLeftBack:
        case BodyRegion.lowerLegRightBack:
        case BodyRegion.footLeftFront:
        case BodyRegion.footRightFront:
        case BodyRegion.footLeftBack:
        case BodyRegion.footRightBack:
          lowerLimbs += actualBsa;
          break;
      }
    });

    return {
      'Testa e collo': headAndNeck,
      'Arti superiori': upperLimbs,
      'Tronco': trunk,
      'Arti inferiori': lowerLimbs,
    };
  }
}