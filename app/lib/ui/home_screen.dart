import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_config.dart';
import '../models/document_record.dart';
import '../services/ad_service.dart';
import '../services/document_store.dart';
import '../services/scan_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.defaultMode});

  final PdfColorMode defaultMode;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DocumentStore _store = DocumentStore.instance;
  final ScanService _scanService = ScanService();

  Timer? _refreshTimer;
  late PdfColorMode _selectedMode;
  List<DocumentRecord> _documents = const <DocumentRecord>[];
  bool _isLoading = true;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.defaultMode;
    _refreshDocuments();
    _refreshTimer = Timer.periodic(liveRefreshInterval, (_) {
      _refreshDocuments(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshDocuments({bool silent = false}) async {
    final documents = await _store.loadDocuments();
    if (!mounted) {
      return;
    }

    setState(() {
      _documents = documents;
      if (!silent) {
        _isLoading = false;
      } else if (_isLoading) {
        _isLoading = false;
      }
    });
  }

  Future<void> _scanDocument() async {
    if (_isScanning) {
      return;
    }

    setState(() {
      _isScanning = true;
    });

    try {
      final record = await _scanService.scanAndCreatePdf(
        context: context,
        mode: _selectedMode,
      );
      await _refreshDocuments();
      if (!mounted) {
        return;
      }

      if (record == null) {
        _showMessage('Scanning discarded.');
        return;
      }

      _showMessage(
        '${record.pageCount}-page ${record.mode.shortLabel} PDF created.',
      );
      unawaited(AdService.instance.maybeShowPostConversionInterstitial());
    } on ScanFlowException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('Something went wrong. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  Future<void> _shareDocument(DocumentRecord record) async {
    if (!await File(record.pdfPath).exists()) {
      _showMessage('The PDF could not be found. Refreshing the list.');
      await _refreshDocuments();
      return;
    }

    await SharePlus.instance.share(
      ShareParams(
        title: 'LovelyPDF Scan',
        subject: 'LovelyPDF document',
        text: 'Shared from the LovelyPDF app.',
        files: <XFile>[XFile(record.pdfPath)],
      ),
    );
  }

  Future<void> _deleteDocument(DocumentRecord record) async {
    await _store.deleteDocument(record.id);
    await _refreshDocuments();
    if (!mounted) {
      return;
    }
    _showMessage('PDF deleted.');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openPrivacyPolicy() async {
    final uri = Uri.parse(privacyPolicyUrl);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      _showMessage('The Privacy Policy could not be opened. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalPages = _documents.fold<int>(
      0,
      (sum, item) => sum + item.pageCount,
    );

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0xFFF3E8D5),
              Color(0xFFF8F5EF),
              Color(0xFFE9F3F1),
            ],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refreshDocuments,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: <Widget>[
                _HeroCard(
                  isScannerSupported: Platform.isAndroid || Platform.isIOS,
                  isScanning: _isScanning,
                  selectedMode: _selectedMode,
                  onScan: _scanDocument,
                ),
                const SizedBox(height: 14),
                _StatsStrip(
                  pdfCount: _documents.length,
                  pageCount: totalPages,
                  retentionLabel:
                      '${documentRetentionDuration.inMinutes} min retention',
                ),
                const SizedBox(height: 14),
                const InlineBannerAdCard(),
                const SizedBox(height: 18),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'PDF output mode',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Please select the pdf color style.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF5C5A57),
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SegmentedButton<PdfColorMode>(
                          showSelectedIcon: false,
                          segments: PdfColorMode.values
                              .map(
                                (mode) => ButtonSegment<PdfColorMode>(
                                  value: mode,
                                  label: Text(mode.shortLabel),
                                ),
                              )
                              .toList(),
                          selected: <PdfColorMode>{_selectedMode},
                          onSelectionChanged: (selection) {
                            setState(() {
                              _selectedMode = selection.first;
                            });
                          },
                        ),
                        const SizedBox(height: 14),
                        _ModeInfoCard(mode: _selectedMode),
                        const SizedBox(height: 12),
                        const _FeatureBand(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Saved PDFs',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Files will be expired in ${documentRetentionDuration.inMinutes} minutes. The list will auto-refresh while the screen is open.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF5C5A57),
                  ),
                ),
                const SizedBox(height: 14),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_documents.isEmpty)
                  const _EmptyState()
                else
                  ..._documents.map(
                    (record) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _DocumentTile(
                        record: record,
                        onShare: () => _shareDocument(record),
                        onDelete: () => _deleteDocument(record),
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                _LegalCard(onPrivacyTap: _openPrivacyPolicy),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.isScannerSupported,
    required this.isScanning,
    required this.selectedMode,
    required this.onScan,
  });

  final bool isScannerSupported;
  final bool isScanning;
  final PdfColorMode selectedMode;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF0F766E),
            Color(0xFF115E59),
            Color(0xFF19403E),
          ],
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x220F766E),
            blurRadius: 28,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0x22FFFFFF),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Up to 30 pages - A4 PDF - Share ready',
              style: theme.textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Scan document, auto crop, and create ${selectedMode.shortLabel} PDF.',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Use tap-to-focus, manual capture, crop, rotate, and blur warnings to get a cleaner PDF.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: const Color(0xFFE4FBF7),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const <Widget>[
              _HeroTag(label: 'Tap focus'),
              _HeroTag(label: 'Blur check'),
              _HeroTag(label: 'Multi-page'),
              _HeroTag(label: 'A4 PDF'),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: isScannerSupported && !isScanning ? onScan : null,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF7B267),
              foregroundColor: const Color(0xFF22201D),
            ),
            icon: isScanning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.document_scanner_outlined),
            label: Text(isScanning ? 'Creating PDF...' : 'Scan with Camera'),
          ),
          const SizedBox(height: 12),
          Text(
            isScannerSupported
                ? 'Tip: tap the document to focus, then hold the phone steady before capturing.'
                : 'Run this on a supported Android or iPhone device to use the camera scanner.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFFD8F2EE),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({
    required this.pdfCount,
    required this.pageCount,
    required this.retentionLabel,
  });

  final int pdfCount;
  final int pageCount;
  final String retentionLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _StatCard(
            title: 'Saved PDFs',
            value: '$pdfCount',
            accent: const Color(0xFF0F766E),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            title: 'Pages',
            value: '$pageCount',
            accent: const Color(0xFFC2410C),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            title: 'Cleanup',
            value: retentionLabel,
            accent: const Color(0xFF334155),
            compact: true,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.accent,
    this.compact = false,
  });

  final String title;
  final String value;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8E0D3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: const Color(0xFF6B665F),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: compact ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeInfoCard extends StatelessWidget {
  const _ModeInfoCard({required this.mode});

  final PdfColorMode mode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = switch (mode) {
      PdfColorMode.color => const Color(0xFF0F766E),
      PdfColorMode.grayscale => const Color(0xFF475569),
      PdfColorMode.blackWhite => const Color(0xFF111827),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.picture_as_pdf, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  mode.label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  mode.description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF5C5A57),
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

class _FeatureBand extends StatelessWidget {
  const _FeatureBand();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F3EA),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: <Widget>[
          _MiniFeature(
            icon: Icons.filter_b_and_w,
            label: 'Filter ready',
            color: theme.colorScheme.primary,
          ),
          _MiniFeature(
            icon: Icons.photo_library_outlined,
            label: 'Gallery import',
            color: theme.colorScheme.secondary,
          ),
          _MiniFeature(
            icon: Icons.auto_delete_outlined,
            label: 'Auto cleanup',
            color: const Color(0xFF475569),
          ),
        ],
      ),
    );
  }
}

