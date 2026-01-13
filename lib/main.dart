import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF111111))
      ..loadHtmlString(_viewerHtml);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MC Mod Studio'),
      ),
      body: Column(
        children: [
          // Top controls (placeholder)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      // Later: open folder picker + parse RP
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('قريباً: اختيار resource_pack')),
                      );
                    },
                    icon: const Icon(Icons.folder_open),
                    label: const Text('اختيار RP'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // Later: load Bat model + texture
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('قريباً: عرض Bat 3D')),
                      );
                    },
                    icon: const Icon(Icons.visibility),
                    label: const Text('عرض Bat'),
                  ),
                ),
              ],
            ),
          ),

          // 3D Preview area (WebView)
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: WebViewWidget(controller: _controller),
            ),
          ),
        ],
      ),
    );
  }
}

const String _viewerHtml = r'''
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>MC Mod Studio Viewer</title>
  <style>
    html, body { margin:0; padding:0; height:100%; background:#111; overflow:hidden; }
    #wrap { position:fixed; inset:0; display:flex; align-items:center; justify-content:center; color:#ddd; font-family:system-ui; }
    .card { max-width: 420px; padding: 18px 16px; border:1px solid #2a2a2a; border-radius:16px; background:#161616; }
    .hint { opacity:0.85; line-height:1.6; }
    .small { font-size: 12px; opacity:0.7; margin-top:10px; }
  </style>
</head>
<body>
  <div id="wrap">
    <div class="card">
      <h3 style="margin:0 0 8px 0;">3D Preview (قريباً)</h3>
      <div class="hint">
        هاد مكان العارض ثلاثي الأبعاد.<br/>
        بالخطوة الجاية رح نخلي التطبيق يقرأ ملفات <b>Bat v2</b> من resource_pack ويعرضها هون.
      </div>
      <div class="small">WebView جاهز ✅ — Three.js رح نضيفه بعدها.</div>
    </div>
  </div>
</body>
</html>
''';
