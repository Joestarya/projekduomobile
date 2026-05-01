// ==========================================
// FILE: lib/widgets/ai_prediction_card.dart
// ==========================================
// Widget ini dipanggil di _buildIdlePanel() di GameScreen
// Tambahkan ke Column children di atas tombol Higher/Lower

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../service/api_config.dart'; // sesuaikan path import kamu

// ─────────────────────────────────────────────
// MODEL
// ─────────────────────────────────────────────
class AiPrediction {
  final String direction;    // "UP" | "DOWN"
  final String confidence;   // "HIGH" | "MEDIUM" | "LOW"
  final String reasoning;
  final double currentPrice;
  final DateTime generatedAt;

  const AiPrediction({
    required this.direction,
    required this.confidence,
    required this.reasoning,
    required this.currentPrice,
    required this.generatedAt,
  });

  factory AiPrediction.fromJson(Map<String, dynamic> json) => AiPrediction(
        direction: json['direction'] as String,
        confidence: json['confidence'] as String,
        reasoning: json['reasoning'] as String,
        currentPrice: (json['currentPrice'] as num).toDouble(),
        generatedAt: DateTime.parse(json['generatedAt'] as String),
      );

  bool get isUp => direction == 'UP';

  Color get directionColor =>
      isUp ? const Color(0xFF26A69A) : const Color(0xFFEF5350);

  Color get confidenceColor {
    switch (confidence) {
      case 'HIGH':
        return const Color(0xFF26A69A);
      case 'MEDIUM':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF3A5070);
    }
  }

  String get confidenceLabel {
    switch (confidence) {
      case 'HIGH':
        return 'Tinggi';
      case 'MEDIUM':
        return 'Sedang';
      default:
        return 'Rendah';
    }
  }
}

// ─────────────────────────────────────────────
// WIDGET
// ─────────────────────────────────────────────
class AiPredictionCard extends StatefulWidget {
  final String selectedPair;

  const AiPredictionCard({super.key, required this.selectedPair});

  @override
  State<AiPredictionCard> createState() => _AiPredictionCardState();
}

class _AiPredictionCardState extends State<AiPredictionCard>
    with SingleTickerProviderStateMixin {
  AiPrediction? _prediction;
  bool _isLoading = false;
  String? _errorMsg;

  late AnimationController _fadeCtrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void didUpdateWidget(AiPredictionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset kalau pair ganti
    if (oldWidget.selectedPair != widget.selectedPair) {
      setState(() {
        _prediction = null;
        _errorMsg = null;
      });
      _fadeCtrl.reset();
    }
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchPrediction() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMsg = null;
      _prediction = null;
    });
    _fadeCtrl.reset();

    try {
      final resp = await http
          .post(
            Uri.parse(ApiConfig.endpoint('/crypto/predict')),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'pair': widget.selectedPair}),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        final prediction = AiPrediction.fromJson(json);
        if (mounted) {
          setState(() => _prediction = prediction);
          _fadeCtrl.forward();
        }
      } else {
        final body = jsonDecode(resp.body);
        if (mounted) {
          setState(() => _errorMsg = body['message'] ?? 'Terjadi kesalahan.');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMsg = 'Koneksi gagal. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header label ──────────────────────
        const Row(
          children: [
            Icon(Icons.auto_awesome_rounded,
                size: 12, color: Color(0xFF3A5070)),
            SizedBox(width: 5),
            Text(
              'AI ANALYSIS',
              style: TextStyle(
                color: Color(0xFF3A5070),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ── Card utama ────────────────────────
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0C1018),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _prediction != null
                  ? _prediction!.directionColor.withOpacity(0.2)
                  : const Color(0xFF0E1420),
              width: 1,
            ),
          ),
          child: _buildCardContent(),
        ),
        const SizedBox(height: 6),

        // ── Disclaimer kecil ──────────────────
        const Text(
          '⚠️  Prediksi AI bukan saran investasi.',
          style: TextStyle(color: Color(0xFF1A2535), fontSize: 10),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _buildCardContent() {
    // State: idle (belum pernah tekan)
    if (!_isLoading && _prediction == null && _errorMsg == null) {
      return _buildIdleContent();
    }

    // State: loading
    if (_isLoading) {
      return _buildLoadingContent();
    }

    // State: error
    if (_errorMsg != null) {
      return _buildErrorContent();
    }

    // State: ada hasil
    return FadeTransition(opacity: _fade, child: _buildResultContent());
  }

  // ── Idle ─────────────────────────────────
  Widget _buildIdleContent() {
    return GestureDetector(
      onTap: _fetchPrediction,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF0F1825),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: const Color(0xFF1A2540), width: 1),
            ),
            child: const Icon(
              Icons.psychology_rounded,
              color: Color(0xFF3A5070),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Minta prediksi dari Gemini AI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Analisis harga & momentum terkini',
                  style: TextStyle(
                      color: Color(0xFF2A3A5A), fontSize: 11),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: Color(0xFF1A2535), size: 18),
        ],
      ),
    );
  }

  // ── Loading ───────────────────────────────
  Widget _buildLoadingContent() {
    return const Row(
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: Color(0xFF3A5070),
          ),
        ),
        SizedBox(width: 12),
        Text(
          'Gemini sedang menganalisis…',
          style: TextStyle(color: Color(0xFF3A5070), fontSize: 13),
        ),
      ],
    );
  }

  // ── Error ─────────────────────────────────
  Widget _buildErrorContent() {
    return Row(
      children: [
        const Icon(Icons.error_outline_rounded,
            color: Color(0xFFEF5350), size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _errorMsg!,
            style: const TextStyle(color: Color(0xFFEF5350), fontSize: 12),
          ),
        ),
        TextButton(
          onPressed: _fetchPrediction,
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Retry',
              style: TextStyle(color: Color(0xFF3A5070), fontSize: 12)),
        ),
      ],
    );
  }

  // ── Result ────────────────────────────────
  Widget _buildResultContent() {
    final p = _prediction!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Direction badge + confidence
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: p.directionColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: p.directionColor.withOpacity(0.2), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    p.isUp ? Icons.north_rounded : Icons.south_rounded,
                    color: p.directionColor,
                    size: 13,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    p.isUp ? 'NAIK' : 'TURUN',
                    style: TextStyle(
                      color: p.directionColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Confidence
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: p.confidenceColor.withOpacity(0.06),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: p.confidenceColor.withOpacity(0.15), width: 1),
              ),
              child: Text(
                'Keyakinan: ${p.confidenceLabel}',
                style: TextStyle(
                  color: p.confidenceColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            // Refresh button
            GestureDetector(
              onTap: _fetchPrediction,
              child: const Icon(Icons.refresh_rounded,
                  color: Color(0xFF1A2535), size: 16),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Reasoning
        Text(
          p.reasoning,
          style: const TextStyle(
            color: Color(0xFF3A5070),
            fontSize: 12,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}