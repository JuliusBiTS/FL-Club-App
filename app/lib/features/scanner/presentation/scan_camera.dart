import 'dart:async';

import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// The one camera view both scanner tabs use. It owns its controller: the
/// camera starts when this widget is built and is released when it goes away,
/// so only the tab you're looking at ever holds the camera (the two tabs used
/// to each start their own, and fought over it). It also:
///  - ignores the same code for a few seconds after it's been read, so a QR
///    still held in front of the lens isn't re-submitted the instant a result
///    is dismissed (or hammered at the server after an error);
///  - shows a plain-English message if the camera can't start (permission
///    denied, no camera) instead of a blank black rectangle.
class ScanCamera extends StatefulWidget {
  const ScanCamera({required this.onCode, super.key});

  final void Function(String code) onCode;

  @override
  State<ScanCamera> createState() => ScanCameraState();
}

class ScanCameraState extends State<ScanCamera> {
  static const Duration _repeatWindow = Duration(seconds: 4);

  final MobileScannerController _controller = MobileScannerController(
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  String? _lastCode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> toggleTorch() => _controller.toggleTorch();

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    for (final Barcode b in capture.barcodes) {
      final String? code = b.rawValue;
      if (code == null || code.isEmpty) continue;
      final DateTime now = DateTime.now();
      if (code == _lastCode && now.difference(_lastAt) < _repeatWindow) return;
      _lastCode = code;
      _lastAt = now;
      widget.onCode(code);
      return;
    }
  }

  bool? _visible;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The scanner tab stays mounted (hidden) after you leave it; make sure the
    // camera is actually released then, and reacquired when you come back.
    final bool visible = TickerMode.valuesOf(context).enabled;
    if (_visible != null && _visible != visible) {
      unawaited((visible ? _controller.start() : _controller.stop()).catchError((Object _) {}));
    }
    _visible = visible;
  }

  @override
  Widget build(BuildContext context) {
    return TickerMode.valuesOf(context).enabled ? _camera() : const ColoredBox(color: Colors.black);
  }

  Widget _camera() {
    return MobileScanner(
      controller: _controller,
      onDetect: _onDetect,
      errorBuilder: (BuildContext context, MobileScannerException error, Widget? child) {
        final bool denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
        return ColoredBox(
          color: Colors.black,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(FlcSpace.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 40),
                  const SizedBox(height: FlcSpace.sm),
                  Text(
                    denied
                        ? 'The camera is blocked. Allow camera access for this app in your phone\'s settings, then come back.'
                        : "The camera couldn't start. Close other apps using it and try again.",
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: FlcSpace.md),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                    onPressed: () => unawaited(_controller.start()),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
