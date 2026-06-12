import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

class AssetPdfViewerScreen extends StatefulWidget {
  final String title;
  final String assetPath;

  const AssetPdfViewerScreen({
    super.key,
    required this.title,
    required this.assetPath,
  });

  static Route<void> route({
    required String title,
    required String assetPath,
  }) {
    return PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) =>
          AssetPdfViewerScreen(title: title, assetPath: assetPath),
    );
  }

  @override
  State<AssetPdfViewerScreen> createState() => _AssetPdfViewerScreenState();
}

class _AssetPdfViewerScreenState extends State<AssetPdfViewerScreen> {
  late final PdfViewerController _pdfViewerController;
  bool _isLoading = true;
  String? _loadError;
  Uint8List? _documentBytes;

  @override
  void initState() {
    super.initState();
    _pdfViewerController = PdfViewerController();
    _loadPdfBytes();
  }

  @override
  void dispose() {
    _pdfViewerController.dispose();
    super.dispose();
  }

  Future<void> _loadPdfBytes() async {
    try {
      final ByteData data = await rootBundle.load(widget.assetPath);
      if (!mounted) {
        return;
      }
      setState(() {
        _documentBytes = data.buffer.asUint8List();
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _loadError = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasDocument = _documentBytes != null && _loadError == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: hasDocument
                ? _pdfViewerController.previousPage
                : null,
            tooltip: 'Previous page',
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          IconButton(
            onPressed: hasDocument ? _pdfViewerController.nextPage : null,
            tooltip: 'Next page',
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
      body: ColoredBox(
        color: Colors.white,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
            ? _PdfLoadErrorView(
                title: widget.title,
                message: _loadError!,
              )
            : SizedBox.expand(
                child: SfPdfViewer.memory(
                  _documentBytes!,
                  controller: _pdfViewerController,
                  pageLayoutMode: PdfPageLayoutMode.continuous,
                  scrollDirection: PdfScrollDirection.vertical,
                  interactionMode: PdfInteractionMode.pan,
                  enableDoubleTapZooming: true,
                  enableTextSelection: false,
                  pageSpacing: 8,
                  canShowScrollHead: false,
                  canShowPaginationDialog: false,
                  canShowPageLoadingIndicator: false,
                  onDocumentLoadFailed: (details) {
                    if (!mounted) {
                      return;
                    }
                    setState(() {
                      _loadError = details.description;
                    });
                  },
                ),
              ),
      ),
    );
  }
}

class _PdfLoadErrorView extends StatelessWidget {
  final String title;
  final String message;

  const _PdfLoadErrorView({
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.picture_as_pdf_outlined,
              size: 56,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 12),
            Text(
              'Unable to open $title',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
