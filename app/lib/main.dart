import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'models/document_record.dart';
import 'services/ad_service.dart';
import 'services/background_tasks.dart';
import 'services/document_store.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AdService.instance.initialize();
  await BackgroundTasks.initialize();
  await DocumentStore.instance.cleanupExpired();
  runApp(const DocPdfApp());
}

class DocPdfApp extends StatelessWidget {
  const DocPdfApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F766E),
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'LovelyPDF',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: baseScheme.copyWith(
          primary: const Color(0xFF0F766E),
          secondary: const Color(0xFFC2410C),
          surface: const Color(0xFFFFFBF6),
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F1E8),
        textTheme: GoogleFonts.manropeTextTheme(),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            textStyle: WidgetStatePropertyAll(
              GoogleFonts.manrope(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0xFFE8E0D3)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle: GoogleFonts.manrope(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
      home: const HomeScreen(defaultMode: PdfColorMode.color),
    );
  }
}
