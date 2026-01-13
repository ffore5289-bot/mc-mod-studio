import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const McModStudioApp());
}

class McModStudioApp extends StatelessWidget {
  const McModStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MC Mod Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.green,
      ),
      home: const HomeScreen(),
    );
  }
}

class RpInfo {
  final String name;
  final String description;
  final String version;
  final String uuid;

  const RpInfo({
    required this.name,
    required this.description,
    required this.version,
    required this.uuid,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  RpInfo? _rpInfo;
  String _status = 'جاهز ✅';
  String? _extractedDirPath;

  Future<void> _pickRpZip() async {
    setState(() {
      _status = 'اختيار ملف...';
    });

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip', 'mcpack'],
      withData: true, // مهم على أندرويد لتفادي مشاكل الصلاحيات
    );

    if (result == null) {
      setState(() => _status = 'تم الإلغاء.');
      return;
    }

    final file = result.files.single;
    final bytes = file.bytes;
    final name = file.name.toLowerCase();

    if (bytes == null) {
      setState(() => _status = 'ما قدرت أقرأ الملف (bytes = null). جرّب ملف تاني.');
      return;
    }

    if (!name.endsWith('.zip') && !name.endsWith('.mcpack')) {
      setState(() => _status = 'اختار ملف .zip أو .mcpack فقط.');
      return;
    }

    try {
      setState(() => _status = 'فك الضغط وقراءة manifest...');

      // فكّ ضغط داخل temp/app cache
      final tempDir = await getTemporaryDirectory();
      final outDir = Directory(
        '${tempDir.path}/rp_extract_${DateTime.now().millisecondsSinceEpoch}',
      );
      await outDir.create(recursive: true);

      final archive = ZipDecoder().decodeBytes(bytes);

      // استخرج الملفات
      for (final f in archive) {
        final filename = f.name;

        // تجاهل المسارات الغريبة
        if (filename.contains('..')) continue;

        final outPath = '${outDir.path}/$filename';

        if (f.isFile) {
          final data = f.content as List<int>;
          final outFile = File(outPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(data, flush: true);
        } else {
          await Directory(outPath).create(recursive: true);
        }
      }

      // ابحث عن manifest.json داخل الأرشيف (أحيانًا يكون داخل مجلد)
      final manifestFile = _findManifestFile(outDir);
      if (manifestFile == null) {
        setState(() {
          _status = 'ما لقيت manifest.json داخل الـ RP.';
          _rpInfo = null;
          _extractedDirPath = outDir.path;
        });
        return;
      }

      final manifestText = await manifestFile.readAsString();
      final manifestJson = jsonDecode(manifestText) as Map<String, dynamic>;

      final header = (manifestJson['header'] as Map?)?.cast<String, dynamic>() ?? {};
      final modules = (manifestJson['modules'] as List?) ?? const [];

      final rpName = (header['name']?.toString().trim().isNotEmpty ?? false)
          ? header['name'].toString()
          : 'بدون اسم';

      final rpDesc = (header['description']?.toString().trim().isNotEmpty ?? false)
          ? header['description'].toString()
          : 'بدون وصف';

      final versionList = header['version'];
      final rpVersion = (versionList is List && versionList.isNotEmpty)
          ? versionList.join('.')
          : '?.?.?';

      // الـ uuid أحيانًا يكون بالـ header أو ضمن modules
      final headerUuid = header['uuid']?.toString();
      String rpUuid = (headerUuid != null && headerUuid.trim().isNotEmpty) ? headerUuid : '';

      if (rpUuid.isEmpty && modules.isNotEmpty) {
        final firstModule = modules.first;
        if (firstModule is Map && firstModule['uuid'] != null) {
          rpUuid = firstModule['uuid'].toString();
        }
      }
      if (rpUuid.isEmpty) rpUuid = 'غير معروف';

      setState(() {
        _rpInfo = RpInfo(
          name: rpName,
          description: rpDesc,
          version: rpVersion,
          uuid: rpUuid,
        );
        _extractedDirPath = outDir.path;
        _status = 'تم ✅ قرأنا manifest.json';
      });
    } catch (e) {
      setState(() {
        _status = 'فشل: $e';
        _rpInfo = null;
      });
    }
  }

  File? _findManifestFile(Directory root) {
    // أولًا جرّب جذر المجلد
    final direct = File('${root.path}/manifest.json');
    if (direct.existsSync()) return direct;

    // بعدها فتش كل الملفات
    final entities = root.listSync(recursive: true, followLinks: false);
    for (final e in entities) {
      if (e is File) {
        final lower = e.path.toLowerCase();
        if (lower.endsWith('${Platform.pathSeparator}manifest.json') ||
            lower.endsWith('/manifest.json') ||
            lower.endsWith('\\manifest.json')) {
          return e;
        }
      }
    }
    return null;
  }

  void _showSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('قريبًا: $feature')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MC Mod Studio'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _pickRpZip,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('اختيار RP'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showSoon('عرض Bat'),
                    icon: const Icon(Icons.remove_red_eye),
                    label: const Text('عرض Bat'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            _StatusCard(status: _status),

            const SizedBox(height: 14),

            if (_rpInfo != null) _RpInfoCard(info: _rpInfo!, extractedDirPath: _extractedDirPath),

            const Spacer(),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('3D Preview (قريبًا)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    SizedBox(height: 8),
                    Text('هاد مكان العارض ثلاثي الأبعاد. الخطوة الجاية: نقرأ ملفات الـ RP ونجهّز Three.js داخل WebView.'),
                    SizedBox(height: 6),
                    Text('WebView جاهز ✅ — رح نضيف Three.js بعدها.'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final String status;
  const _StatusCard({required this.status});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.info_outline),
            const SizedBox(width: 10),
            Expanded(child: Text(status)),
          ],
        ),
      ),
    );
  }
}

class _RpInfoCard extends StatelessWidget {
  final RpInfo info;
  final String? extractedDirPath;

  const _RpInfoCard({required this.info, required this.extractedDirPath});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('RP Info', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text('الاسم: ${info.name}'),
            const SizedBox(height: 6),
            Text('الوصف: ${info.description}'),
            const SizedBox(height: 6),
            Text('النسخة: ${info.version}'),
            const SizedBox(height: 6),
            Text('UUID: ${info.uuid}'),
            if (extractedDirPath != null) ...[
              const SizedBox(height: 10),
              Text(
                'Extracted: $extractedDirPath',
                style: TextStyle(color: Colors.black.withOpacity(0.55), fontSize: 12),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
