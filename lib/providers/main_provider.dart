import 'package:flutter/material.dart';
import '../models/body_region.dart';
import '../models/bsa_result.dart';
import '../utils/bsa_calculator.dart';

class MainProvider with ChangeNotifier {
  BodyRegion? _selectedRegion;
  BsaResult? _bsaResult;


  BodyRegion? get selectedRegion => _selectedRegion;
  BsaResult? get bsaResult => _bsaResult;

  void selectRegion(BodyRegion region) {
    _selectedRegion = region;
    _bsaResult = null;
    notifyListeners();
  }


  void calculateManualBsa({required int lesionArea, required int totalArea}) {
    if (_selectedRegion == null) return;

    _bsaResult = BsaCalculator.calculateLesionBsa(
      _selectedRegion!,
      lesionArea,
      totalArea,
    );

    notifyListeners();
  }

  void reset() {
    _selectedRegion = null;
    _bsaResult = null;
    notifyListeners();
  }
}