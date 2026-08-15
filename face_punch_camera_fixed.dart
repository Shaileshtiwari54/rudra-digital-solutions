import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

/// Live front-camera session with blink-based liveness verification.
///
/// Flow:
/// 1. Start front camera.
/// 2. Detect a reasonably sized face.
/// 3. Wait until both eyes are clearly OPEN.
/// 4. Detect the eyes becoming CLOSED.
/// 5. Mark blink as verified.
/// 6. InlinePunchControls explicitly starts photo capture.
class FacePunchCameraController extends ChangeNotifier {
  CameraController? _camera;
  FaceDetector? _detector;

  bool _busyFrame = false;
  bool _captured = false;
  bool _blinkVerified = false;
  bool _starting = false;

  /// Becomes true after we have seen the user's eyes open.
  bool _eyesOpened = false;

  /// Consecutive frames where both eyes are considered closed.
  int _closedEyeFrames = 0;

  /// Prevents immediate false capture when the camera starts.
  int _validFaceFrames = 0;

  String? error;

  CameraController? get camera => _camera;

  bool get isReady =>
      _camera != null && _camera!.value.isInitialized && error == null;

  bool get isStarting => _starting;

  bool get hasCaptured => _captured;

  bool get blinkVerified => _blinkVerified;

  /// Whether the camera has detected an open-eye state.
  bool get eyesOpened => _eyesOpened;

  Future<void> start() async {
    if (_starting || isReady) return;

    _starting = true;
    _captured = false;
    _blinkVerified = false;
    _eyesOpened = false;
    _closedEyeFrames = 0;
    _validFaceFrames = 0;
    error = null;
    notifyListeners();

    try {
      final camPerm = await Permission.camera.request();

      if (!camPerm.isGranted) {
        throw Exception(
          'Camera permission is required for punch verification.',
        );
      }

      final cameras = await availableCameras();

      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.isNotEmpty
            ? cameras.first
            : (throw Exception('No camera available on this device.')),
      );

      final controller = CameraController(
        front,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await controller.initialize();

      _camera = controller;

      _detector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.fast,

          // Required for eye-open probability.
          enableClassification: true,

          enableLandmarks: false,
          enableContours: false,

          minFaceSize: 0.2,
        ),
      );

      await controller.startImageStream(_onFrame);

      notifyListeners();
    } catch (e) {
      error = e.toString();
      await stop();
      notifyListeners();
      rethrow;
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_busyFrame ||
        _captured ||
        _camera == null ||
        _detector == null) {
      return;
    }

    _busyFrame = true;

    try {
      final input = _toInputImage(
        image,
        _camera!.description,
      );

      if (input == null) return;

      final faces = await _detector!.processImage(input);

      if (faces.isEmpty || _captured) {
        _validFaceFrames = 0;
        _closedEyeFrames = 0;
        return;
      }

      // Use the largest detected face.
      final face = faces.reduce(
        (a, b) =>
            (a.boundingBox.width * a.boundingBox.height) >=
                    (b.boundingBox.width * b.boundingBox.height)
                ? a
                : b,
      );

      final box = face.boundingBox;

      final frameArea = image.width * image.height;
      final faceArea = box.width * box.height;

      if (frameArea <= 0) return;

      final faceRatio = faceArea / frameArea;

      // Face must be reasonably close to the camera.
      if (faceRatio < 0.04) {
        _validFaceFrames = 0;
        _closedEyeFrames = 0;
        return;
      }

      _validFaceFrames++;

      // Don't make a decision from the first random frame.
      if (_validFaceFrames < 3) {
        return;
      }

      final leftEye = face.leftEyeOpenProbability;
      final rightEye = face.rightEyeOpenProbability;

      // ML Kit can return null if it cannot classify an eye.
      if (leftEye == null || rightEye == null) {
        return;
      }

      const openThreshold = 0.65;
      const closedThreshold = 0.35;

      final bothEyesOpen =
          leftEye >= openThreshold && rightEye >= openThreshold;

      final bothEyesClosed =
          leftEye <= closedThreshold && rightEye <= closedThreshold;

      // STEP 1:
      // User must first have both eyes open.
      if (bothEyesOpen) {
        if (!_eyesOpened) {
          _eyesOpened = true;
          notifyListeners();
        }

        _closedEyeFrames = 0;
        return;
      }

      // STEP 2:
      // After eyes have been seen open, detect closing.
      if (_eyesOpened && bothEyesClosed) {
        _closedEyeFrames++;

        // Require several consecutive closed frames.
        // This prevents random ML classification noise
        // from triggering a photo.
        if (_closedEyeFrames >= 2) {
          _markBlinkVerified();
        }

        return;
      }

      // Intermediate state: one eye may be open/closing.
      // Do not capture.
      _closedEyeFrames = 0;
    } catch (_) {
      // Ignore transient frame errors.
      // Camera continues streaming.
    } finally {
      _busyFrame = false;
    }
  }

  /// Marks the blink as a liveness verification only.
  ///
  /// IMPORTANT: Blink never captures a photo.
  void _markBlinkVerified() {
    if (_blinkVerified || _captured) return;

    _blinkVerified = true;
    _closedEyeFrames = 0;
    notifyListeners();
  }

  /// Takes the actual JPEG still from the camera.
  ///
  /// This is called only after blink verification and an explicit capture action.
  Future<XFile> takePicture() async {
    final cam = _camera;

    if (cam == null || !cam.value.isInitialized) {
      throw Exception('Camera is not ready.');
    }

    if (!_blinkVerified) {
      throw Exception('Please blink once before capturing the photo.');
    }

    if (_captured) {
      throw Exception('Photo has already been captured.');
    }

    if (cam.value.isStreamingImages) {
      await cam.stopImageStream();
    }

    // Small delay allows camera exposure/focus to settle
    // after the image stream has stopped.
    await Future<void>.delayed(
      const Duration(milliseconds: 150),
    );

    final shot = await cam.takePicture();
    _captured = true;
    notifyListeners();
    return shot;
  }

  Future<void> stop() async {
    final cam = _camera;

    _camera = null;

    _captured = false;
    _blinkVerified = false;
    _eyesOpened = false;
    _closedEyeFrames = 0;
    _validFaceFrames = 0;

    try {
      if (cam != null) {
        if (cam.value.isStreamingImages) {
          await cam.stopImageStream();
        }

        await cam.dispose();
      }
    } catch (_) {}

    await _detector?.close();
    _detector = null;

    notifyListeners();
  }

  InputImage? _toInputImage(
    CameraImage image,
    CameraDescription description,
  ) {
    final rotation =
        InputImageRotationValue.fromRawValue(
          description.sensorOrientation,
        ) ??
        InputImageRotation.rotation0deg;

    final format = InputImageFormatValue.fromRawValue(
      image.format.raw,
    );

    if (format == null) return null;

    if (image.planes.isEmpty) return null;

    late final Uint8List bytes;

    if (image.planes.length == 1) {
      bytes = image.planes.first.bytes;
    } else if (Platform.isAndroid) {
      // Android camera may provide multiple YUV planes.
      // Combine them into a single byte buffer for ML Kit.
      final write = BytesBuilder(copy: false);

      for (final plane in image.planes) {
        write.add(plane.bytes);
      }

      bytes = write.toBytes();
    } else {
      bytes = image.planes.first.bytes;
    }

    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(
          image.width.toDouble(),
          image.height.toDouble(),
        ),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
