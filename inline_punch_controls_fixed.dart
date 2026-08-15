import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/face_punch_camera.dart';
import '../services/selfie_store.dart';
import '../state/session.dart';
import 'eye_mark.dart';
import 'glass_card.dart';

enum InlinePunchPhase { idle, scanning, capturing, submitting, success }

/// Home-row punch controls: circular area becomes live FRONT camera preview.
/// Face detect â†’ auto capture â†’ GPS + photo punch â€” no separate camera screen.
class InlinePunchControls extends StatefulWidget {
  const InlinePunchControls({
    super.key,
    required this.canPunchIn,
    required this.canPunchOut,
    required this.sessionBusy,
    this.onAttendanceTap,
    this.onLocationVerified,
  });

  final bool canPunchIn;
  final bool canPunchOut;
  final bool sessionBusy;
  final VoidCallback? onAttendanceTap;
  final void Function(String locationLabel)? onLocationVerified;

  @override
  State<InlinePunchControls> createState() => _InlinePunchControlsState();
}

class _InlinePunchControlsState extends State<InlinePunchControls> {
  final FacePunchCameraController _cam = FacePunchCameraController();

  InlinePunchPhase _phase = InlinePunchPhase.idle;
  bool? _isIn;
  String? _error;
  String? _punchedAt;
  bool _handlingCapture = false;

  @override
  void initState() {
    super.initState();
    _cam.addListener(_onCamChanged);
  }

  @override
  void dispose() {
    _cam.removeListener(_onCamChanged);
    _cam.dispose();
    super.dispose();
  }

  void _onCamChanged() {
    if (!mounted) return;

    setState(() {});


  }

