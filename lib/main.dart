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

class PackInfo {
  final String name;
  final String description;
  final String version;
  final String uuid;
  final String packType; // RP / BP / RP+BP

  const PackInfo({
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
  PackInfo? _info;
  String _status = 'جاهز ✅';
  String? _workDirPath;

  Future<void> _pickPackZip() async {
    setState(() {
      _status = 'اختيار ملف...';
      _info = null;
      _workDirPath = null;
    });

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip', 'mcpack', 'mcaddon'],
      withData: true, // مهم على أندرويد
    );

    if (result == null) {
      setState(() => _status = 'تم الإلغاء.');
      return;
    }

    final file = result.files.single;
    final bytes = file.bytes;
    final lowerName = file.name.toLowerCase();

    if (bytes == null) {
      setState(() => _status = 'ما قدرت أقرأ الملف (bytes = null). جرّب ملف تاني.');
      return;
    }

    if (!lowerName.endsWith('.zip') &&
        !lowerName.endsWith('.mcpack') &&
        !lowerName.endsWith('.mcaddon')) {
      setState(() => _status = 'اختار ملف .zip / .mcpack / .mcaddon فقط.');
      return;
    }

    try {
      setState(() => _status = 'فك الضغط...');

      // فك ضغط داخل temp
      final tempDir = await getTemporaryDirectory();
      final outDir = Directory(
        '${tempDir.path}/pack_extract_${DateTime.now().millisecondsSinceEpoch}',
      );
      await outDir.create(recursive: true);

      final archive = ZipDecoder().decodeBytes(bytes);

      for (final f in archive) {
        final filename = f.name;

        // حماية من مسارات خبيثة
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

      setState(() {
        _workDirPath = outDir.path;
        _status = 'قراءة manifest والتحقق...';
      });

      final manifestFile = _findManifestFile(outDir);
      if (manifestFile == null) {
        setState(() {
          _status = 'ما لقيت manifest.json داخل الملف. هذا غالبًا مو Pack Bedrock.';
          _info = null;
        });
        return;
      }

      final manifestText = await manifestFile.readAsString();
      final manifestJson = jsonDecode(manifestText);

      if (manifestJson is! Map<String, dynamic>) {
        setState(() {
          _status = 'manifest.json موجود، بس شكله مو JSON صحيح (مش Map).';
          _info = null;
        });
        return;
      }

      // ✅ تحقق قوي: header + modules + modules.type لازم يكون resources/data
      final header = (manifestJson['header'] as Map?)?.cast<String, dynamic>();
      final modules = (manifestJson['modules'] as List?);

      if (header == null || modules == null || modules.isEmpty) {
        setState(() {
          _status =
              'manifest.json موجود، لكن هذا مو Pack صحيح: (header/modules) ناقصين أو فاضيين.';
          _info = null;
        });
        return;
      }

      bool hasResources = false;
      bool hasData = false;

      for (final m in modules) {
        if (m is Map && m['type'] != null) {
          final t = m['type'].toString().toLowerCase().trim();
          if (t == 'resources') hasResources = true;
          if (t == 'data') hasData = true;
        }
      }

      if (!hasResources && !hasData) {
        setState(() {
          _status =
              'manifest موجود، لكن modules.type ليس resources ولا data → غالبًا مو Pack Bedrock.';
          _info = null;
        });
        return;
      }

      final info = _parseManifest(manifestJson, hasResources, hasData);

      setState(() {
        _info = info;
        _status = 'تم ✅ Pack صحيح — النوع: ${info.packType}';
      });
    } catch (e) {
      setState(() {
        _status = 'فشل: $e';
        _info = null;
      });
    }
  }

  File? _findManifestFile(Directory root) {
    final direct = File('${root.path}/manifest.json');
    if (direct.existsSync()) return direct;

    final entities = root.listSync(recursive: true, followLinks: false);
    for (final e in entities) {
      if (e is File) {
        final p = e.path.toLowerCase();
        if (p.endsWith('${Platform.pathSeparator}manifest.json') ||
            p.endsWith('/manifest.json') ||
            p.endsWith('\\manifest.json')) {
          return e;
        }
      }
    }
    return null;
  }

  PackInfo _parseManifest(
    Map<String, dynamic> manifestJson,
    bool hasResources,
    bool hasData,
  ) {
    final header =
        (manifestJson['header'] as Map).cast<String, dynamic>();
    final modules = (manifestJson['modules'] as List?) ?? const [];

    final name = (header['name']?.toString().trim().isNotEmpty ?? false)
        ? header['name'].toString()
        : 'بدون اسم';

    final desc =
        (header['description']?.toString().trim().isNotEmpty ?? false)
            ? header['description'].toString()
            : 'بدون وصف';

    final versionList = header['version'];
    final version = (versionList is List && versionList.isNotEmpty)
        ? versionList.join('.')
        : '?.?.?';

    String uuid = '';
    final headerUuid = header['uuid']?.toString();
    if (headerUuid != null && headerUuid.trim().isNotEmpty) {
      uuid = headerUuid.trim();
    }

    if (uuid.isEmpty && modules.isNotEmpty) {
      final first = modules.first;
      if (first is Map && first['uuid'] != null) {
        uuid = first['uuid'].toString();
      }
    }
    if (uuid.isEmpty) uuid = 'غير معروف';

    String packType = 'Unknown';
    if (hasResources && !hasData) packType = 'Resource Pack (RP)';
    if (hasData && !hasResources) packType = 'Behavior Pack (BP)';
    if (hasResources && hasData) packType = 'Both (RP+BP)';

    return PackInfo(
      name: name,
      description: desc,
      version: version,
      uuid: uuid,
      packType: packType,
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
                    onPressed: _pickPackZip,
                    icon: const Icon(Icons.archive),
                    label: const Text('اختيار Pack (ZIP/MCPACK)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            _StatusCard(status: _status),

            const SizedBox(height: 14),

            if (_info != null) _PackInfoCard(info: _info!, workDirPath: _workDirPath),

            const Spacer(),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'الخطوة الجاية',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 8),
                    Text('بعد ما نثبت اكتشاف الـ Pack، بنضيف: قائمة الملفات ثم entities ثم 3D preview.'),
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

class _PackInfoCard extends StatelessWidget {
  final PackInfo info;
  final String? workDirPath;

  const _PackInfoCard({required this.info, required this.workDirPath});

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
            if (workDirPath != null) ...[
              const SizedBox(height: 10),
              Text(
                'WorkDir: $workDirPath',
                style: TextStyle(color: Colors.black.withOpacity(0.55), fontSize: 12),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
