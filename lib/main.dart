import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:vibration/vibration.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'widgets/scanner_overlay.dart';
import 'models/scan_result.dart';

void main() {
  runApp(const ScannerApp());
}

class ScannerApp extends StatelessWidget {
  const ScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QuickScanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blueAccent,
        brightness: Brightness.dark,
        fontFamily: 'SF Pro Display', // Apple's font (fits the theme)
      ),
      home: const ScannerScreen(),
    );
  }
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  final MobileScannerController controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    torchEnabled: false,
    autoStart: true,
  );

  bool isScanned = false;
  double _baseZoomScale = 0.0;
  bool enableVibration = true;
  bool enableSound = true;

  OverlayEntry? _currentOverlay;

  void _showTopNotification(String message) {
    _currentOverlay?.remove();
    _currentOverlay = OverlayEntry(
      builder: (context) => _TopNotification(
        message: message,
        onDismiss: () {
          _currentOverlay?.remove();
          _currentOverlay = null;
        },
      ),
    );

    Overlay.of(context).insert(_currentOverlay!);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!controller.value.isInitialized) return;

    switch (state) {
      case AppLifecycleState.resumed:
        controller.start();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        controller.stop();
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> _checkPermission() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      if (mounted) {
        await controller.start();
        // Set a slight initial zoom (0.1 = ~1.4x) - enough to help, not enough to blur
        controller.setZoomScale(0.1);
      }
    } else if (status.isDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera permission is required')),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  bool _isUrl(String text) {
    final sanitized = text.trim().toLowerCase();
    if (sanitized.startsWith('http://') || sanitized.startsWith('https://')) {
      return true;
    }
    // Simple check for domains: contains a dot, no spaces, and doesn't look like an email
    if (sanitized.contains('.') &&
        !sanitized.contains(' ') &&
        !sanitized.contains('@')) {
      return true;
    }
    return false;
  }

  void _onDetect(BarcodeCapture capture) async {
    if (isScanned) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final String code = barcodes.first.rawValue ?? '---';
      debugPrint('QR Code detected: $code');
      _handleResult(code);
    }
  }

  void _handleResult(String code) async {
    setState(() {
      isScanned = true;
    });

    // Stop detection immediately to prevent duplicate sheets
    // We stay active but stop the engine processing
    try {
      await controller.stop();
    } catch (e) {
      debugPrint('Error stopping controller: $e');
    }

    if (enableSound) {
      SystemSound.play(SystemSoundType.click);
    }

    if (enableVibration) {
      // Use HapticFeedback as it's more reliable on modern Android/iOS
      HapticFeedback.mediumImpact();
      // Also try Vibration package for legacy support
      Vibration.vibrate(duration: 70);
    }

    final bool isUrl = _isUrl(code);

    // Add to history
    scanHistory.insert(
      0,
      ScanResult(code: code, timestamp: DateTime.now(), isUrl: isUrl),
    );

    if (mounted) {
      _showResultSheet(code, isUrl);
    }
  }

  void _showResultSheet(String code, bool isUrl) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E).withOpacity(0.85),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30),
              ),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isUrl
                        ? Colors.blueAccent.withOpacity(0.1)
                        : Colors.greenAccent.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isUrl ? Icons.link_rounded : Icons.qr_code_2_rounded,
                    color: isUrl ? Colors.blueAccent : Colors.greenAccent,
                    size: 50,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  isUrl ? 'Link Found' : 'Result Found',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(18),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: SelectableText(
                    code,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    if (isUrl) ...[
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            String urlString = code.trim();
                            if (!urlString.startsWith('http://') &&
                                !urlString.startsWith('https://')) {
                              urlString = 'https://$urlString';
                            }
                            final url = Uri.tryParse(urlString);
                            if (url != null) {
                              try {
                                await launchUrl(
                                  url,
                                  mode: LaunchMode.externalApplication,
                                );
                              } catch (e) {
                                _showTopNotification('Could not open link');
                              }
                            }
                          },
                          icon: const Icon(Icons.open_in_new_rounded, size: 20),
                          label: const Text('Open'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: code));
                          _showTopNotification('Copied to clipboard');
                        },
                        icon: const Icon(Icons.copy_rounded, size: 20),
                        label: const Text('Copy'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white10,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: const BorderSide(color: Colors.white10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Done',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    ).then((_) async {
      // Small delay before allowing next scan to avoid accidental double-scans
      await Future.delayed(const Duration(milliseconds: 200));

      // Restart the camera engine to clear its internal barcode cache
      // This is the key to 'same QR' scanning quickly
      try {
        if (mounted) {
          await controller.start();
          HapticFeedback.lightImpact(); // Subtle confirmation
        }
      } catch (e) {
        debugPrint('Error starting controller: $e');
      }

      if (mounted) {
        setState(() {
          isScanned = false;
        });
      }
    });
  }

  void _showSettingsDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E).withOpacity(0.8),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Row(
                    children: [
                      Icon(
                        Icons.settings_rounded,
                        color: Colors.blueAccent,
                        size: 28,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Settings',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: -1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildSettingsTile(
                    title: 'Vibration',
                    subtitle: 'Haptic feedback on scan',
                    icon: Icons.vibration_rounded,
                    value: enableVibration,
                    onChanged: (val) {
                      setState(() => enableVibration = val);
                      setDialogState(() => enableVibration = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildSettingsTile(
                    title: 'Beep Sound',
                    subtitle: 'Audio cue on detection',
                    icon: Icons.volume_up_rounded,
                    value: enableSound,
                    onChanged: (val) {
                      setState(() => enableSound = val);
                      setDialogState(() => enableSound = val);
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.white.withOpacity(0.05),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Close',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.blueAccent, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeColor: Colors.blueAccent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      final results = await controller.analyzeImage(image.path);
      if (results != null && results.barcodes.isNotEmpty) {
        _handleResult(results.barcodes.first.rawValue ?? '---');
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No QR code found in image')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final scanWindow = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: 280,
      height: 280,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (details) {
              _baseZoomScale = controller.value.zoomScale;
            },
            onScaleUpdate: (details) {
              // Increase sensitivity slightly (0.7 instead of 0.5)
              final double newZoom =
                  (_baseZoomScale + (details.scale - 1.0) * 0.7).clamp(
                    0.0,
                    1.0,
                  );
              controller.setZoomScale(newZoom);
            },
            child: MobileScanner(
              controller: controller,
              onDetect: _onDetect,
              errorBuilder: (context, error, child) {
                debugPrint('MobileScanner Error: ${error.errorCode}');
                return Center(
                  child: Text(
                    'Error: ${error.errorCode}',
                    style: const TextStyle(color: Colors.white),
                  ),
                );
              },
            ),
          ),
          IgnorePointer(child: ScannerOverlay(scanWindow: scanWindow)),

          // Top Bar Overlay
          Positioned(
            top: 55,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // History Button
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const HistoryScreen(),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(
                      Icons.history_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),

                // Zoom Indicator
                ValueListenableBuilder(
                  valueListenable: controller,
                  builder: (context, state, child) {
                    final zoomDisplay = 1.0 + (state.zoomScale * 4.0);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text(
                        '${zoomDisplay.toStringAsFixed(1)}X Zoom',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  },
                ),

                // Settings Button
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _showSettingsDialog();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(
                      Icons.settings_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom Controls
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Flashlight
                ValueListenableBuilder(
                  valueListenable: controller,
                  builder: (context, state, child) {
                    final isTorchOn = state.torchState == TorchState.on;
                    final isInitialized = state.isInitialized;

                    return GestureDetector(
                      onTap: () {
                        if (isInitialized) {
                          controller.toggleTorch();
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Camera not ready yet'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        }
                      },
                      child: Container(
                        height: 70,
                        width: 70,
                        decoration: BoxDecoration(
                          color: isTorchOn ? Colors.blueAccent : Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            if (isTorchOn)
                              BoxShadow(
                                color: Colors.blueAccent.withOpacity(0.5),
                                blurRadius: 15,
                                spreadRadius: 2,
                              ),
                          ],
                        ),
                        child: Icon(
                          isTorchOn
                              ? Icons.flashlight_off_rounded
                              : Icons.flashlight_on_rounded,
                          color: isTorchOn ? Colors.white : Colors.black,
                          size: 30,
                        ),
                      ),
                    );
                  },
                ),
                // Gallery
                GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    height: 70,
                    width: 70,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.image_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  void _showResultDetails(ScanResult result) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E).withOpacity(0.85),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30),
              ),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Icon(
                  result.isUrl ? Icons.link_rounded : Icons.qr_code_2_rounded,
                  color: Colors.blueAccent,
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  result.isUrl ? 'Saved Link' : 'Saved Result',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(18),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: SelectableText(
                    result.code,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    if (result.isUrl) ...[
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            String urlString = result.code.trim();
                            if (!urlString.startsWith('http://') &&
                                !urlString.startsWith('https://')) {
                              urlString = 'https://$urlString';
                            }
                            final url = Uri.tryParse(urlString);
                            if (url != null) {
                              try {
                                await launchUrl(
                                  url,
                                  mode: LaunchMode.externalApplication,
                                );
                              } catch (e) {}
                            }
                          },
                          icon: const Icon(Icons.open_in_new_rounded),
                          label: const Text('Open'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: result.code));
                          Navigator.pop(context);
                          // We need a way to show notification which is currently in ScannerScreenState
                          // For now using simple snackbar or just pop
                        },
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text('Copy'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white10,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            scanHistory.remove(result);
                          });
                          Navigator.pop(context);
                        },
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                        label: const Text('Delete'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent.withOpacity(0.1),
                          foregroundColor: Colors.redAccent,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(
                              color: Colors.redAccent,
                              width: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Close',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Group history by date
    Map<String, List<ScanResult>> groupedHistory = {};
    for (var result in scanHistory) {
      String dateLabel = _formatDate(result.timestamp);
      if (!groupedHistory.containsKey(dateLabel)) {
        groupedHistory[dateLabel] = [];
      }
      groupedHistory[dateLabel]!.add(result);
    }

    final dateKeys = groupedHistory.keys.toList();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'History',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 22,
            letterSpacing: -1,
          ),
        ),
        centerTitle: true,
        actions: [
          if (scanHistory.isNotEmpty)
            IconButton(
              icon: const Icon(
                Icons.delete_sweep_rounded,
                color: Colors.redAccent,
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: const Color(0xFF1E1E1E),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    title: const Text('Clear History?'),
                    content: const Text(
                      'This will delete all your scan history permanently.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            scanHistory.clear();
                          });
                          Navigator.pop(context);
                        },
                        child: const Text(
                          'Clear All',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: scanHistory.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(40),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.history_rounded,
                      size: 100,
                      color: Colors.white.withOpacity(0.1),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Your scans will appear here',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
              itemCount: dateKeys.length,
              itemBuilder: (context, sectionIndex) {
                String dateLabel = dateKeys[sectionIndex];
                List<ScanResult> items = groupedHistory[dateLabel]!;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 4,
                        bottom: 12,
                        top: 12,
                      ),
                      child: Text(
                        dateLabel.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white24,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    ...items.map(
                      (result) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Dismissible(
                          key: Key(result.timestamp.toString() + result.code),
                          direction: DismissDirection.endToStart,
                          onDismissed: (direction) {
                            setState(() {
                              scanHistory.remove(result);
                            });
                          },
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: const Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.redAccent,
                            ),
                          ),
                          child: InkWell(
                            onTap: () => _showResultDetails(result),
                            borderRadius: BorderRadius.circular(22),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.04),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.06),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: result.isUrl
                                          ? Colors.blueAccent.withOpacity(0.1)
                                          : Colors.greenAccent.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Icon(
                                      result.isUrl
                                          ? Icons.link_rounded
                                          : Icons.qr_code_2_rounded,
                                      color: result.isUrl
                                          ? Colors.blueAccent
                                          : Colors.greenAccent,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          result.code,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16,
                                            letterSpacing: -0.3,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _formatTime(result.timestamp),
                                          style: const TextStyle(
                                            color: Colors.white24,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 12,
                                    color: Colors.white12,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (date.day == now.day &&
        date.month == now.month &&
        date.year == now.year) {
      return 'Today';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (date.day == yesterday.day &&
        date.month == yesterday.month &&
        date.year == yesterday.year) {
      return 'Yesterday';
    }
    return '${date.day}/${date.month}';
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _TopNotification extends StatefulWidget {
  final String message;
  final VoidCallback onDismiss;
  const _TopNotification({required this.message, required this.onDismiss});

  @override
  State<_TopNotification> createState() => _TopNotificationState();
}

class _TopNotificationState extends State<_TopNotification>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _controller.forward();

    // Auto-reverse after 1.5 seconds
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) {
        _controller.reverse().then((_) {
          widget.onDismiss();
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 50,
      left: 60,
      right: 60,
      child: SlideTransition(
        position: _offsetAnimation,
        child: Material(
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.check_rounded,
                      color: Colors.green,
                      size: 16,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        widget.message,
                        style: TextStyle(
                          color: Colors.black.withOpacity(0.8),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          letterSpacing: -0.3,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
