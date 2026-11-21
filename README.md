# body_measurement_plugin

An embeddable Flutter plugin for **automated body measurement, rule-based clothing size recommendation, and AI virtual try-on**. With a single Flutter package call, independent mobile shopping apps get body measurements, clear size recommendations, and virtual outfit previews right inside their existing app — no external backend or store portal required.

## Features

- **Guided Camera Capture:** Front and side camera capture with live pose feedback and phone tilt (`90°`) indicator (or gallery upload).
- **Height-Based Scale Calibration:** On-device ML Kit pose estimation and foreground segmentation convert pixels to centimeters using the user's height, with manual `HEAD` / `FEET` fine-tuning handles.
- **3D Circumference Estimation:** Extracts front widths and side depths for Chest/Bust, Waist, and Hips and computes circumferences using Ramanujan's second elliptical approximation with anatomical shape factors.
- **Wearability-First Size Recommendation:** Evaluates calibrated measurements against size charts for Tops, Dresses, Shorts, and Pants, showing part-by-part fit breakdowns (`Optimal`, `Snug`, `Relaxed`).
- **Virtual Outfit Try-On:** Built-in virtual try-on fitting with an interactive before/after comparison toggle.

---

## Requirements

- **Flutter:** `>=3.3.0`, **Dart SDK:** `^3.10.7`
- **Android:** set `minSdk = 24` in `android/app/build.gradle.kts`
- **iOS (`13.0+`):** add `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` in `Info.plist`

---

## How to Embed the Plugin Into Any Flutter App

Start with basic 1-call embedding, or optionally pass your product's garment type, gender, and photo automatically.

### Step 1: Add Dependency to `pubspec.yaml`

Add under `dependencies:` in your independent Flutter app, then run `flutter pub get` and rebuild once so native camera and ML Kit dependencies link cleanly:

```yaml
dependencies:
  body_measurement_plugin:
    git:
      url: https://github.com/bgdygdh/plugin.git
      ref: main
```

```bash
flutter pub get
```

### Step 2: Basic Embedding (Minimal 1-Call Setup)

Ideal when adding the plugin quickly with zero backend changes. The plugin prompts the shopper for height, gender, photos, garment category, and try-on garment image inside its own flow:

```dart
import 'package:body_measurement_plugin/body_measurement_plugin.dart';

// Add this button anywhere in your product screen:
OutlinedButton.icon(
  onPressed: () async {
    final result = await BodyMeasurementPlugin().startCapture(
      context,
    );
    final rec = result?.recommendation?.recommendedSize;
    if (rec != null && mounted) {
      final upper = rec.toUpperCase();
      if (_sizes.contains(upper)) {
        setState(() => _selectedSize = upper);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Recommended Size: $upper')),
      );
    }
  },
  icon: const Icon(Icons.straighten),
  label: const Text('Find My Size & Try-On'),
  style: OutlinedButton.styleFrom(
    minimumSize: const Size.fromHeight(48),
  ),
),
```

### Step 3 (Optional): Automatic Passing of Garment Type, Gender & Product Photo

When invoking from a product detail page, pass your product's metadata so the sizing chart and Virtual Try-On screen pre-fill automatically without asking the user to pick the garment again:

```dart
import 'package:body_measurement_plugin/body_measurement_plugin.dart';

final result = await BodyMeasurementPlugin().startCapture(
  context,
  userGender: Gender.female,               // Optional: Gender.male | Gender.female
  initialGarmentType: GarmentType.dress,   // Optional: tShirt | dress | shorts | pants
  tryOnCategory: TryOnCategory.onePieces,  // Optional: tops | bottoms | onePieces
  garmentImageUrl: product.imageUrl,       // Optional: URL pre-loaded for Virtual Try-On
  userHeightCm: 165,                       // Optional: skips height prompt if already known
);

// Returned BodyCaptureResult fields your host app can use:
final size = result?.recommendation?.recommendedSize;          // e.g. "M"
final waistCm = result?.measurements?[BodyLineKind.waist]?.circumferenceCm;
final tryOnFile = result?.tryOnResult?.localTryOnImagePath;     // Local generated try-on image
```

#### Supported Parameters

| Parameter | Values | Notes |
| :--- | :--- | :--- |
| `Gender` | `Gender.male`, `Gender.female` | Prompted inside plugin if omitted |
| `GarmentType` | `tShirt`, `dress`, `shorts`, `pants` | Selects size chart automatically |
| `TryOnCategory` | `tops`, `bottoms`, `onePieces` | Pre-selects Virtual Try-On category |
| `garmentImageUrl` | `String?` | Pre-loads catalog photo for Try-On |
| `userHeightCm` | `double?` (`100`–`250`) | Skips height setup screen when passed |
