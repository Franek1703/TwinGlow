/// Conversion between the percent the UI shows and the 0-255 value the firmware
/// stores and hands to Adafruit_NeoPixel.
///
/// The device document holds raw 0-255 so the firmware never has to rescale;
/// percent exists only in the app.
library;

/// Lowest brightness the day slider allows.
///
/// Zero would leave the panel effectively dark with no way back except the
/// physical buttons - `MatrixDriver::setBrightness` clamps 0 up to 1, which is
/// invisible in practice. Sleep mode is the one place 0 is meaningful, and it
/// blanks the display deliberately.
const double kMinBrightnessPercent = 5;

/// Percent (0-100) to the raw 0-255 value stored in Firestore.
int percentToRaw(double percent) {
  final clamped = percent.clamp(0.0, 100.0);
  return (clamped * 255 / 100).round();
}

/// Raw 0-255 back to percent, for driving the slider from a stored value.
double rawToPercent(int raw) {
  final clamped = raw.clamp(0, 255);
  return clamped * 100 / 255;
}
