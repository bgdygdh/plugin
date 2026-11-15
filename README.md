# body_measurement_plugin

An embeddable Flutter plugin for **automated body measurement, rule-based clothing size recommendation, and AI virtual try-on**. Host e-commerce apps can launch the full fitting-room workflow from any screen with a single Dart method call—no external backend or merchant portal setup required.

## Features

- **Guided Dual-View Capture:** Front and side camera capture with live pose feedback and phone tilt (`90°`) indicator (or gallery upload).
- **Height-Based Scale Calibration:** On-device ML Kit pose estimation and foreground segmentation convert pixels to centimeters using the user's height, with manual `HEAD` / `FEET` fine-tuning handles.
- **3D Circumference Estimation:** Extracts front widths and side depths for Chest/Bust, Waist, and Hips and computes circumferences using Ramanujan's second elliptical approximation with anatomical shape factors.
- **Wearability-First Size Recommendation:** Evaluates calibrated measurements against size charts for Tops, Dresses, Shorts, and Pants, showing part-by-part fit breakdowns (`Optimal`, `Snug`, `Relaxed`).
- **Generative Virtual Try-On:** Built-in virtual try-on fitting with an interactive before/after comparison toggle.

---

## Requirements

- **Flutter:** `>=3.3.0`, **Dart SDK:** `^3.10.7`
- **Android:** `minSdk 24` (Android 7.0+) with camera permission

---

## Quick Integration (2 Minutes)

### 1. Add the dependency

In your Flutter app's `pubspec.yaml`:

```yaml
dependencies:
  body_measurement_plugin:
    git:
      url: https://github.com/bgdygdh/plugin.git
      ref: main
```

Then run:

```bash
flutter pub get
```

### 2. Launch from any screen

Import the package and call `BodyMeasurementPlugin().startCapture(context)` from any button in your app:

```dart
import 'package:body_measurement_plugin/body_measurement_plugin.dart';
```

#### Minimal call (no product metadata required)

```dart
final result = await BodyMeasurementPlugin().startCapture(context);

if (result != null && result.recommendation != null) {
  final recommendedSize = result.recommendation!.recommendedSize; // e.g. 'M'
  final chestCm = result.measurements?[BodyLineKind.chest]?.circumferenceCm;
}
```

#### Pre-filled e-commerce product call

```dart
final result = await BodyMeasurementPlugin().startCapture(
  context,
  userGender: Gender.female,
  initialGarmentType: GarmentType.dress,
  tryOnCategory: TryOnCategory.onePieces,
  garmentImageUrl: product.imageUrl,
);
```

All parameters except `context` are optional. If omitted, the plugin automatically prompts the user for gender/height and lets them pick a garment category or upload a garment photo inside the flow.
