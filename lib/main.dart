import 'dart:convert';
import 'dart:io';

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
  final String packType; // Resource Pack / Behavior Pack / Both / Unknown

  const RpInfo({
    required this.name,
    required this.description,
    required this.version,
    required this.uuid,
    required this.packType,
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

  // -----------------------
  // Helpers
  // -----------------------

  File? _findManifestFile(Directory root) {
    // Try root first
    final direct = File('${root.path}/manifest.json');
    if (direct.existsSync()) return direct;

    // Search recursively
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

  String _detectPackType(List modules) {
    bool hasResources = false;
    bool hasData = false;

    for (final m in modules) {
      if (m is Map && m['type'] != null) {
        final t = m['type'].toString().toLowerCase().trim();
        if (t == 'resources') hasResources = true;
        if (t == 'data') hasData = true;
      }
    }

    if (hasResources && !hasData) return 'Resource Pack (RP)';
    if (hasData && !hasResources) return 'Behavior Pack (BP)';
    if (hasResources && hasData) return 'Both (RP+BP)';
    return 'Unknown';
  }

  RpInfo _parseManifest(Map<String, dynamic> manifestJson) {
    final header =
        (manifestJson['header'] as Map?)?.cast<String, dynamic>() ?? {};
    final modules = (manifestJson['modules'] as List?) ?? const [];

    final rpName = (header['name']?.toString().trim().isNotEmpty ?? false)
        ? header['name'].toString()
        : 'بدون اسم';

    final rpDesc =
        (header['description']?.toString().trim().isNotEmpty ?? false)
            ? header['description'].toString()
            : 'بدون وصف';

    final versionList = header['version'];
    final rpVersion = (versionList is List && versionList.isNotEmpty)
        ? versionList.join('.')
        : '?.?.?';

    // uuid (header or first module)
    final headerUuid = header['uuid']?.toString();
    String rpUuid =
        (headerUuid != null && headerUuid.trim().isNotEmpty) ? headerUuid : '';

    if (rpUuid.isEmpty && modules.isNotEmpty) {
      final firstModule = modules.first;
      if (firstModule is Map && firstModule['uuid'] != null) {
        rpUuid = firstModule['uuid'].toString();
      }
    }
    if (rpUuid.isEmpty) rpUuid = 'غير معروف';

    final packType = _detectPackType(modules);

    return RpInfo(
      name: rpName,
      description: rpDesc,
      version: rpVersion,
      uuid: rpUuid,
      packType: packType,
    );
  }

  void _showSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('قريبًا: $feature')),
    );
  }

  // -----------------------
  // Pick ZIP / MCPACK
  // -----------------------
  Future<void> _pickRpZip() async {
    setState(() {
      _status = 'اختيار ملف...';
      _rpInfo = null;
      _extractedDirPath = null;
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

      final tempDir = await getTemporaryDirectory();
      final outDir = Directory(
        '${tempDir.path}/rp_extract_${DateTime.now().millisecondsSinceEpoch}',
      );
      await outDir.create(recursive: true);

      final archive = ZipDecoder().decodeBytes(bytes);

      for (final f in archive) {
        final filename = f.name;

        // avoid weird paths
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

      final manifestFile = _findManifestFile(outDir);
      if (manifestFile == null) {
        setState(() {
          _status = 'ما لقيت manifest.json داخل الملف. (ممكن مو Pack صحيح)';
          _rpInfo = null;
          _extractedDirPath = outDir.path;
        });
        return;
      }

      final manifestText = await manifestFile.readAsString();
      final manifestJson = jsonDecode(manifestText) as Map<String, dynamic>;
      final info = _parseManifest(manifestJson);

      setState(() {
        _rpInfo = info;
        _extractedDirPath = outDir.path;
        _status = 'تم ✅ قرأنا manifest.json — النوع: ${info.packType}';
      });
    } catch (e) {
      setState(() {
        _status = 'فشل: $e';
        _rpInfo = null;
      });
    }
  }

  // -----------------------
  // Pick Folder
  // -----------------------
  Future<void> _pickRpFolder() async {
    setState(() {
      _status = 'اختيار مجلد...';
      _rpInfo = null;
      _extractedDirPath = null;
    });

    final dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath == null) {
      setState(() => _status = 'تم الإلغاء.');
      return;
    }

    try {
      setState(() => _status = 'قراءة manifest من المجلد...');

      final root = Directory(dirPath);
      final manifestFile = _findManifestFile(root);

      if (manifestFile == null) {
        setState(() {
          _status = 'ما لقيت manifest.json داخل المجلد.';
          _rpInfo = null;
          _extractedDirPath = dirPath;
        });
        return;
      }

      final manifestText = await manifestFile.readAsString();
      final manifestJson = jsonDecode(manifestText) as Map<String, dynamic>;
      final info = _parseManifest(manifestJson);

      setState(() {
        _rpInfo = info;
        _extractedDirPath = dirPath;
        _status = 'تم ✅ قرأنا manifest — النوع: ${info.packType}';
      });
    } catch (e) {
      setState(() {
        _status = 'فشل: $e';
        _rpInfo = null;
      });
    }
  }

  // -----------------------
  // UI
  // -----------------------
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
                    icon: const Icon(Icons.archive),
                    label: const Text('اختيار RP (ZIP)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _pickRpFolder,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('اختيار RP (مجلد)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              children: [
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
            if (_rpInfo != null)
              _RpInfoCard(info: _rpInfo!, extractedDirPath: _extractedDirPath),

            const Spacer(),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      '3D Preview (قريبًا)',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 8),
                    Text(
                        'هاد مكان العارض ثلاثي الأبعاد. الخطوة الجاية: نقرأ ملفات الـ RP ونجهّز Three.js داخل WebView.'),
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
            const Text('Pack Info',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text('النوع: ${info.packType}'),
            const SizedBox(height: 6),
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
                'Path: $extractedDirPath',
                style: TextStyle(
                    color: Colors.black.withOpacity(0.55), fontSize: 12),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