class _MiniFeature extends StatelessWidget {
  const _MiniFeature({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF312E2A),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.record,
    required this.onShare,
    required this.onDelete,
  });

  final DocumentRecord record;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.picture_as_pdf_rounded,
                    color: Color(0xFF0F766E),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'LovelyPDF ${record.createdAt.hour.toString().padLeft(2, '0')}:${record.createdAt.minute.toString().padLeft(2, '0')}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${record.pageCount} pages - ${record.mode.shortLabel} - ${formatBytes(record.fileSizeBytes)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF5C5A57),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC2410C).withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    formatRemaining(record.timeLeft),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: const Color(0xFFC2410C),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              record.pdfPath,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF7A7671),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _RecordChip(
                  icon: Icons.layers_outlined,
                  label: '${record.pageCount} pages',
                ),
                _RecordChip(icon: Icons.tune, label: record.mode.shortLabel),
                _RecordChip(
                  icon: Icons.sd_storage_outlined,
                  label: formatBytes(record.fileSizeBytes),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete now'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onShare,
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Share PDF'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
        child: Column(
          children: <Widget>[
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF0F766E).withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                size: 34,
                color: Color(0xFF0F766E),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'No PDF saved yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Press the camera button, tap to focus, capture each page, and then create the PDF. You can share it directly on WhatsApp or email.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF5C5A57),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegalCard extends StatelessWidget {
  const _LegalCard({required this.onPrivacyTap});

  final Future<void> Function() onPrivacyTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Privacy & Legal',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap the button below to view the Privacy Policy.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF5C5A57),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onPrivacyTap,
              icon: const Icon(Icons.privacy_tip_outlined),
              label: const Text('Open Privacy Policy'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordChip extends StatelessWidget {
  const _RecordChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F0E8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: const Color(0xFF5C5A57)),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroTag extends StatelessWidget {
  const _HeroTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x18FFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