  void _handlePunchInTap() {
    if (_phase != InlinePunchPhase.idle) return;

    if (widget.sessionBusy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait, attendance is being processed.'),
        ),
      );
      return;
    }

    if (!widget.canPunchIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Today's attendance is already marked."),
        ),
      );
      return;
    }

    _armPunch(isIn: true);
  }

  Future<void> _armPunch({required bool isIn}) async {
    if (_phase != InlinePunchPhase.idle || widget.sessionBusy) return;

    setState(() {
      _isIn = isIn;
      _phase = InlinePunchPhase.scanning;
      _error = null;
      _punchedAt = null;
      _handlingCapture = false;
    });

    try {
      await _cam.start();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _phase = InlinePunchPhase.idle;
        _isIn = null;
        _handlingCapture = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  Future<void> _cancelScan() async {
    await _cam.stop();

    if (!mounted) return;

    setState(() {
      _phase = InlinePunchPhase.idle;
      _isIn = null;
      _handlingCapture = false;
    });
  }

  Future<void> _completeAfterFace() async {
    _handlingCapture = true;

    setState(() => _phase = InlinePunchPhase.capturing);

    final session = context.read<SessionController>();
    final isIn = _isIn ?? true;

    try {
      final shot = await _cam.takePicture();
      final bytes = await File(shot.path).readAsBytes();

      final localPath = await SelfieStore.savePunchSelfie(
        bytes: Uint8List.fromList(bytes),
        isIn: isIn,
      );

      await _cam.stop();

      if (!mounted) return;

      setState(() => _phase = InlinePunchPhase.submitting);

      if (isIn) {
        await session.punchIn(
          selfiePath: localPath,
          selfieBytes: bytes,
        );
      } else {
        await session.punchOut(
          selfiePath: localPath,
          selfieBytes: bytes,
        );
      }

      if (!mounted) return;

      final now =
          session.serverClock?.serverNowLocal ?? DateTime.now();

      _punchedAt = DateFormat('hh:mm:ss a').format(now);

      widget.onLocationVerified?.call('Office Location');

      setState(() {
        _phase = InlinePunchPhase.success;
        _handlingCapture = false;
      });
    } catch (e) {
      await _cam.stop();

      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _phase = InlinePunchPhase.idle;
        _isIn = null;
        _handlingCapture = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  void _dismissSuccess() {
    setState(() {
      _phase = InlinePunchPhase.idle;
      _isIn = null;
      _handlingCapture = false;
      _punchedAt = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scanning = _phase == InlinePunchPhase.scanning ||
        _phase == InlinePunchPhase.capturing ||
        _phase == InlinePunchPhase.submitting;

    final punchInEnabled = !widget.sessionBusy &&
        widget.canPunchIn &&
        _phase == InlinePunchPhase.idle;

    final punchOutEnabled = !widget.sessionBusy &&
        widget.canPunchOut &&
        _phase == InlinePunchPhase.idle;

    return Column(
      children: [
        if (_error != null && _phase == InlinePunchPhase.idle) ...[
          GlassCard(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            child: Text(
              _error!,
              style: const TextStyle(
                color: AppTheme.danger,
                fontSize: 13,
              ),
            ),
          ),
        ],

        if (_phase == InlinePunchPhase.success)
          _InlineSuccessBanner(
            isIn: _isIn ?? true,
            punchedAt: _punchedAt ?? 'â€”',
            onDone: _dismissSuccess,
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _SidePunchButton(
                label: 'PUNCH OUT',
                icon: Icons.logout_rounded,
                enabled: punchOutEnabled,
                onTap: () => _armPunch(isIn: false),
              ),

              _CircularPunchCamera(
                phase: _phase,
                isIn: _isIn,
                camera: _cam.camera,
                enabled: punchInEnabled,
                scanning: scanning,
                onPunchInTap: _handlePunchInTap,
                onCancel: scanning ? _cancelScan : null,
              ),

              _SidePunchButton(
                label: 'ATTENDANCE',
                icon: Icons.fact_check_outlined,
                enabled: _phase == InlinePunchPhase.idle,
                onTap: widget.onAttendanceTap ?? () {},
              ),
            ],
          ),

        if (scanning) ...[
          const SizedBox(height: 12),

          Text(
            _phase == InlinePunchPhase.submitting
                ? 'Saving photo + GPSâ€¦'
                : _phase == InlinePunchPhase.capturing
                    ? 'Face found â€” capturingâ€¦'
                    : 'Look into the circle â€” auto capture',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.saffronSoft,
                ),
          ),

          if (_phase == InlinePunchPhase.scanning && _cam.blinkVerified)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: FilledButton.icon(
                onPressed: _handlingCapture ? null : _completeAfterFace,
                icon: const Icon(Icons.camera_alt_rounded),
                label: const Text('CAPTURE PHOTO'),
              ),
            ),

          if (_phase == InlinePunchPhase.scanning)
            TextButton(
              onPressed: _cancelScan,
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: AppTheme.muted,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _CircularPunchCamera extends StatelessWidget {
  const _CircularPunchCamera({
    required this.phase,
    required this.isIn,
    required this.camera,
    required this.enabled,
    required this.scanning,
    required this.onPunchInTap,
    this.onCancel,
  });

  final InlinePunchPhase phase;
  final bool? isIn;
  final CameraController? camera;
  final bool enabled;
  final bool scanning;
  final VoidCallback onPunchInTap;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final label = scanning
        ? (phase == InlinePunchPhase.capturing
            ? 'CAPTURING'
            : phase == InlinePunchPhase.submitting
                ? 'SAVING'
                : 'READY')
        : 'PUNCH IN';

    return Column(
      children: [
        GestureDetector(
          onTap: scanning ? null : onPunchInTap,
          onLongPress: onCancel,
          child: Container(
            width: 108,
            height: 108,
            decoration: BoxDecoration(
              shape: BoxShape.circle,

              gradient: scanning
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: enabled
                          ? const [
                              AppTheme.saffronGlow,
                              AppTheme.saffronDeep,
                            ]
                          : [
                              AppTheme.muted,
                              AppTheme.navyCard,
                            ],
                    ),

              boxShadow:
                  (enabled || scanning) ? AppTheme.glowShadow : null,

              border: Border.all(
                color:
                    scanning ? AppTheme.saffron : Colors.transparent,
                width: 3,
              ),
            ),

            child: ClipOval(
              child: scanning &&
                      camera != null &&
                      camera!.value.isInitialized
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        _CirclePreview(
                          controller: camera!,
                        ),

                        if (phase == InlinePunchPhase.submitting ||
                            phase == InlinePunchPhase.capturing)
                          Container(
                            color: Colors.black45,
                            alignment: Alignment.center,
                            child: const SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.6,
                                color: AppTheme.saffron,
                              ),
                            ),
                          )
                        else
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              width: double.infinity,
                              color: Colors.black54,
                              padding:
                                  const EdgeInsets.symmetric(
                                vertical: 4,
                              ),
                              child: Text(
                                label,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        const EyeMark(
                          size: 42,
                          glow: false,
                        ),

                        const SizedBox(height: 4),

                        Text(
                          label,
                          style: TextStyle(
                            color: Colors.white.withValues(
                              alpha: enabled ? 1 : 0.6,
                            ),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CirclePreview extends StatelessWidget {
  const _CirclePreview({
    required this.controller,
  });

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final size = controller.value.previewSize;

    if (size == null) {
      return const ColoredBox(
        color: Colors.black,
      );
    }

    // Preview is landscape-native; rotate for portrait circle fill.
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: size.height,
        height: size.width,
        child: Transform.scale(
          scaleX: -1,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

class _SidePunchButton extends StatelessWidget {
  const _SidePunchButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            customBorder: const CircleBorder(),
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    AppTheme.navyCard.withValues(alpha: 0.9),
                border: Border.all(
                  color: AppTheme.glassBorder,
                ),
              ),
              child: Icon(
                icon,
                color:
                    enabled ? AppTheme.ivory : AppTheme.muted,
              ),
            ),
          ),
        ),

        const SizedBox(height: 8),

        Text(
          label,
          style: TextStyle(
            color: enabled
                ? AppTheme.ivoryMuted
                : AppTheme.muted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}

class _InlineSuccessBanner extends StatelessWidget {
  const _InlineSuccessBanner({
    required this.isIn,
    required this.punchedAt,
    required this.onDone,
  });

  final bool isIn;
  final String punchedAt;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      glow: true,
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  AppTheme.success.withValues(alpha: 0.15),
              border: Border.all(
                color: AppTheme.success,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      AppTheme.success.withValues(alpha: 0.28),
                  blurRadius: 18,
                ),
              ],
            ),
            child: const Icon(
              Icons.check_rounded,
              color: AppTheme.success,
              size: 36,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            isIn
                ? 'PUNCHED IN Successfully'
                : 'PUNCHED OUT Successfully',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.success,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            punchedAt,
            style: const TextStyle(
              color: AppTheme.ivoryMuted,
            ),
          ),

          const SizedBox(height: 4),

          const Text(
            'Photo + GPS saved with attendance',
            style: TextStyle(
              color: AppTheme.muted,
              fontSize: 12,
            ),
          ),

          const SizedBox(height: 12),

          FilledButton(
            onPressed: onDone,
            child: const Text('DONE'),
          ),
        ],
      ),
    );
  }
}
(venv) PS D:\Projects\RudraERP\rudra_attendance>
