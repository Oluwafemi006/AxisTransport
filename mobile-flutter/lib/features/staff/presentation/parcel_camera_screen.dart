import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/axis_spacing.dart';
import '../../../core/theme/axis_tokens.dart';

/// Caméra plein écran : renvoie la photo prise (JPEG) à l'écran du colis.
class ParcelCameraScreen extends StatefulWidget {
  const ParcelCameraScreen({super.key});

  @override
  State<ParcelCameraScreen> createState() => _ParcelCameraScreenState();
}

class _ParcelCameraScreenState extends State<ParcelCameraScreen> {
  CameraController? _controller;
  String? _error;
  bool _taking = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      // Résolution moyenne : assez nette pour l'emballage, légère à envoyer.
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Caméra indisponible. Vérifiez l’autorisation.');
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _take() async {
    final controller = _controller;
    if (controller == null || _taking) return;
    setState(() => _taking = true);
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      if (mounted) Navigator.of(context).pop<List<int>>(bytes);
    } catch (_) {
      if (mounted) {
        setState(() {
          _taking = false;
          _error = 'La photo n’a pas pu être prise. Réessayez.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final axis = context.axis;
    final controller = _controller;
    return Scaffold(
      backgroundColor: axis.ink,
      appBar: AppBar(
        backgroundColor: axis.ink,
        foregroundColor: axis.onDark,
        title: const Text('Photo du colis'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _error != null
                  ? Text(_error!, style: TextStyle(color: axis.onDark))
                  : controller == null
                  ? const CircularProgressIndicator()
                  : CameraPreview(controller),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AxisSpacing.lg),
            child: Tooltip(
              message: 'Prendre la photo',
              child: IconButton.filled(
                iconSize: 40,
                onPressed: controller == null || _taking ? null : _take,
                icon: const Icon(Icons.camera_alt_rounded),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
