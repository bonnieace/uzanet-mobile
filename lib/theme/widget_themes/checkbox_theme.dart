// MaterialStateProperty remains intentionally used for compatibility with the
// older Flutter versions this mobile client has historically supported.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../../constants/colors.dart';
import '../../constants/sizes.dart';

class TCheckboxTheme {
  TCheckboxTheme._();

  static CheckboxThemeData lightCheckboxTheme = CheckboxThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TSizes.xs)),
    checkColor: MaterialStateProperty.resolveWith((states) {
      return states.contains(MaterialState.selected) ? TColors.white : TColors.black;
    }),
    fillColor: MaterialStateProperty.resolveWith((states) {
      return states.contains(MaterialState.selected) ? TColors.primary : Colors.transparent;
    }),
  );

  static CheckboxThemeData darkCheckboxTheme = CheckboxThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TSizes.xs)),
    checkColor: MaterialStateProperty.resolveWith((states) {
      return states.contains(MaterialState.selected) ? TColors.white : TColors.black;
    }),
    fillColor: MaterialStateProperty.resolveWith((states) {
      return states.contains(MaterialState.selected) ? TColors.primary : Colors.transparent;
    }),
  );
}
