// ===== BLOCK 1: imports & main =====
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;

// ===== UTIL: color tweak (used by _HomeWheelPainter) =====
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // ✅ Web では広告SDKを一切触らない
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    await MobileAds.instance.initialize();
    // Interstitials.preload(); // 使うならここで
  }

  runApp(const RouletteApp());
}

Color _shade(
    Color c, {
      double lightnessDelta = -0.08,
    }) {
  final hsl = HSLColor.fromColor(c);
  final l = (hsl.lightness + lightnessDelta).clamp(0.0, 1.0);
  return hsl.withLightness(l).toColor();
}

class RouletteApp extends StatelessWidget {
  const RouletteApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 明るめの水色
    const mainBlue = Color(0xFF4FC3F7);

    // fromSeed で作ってから「primary だけはこの色！」と上書き
    final base = ColorScheme.fromSeed(
      seedColor: mainBlue,
      brightness: Brightness.light,
    );

    final scheme = base.copyWith(
      primary: mainBlue,
      primaryContainer: mainBlue.withOpacity(0.18),
      secondary: mainBlue,
      secondaryContainer: mainBlue.withOpacity(0.12),
    );

    return MaterialApp(
      title: 'ルーレットをつくろう',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: scheme.background,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: scheme.primary,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: scheme.primary,
            side: BorderSide(
              color: scheme.primary,
              width: 1.4,
            ),
          ),
        ),
      ),
      home: const RootPage(),
    );
  }
}

// ===== BLOCK 2: models & storage =====

class RouletteItem {
  final String name;
  final int weight;
  final int color;

  RouletteItem({
    required this.name,
    required this.weight,
    required this.color,
  });

  Map<String, dynamic> toJson() => {
    "name": name,
    "weight": weight,
    "color": color,
  };

  static RouletteItem fromJson(Map<String, dynamic> j) => RouletteItem(
    name: j["name"],
    weight: j["weight"],
    color: j["color"],
  );
}

class RouletteDef {
  final String id;
  final String title;
  final List<RouletteItem> items;
  final String createdAt;
  final String updatedAt;
  final String? lastUsedAt;
  final bool isPinned;

  RouletteDef({
    required this.id,
    required this.title,
    required this.items,
    required this.createdAt,
    required this.updatedAt,
    this.lastUsedAt,
    this.isPinned = false,
  });

  Map<String, dynamic> toJson() => {
    "id": id,
    "title": title,
    "items": items.map((e) => e.toJson()).toList(),
    "createdAt": createdAt,
    "updatedAt": updatedAt,
    "lastUsedAt": lastUsedAt,
    "isPinned": isPinned,
  };

  static RouletteDef fromJson(Map<String, dynamic> j) => RouletteDef(
    id: j["id"],
    title: j["title"],
    items: (j["items"] as List)
        .map((e) => RouletteItem.fromJson(
      Map<String, dynamic>.from(e),
    ))
        .toList(),
    createdAt: j["createdAt"],
    updatedAt: j["updatedAt"],
    lastUsedAt: j["lastUsedAt"],
    isPinned: j["isPinned"] ?? false,
  );
}

// ルーレット時間モード
enum RouletteTimeMode {
  short, // 短い
  normal, // 普通
  long, // 長い
}

// アプリ全体の設定
class AppSettings {
  final bool privateMode; // プライベートモード
  final bool quickResult; // 結果をすぐ表示
  final RouletteTimeMode timeMode; // ルーレット時間

  const AppSettings({
    this.privateMode = false,
    this.quickResult = false,
    this.timeMode = RouletteTimeMode.normal,
  });

  AppSettings copyWith({
    bool? privateMode,
    bool? quickResult,
    RouletteTimeMode? timeMode,
  }) {
    return AppSettings(
      privateMode: privateMode ?? this.privateMode,
      quickResult: quickResult ?? this.quickResult,
      timeMode: timeMode ?? this.timeMode,
    );
  }

  Map<String, dynamic> toJson() => {
    'privateMode': privateMode,
    'quickResult': quickResult,
    'timeMode': timeMode.name, // "short" / "normal" / "long"
  };

  static AppSettings fromJson(Map<String, dynamic> j) {
    final modeStr = j['timeMode'] as String?;
    RouletteTimeMode mode;

    switch (modeStr) {
      case 'short':
        mode = RouletteTimeMode.short;
        break;
      case 'long':
        mode = RouletteTimeMode.long;
        break;
      default:
        mode = RouletteTimeMode.normal;
    }

    return AppSettings(
      privateMode: j['privateMode'] ?? false,
      quickResult: j['quickResult'] ?? false,
      timeMode: mode,
    );
  }
}

class Store {
  static const _kLast = "last_roulette";
  static const _kSaved = "saved_roulettes";
  static const _kSettings = "app_settings";
  static const _kSeededDefault = "seeded_default_omikuji";

  // デフォルトおみくじを投入済みか？
  static Future<bool> hasSeededDefault() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kSeededDefault) ?? false;
  }

  // デフォルトおみくじを投入済みフラグを立てる
  static Future<void> setSeededDefault() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kSeededDefault, true);
  }

  // ===== 前回のルーレット =====
  static Future<Map<String, dynamic>?> loadLast() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kLast);
    return s == null ? null : jsonDecode(s);
  }

  // ★ ここから：デフォルトの「今日の運勢」ルーレット
  static RouletteDef defaultOmikuji() {
    final now = DateTime.now().toIso8601String();
    return RouletteDef(
      id: 'default_omikuji',
      title: '🍀 今日の運勢',
      items: [
        RouletteItem(name: '大吉', weight: 6, color: Colors.redAccent.value),
        RouletteItem(name: '中吉', weight: 5, color: Colors.orangeAccent.value),
        RouletteItem(name: '小吉', weight: 5, color: Colors.yellow.shade700.value),
        RouletteItem(name: '吉',   weight: 8, color: Colors.lightGreen.shade600.value),
        RouletteItem(name: '末吉', weight: 3, color: Colors.blueAccent.value),
        RouletteItem(name: '凶',   weight: 1, color: Colors.grey.shade700.value),
      ],
      createdAt: now,
      updatedAt: now,
      lastUsedAt: null,
      isPinned: true,
    );
  }

  // ★ プライベートモード中は last を保存しない
  static Future<void> saveLast(RouletteDef def) async {
    final p = await SharedPreferences.getInstance();

    final settingsStr = p.getString(_kSettings);
    if (settingsStr != null) {
      final st = AppSettings.fromJson(
        Map<String, dynamic>.from(jsonDecode(settingsStr)),
      );
      if (st.privateMode) {
        // プライベートモード中なので「前回のルーレット」は更新しない
        return;
      }
    }

    await p.setString(_kLast, jsonEncode(def.toJson()));
  }

  // ===== 保存済みルーレット =====
  static Future<List<RouletteDef>> loadSaved() async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_kSaved) ?? [];

    return list
        .map(
          (s) => RouletteDef.fromJson(
        Map<String, dynamic>.from(jsonDecode(s)),
      ),
    )
        .toList();
  }

  static Future<void> saveSaved(List<RouletteDef> defs) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
      _kSaved,
      defs.map((d) => jsonEncode(d.toJson())).toList(),
    );
  }

  // ===== アプリ設定 =====
  static Future<AppSettings> loadSettings() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kSettings);
    if (s == null) return const AppSettings();

    return AppSettings.fromJson(
      Map<String, dynamic>.from(jsonDecode(s)),
    );
  }

  static Future<void> saveSettings(AppSettings settings) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSettings, jsonEncode(settings.toJson()));
  }
}

// ===== BLOCK 2.5: home wheel widget =====

class _HomeWheel extends StatefulWidget {
  final double idleSpeed;
  final double maxSpeed;
  final VoidCallback? onTap;

  const _HomeWheel({
    super.key,
    required this.idleSpeed,
    required this.maxSpeed,
    this.onTap,
  });

  @override
  State<_HomeWheel> createState() => _HomeWheelState();
}

class _HomeWheelState extends State<_HomeWheel>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _ticker;
  double _angle = 0.0;
  double _speed;
  ui.Image? _image;
  Size? _imgSize;
  bool _building = false;

  _HomeWheelState() : _speed = 0.01;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _speed = widget.idleSpeed;

    // 画面全体を rebuild しないよう、ホイールだけを動かす ticker
    _ticker = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        // ここで setState するのは このウィジェットだけ
        _angle += _speed;
        if (_angle > pi * 2) _angle -= pi * 2;
        _speed *= 0.97;
        if (_speed < widget.idleSpeed) _speed = widget.idleSpeed;
        setState(() {}); // ← 再描画範囲は _HomeWheel 内だけ
      })
      ..repeat(
        min: 0,
        max: 1,
        period: const Duration(milliseconds: 16),
      ); // 約60fps
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _image?.dispose();
    super.dispose();
  }

  // アプリが非表示の間は止める
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _ticker.stop();
    } else if (state == AppLifecycleState.resumed) {
      _ticker.repeat(
        min: 0,
        max: 1,
        period: const Duration(milliseconds: 22),
      );
    }
  }

  void _impulse() {
    widget.onTap?.call();
    _speed =
        (_speed + 0.25).clamp(widget.idleSpeed, widget.maxSpeed);
  }

  Future<void> _ensureImage(Size size) async {
    if (_building) return;
    if (_image != null &&
        _imgSize != null &&
        (size.width - _imgSize!.width).abs() < 1 &&
        (size.height - _imgSize!.height).abs() < 1) {
      return;
    }

    _building = true;
    try {
      // 端末負荷が高い時は縮小係数を上げて描画負荷をさらに下げられる
      final dpr = ui.window.devicePixelRatio;
      final scale = (dpr >= 3.0) ? 0.75 : 1.0; // ★ 高密度端末で少し落とす

      final w =
      (size.width * dpr * scale).clamp(128, 2048).toInt();
      final h =
      (size.height * dpr * scale).clamp(128, 2048).toInt();

      final rec = ui.PictureRecorder();
      final c = Canvas(
        rec,
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      );

      c.scale(dpr * scale, dpr * scale);

      // ここは見た目そのまま：一度だけ描画（画像化）
      final painter = _HomeWheelPainter(simplifyShadow: true); // ← 影を軽量化
      painter.paint(c, size);
      final pic = rec.endRecording();
      final img = await pic.toImage(w, h);

      _image?.dispose();

      if (mounted) {
        setState(() {
          _image = img;
          _imgSize = size;
        });
      } else {
        img.dispose();
      }
    } finally {
      _building = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _impulse,
      child: LayoutBuilder(
        builder: (_, c) {
          final sz = Size(c.maxWidth, c.maxHeight);
          _ensureImage(sz);

          if (_image == null) {
            // 画像生成中はフォールバック（1フレーム）
            return CustomPaint(
              painter: _HomeWheelPainter(simplifyShadow: true),
            );
          }

          return CustomPaint(
            painter: _ImageWheelPainter(
              image: _image!,
              angle: _angle,
            ),
          );
        },
      ),
    );
  }
}

// ===== BLOCK 3A: home screen (タイトル画面) =====

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  AppSettings _settings = const AppSettings();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await Store.loadSettings();
    if (!mounted) return;
    setState(() {
      _settings = s;
      _loading = false;
    });
  }

  Future<void> _update(AppSettings newSettings) async {
    setState(() {
      _settings = newSettings;
    });
    await Store.saveSettings(newSettings);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('設定')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: SafeArea(
        child: ListView(
          children: [
            const SizedBox(height: 4),

            // プライベートモード
            SwitchListTile.adaptive(
              title: const Text('プライベートモード'),
              subtitle: const Text(
                'オンにしている間に回したルーレットは「前回のルーレット」に保存されません。',
              ),
              value: _settings.privateMode,
              onChanged: (v) => _update(_settings.copyWith(privateMode: v)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),

            const Divider(height: 1),

            // 結果をすぐ表示（シンプルに一行）
            SwitchListTile.adaptive(
              title: const Text('結果をすぐ表示'),
              value: _settings.quickResult,
              onChanged: (v) => _update(_settings.copyWith(quickResult: v)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),

            const Divider(height: 12, thickness: 0.6),

            // ルーレット時間ラベル
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'ルーレット時間',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),

            // ルーレット時間ラジオ
            RadioListTile<RouletteTimeMode>(
              title: const Text('短い'),
              value: RouletteTimeMode.short,
              groupValue: _settings.timeMode,
              onChanged: (v) {
                if (v != null) _update(_settings.copyWith(timeMode: v));
              },
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            ),
            RadioListTile<RouletteTimeMode>(
              title: const Text('普通'),
              value: RouletteTimeMode.normal,
              groupValue: _settings.timeMode,
              onChanged: (v) {
                if (v != null) _update(_settings.copyWith(timeMode: v));
              },
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            ),
            RadioListTile<RouletteTimeMode>(
              title: const Text('長い'),
              value: RouletteTimeMode.long,
              groupValue: _settings.timeMode,
              onChanged: (v) {
                if (v != null) _update(_settings.copyWith(timeMode: v));
              },
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            ),

            const SizedBox(height: 24), // 下が詰まりすぎないよう余白
          ],
        ),
      ),

      // 設定画面にもバナー
      bottomNavigationBar: const BottomBanner(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
      ),
    );
  }
}

// ▼ ランダム表示するサブ文言リスト（好きなだけ追加OK）
const List<String> kSubMessages = [
  "自由にルーレットをつくれるアプリ",
  "迷った時はこれで決めよう",
  "ぐるぐる回して楽しく決めよう",
  "ぱっと作って、すぐ回せる",
  "あなた好みのルーレットが作れる",
  "今日の運勢も決めちゃおう？",
  "飽きないカラフルルーレット",
  "作るのも回すのもサクッと簡単",
  "日常の些細な悩みに使えます",
  "あらゆる選択をルーレットに",
];


class _RootPageState extends State<RootPage> {
  RouletteDef? _last;

  late final String _subtitle;

  @override
  void initState() {
    super.initState();
    // ▼ ランダムで1つ選ぶ
    _subtitle = (List.of(kSubMessages)..shuffle()).first;
    _loadLast();
  }

  Future<void> _loadLast() async {
    final lastJson = await Store.loadLast();
    if (!mounted) return;
    setState(() {
      _last =
      lastJson == null ? null : RouletteDef.fromJson(lastJson);
    });
  }

  void _goCreate() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QuickInputPage()),
    ).then((_) => _loadLast());   // ★ 追加
  }

  void _goLast() {
    if (_last == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('前回のルーレットはまだありません'),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuickInputPage(initial: _last!),
      ),
    );
  }

  void _goSaved() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SavedListPage()),
    ).then((_) => _loadLast());   // ★ 追加
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 120, // ← タイトルの上下余白UP
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: true,

        title: Column(
          children: [
            const SizedBox(height: 10), // ← タイトルを少し下げる調整
            const Text(
              'ルーレットをつくろう',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _subtitle,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black54,
              ),
            ),
          ],
        ),

        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 12),
            // ↑ アイコンの位置を下げて、タイトルとの高さバランスを揃える
            child: IconButton(
              icon: const Icon(Icons.settings_outlined),
              iconSize: 28,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
              },
            ),
          ),
        ],
      ),



      // ← ここから body
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: _HomeWheel(
                      idleSpeed: 0.01,
                      maxSpeed: 0.70,
                      onTap: () {},
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 80,
                child: ElevatedButton(
                  onPressed: _goCreate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    elevation: 10,
                    shadowColor:
                    Colors.black.withOpacity(0.30),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  child: const Text('ルーレットを作る'),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Material(
                      elevation: 2,
                      borderRadius: BorderRadius.circular(14),
                      color: Colors.transparent,
                      child: OutlinedButton(
                        onPressed: _goLast,
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          padding:
                          const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                            BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('前回のルーレット'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Material(
                      elevation: 2,
                      borderRadius: BorderRadius.circular(14),
                      color: Colors.transparent,
                      child: OutlinedButton(
                        onPressed: _goSaved,
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          padding:
                          const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                            BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('保存済みルーレット'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      // ← ここが Scaffold の bottomNavigationBar
      bottomNavigationBar: const BottomBanner(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
      ),
    );
  }
}

/// タイトル画面用のルーレット描画（セグメント＋中心の白丸）
class _HomeWheelPainter extends CustomPainter {
  final bool simplifyShadow;

  _HomeWheelPainter({this.simplifyShadow = false});

  @override
  void paint(Canvas canvas, Size size) {
    final center =
    Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide * 0.45;
    final rect = Rect.fromCircle(
      center: center,
      radius: r,
    );

    // 落ち影（軽量化オプション）
    if (simplifyShadow) {
      final sp = Paint()..color = Colors.black12;
      canvas.drawCircle(
        center + const Offset(0, 6),
        r * 0.94,
        sp,
      );
    } else {
      final sp = Paint()
        ..color = Colors.black.withOpacity(0.18)
        ..maskFilter = const ui.MaskFilter.blur(
          ui.BlurStyle.normal,
          18,
        );
      canvas.drawCircle(
        center + const Offset(0, 8),
        r * 0.94,
        sp,
      );
    }

    // セグメント色
    final colors = <Color>[
      Colors.redAccent,
      Colors.orangeAccent,
      Colors.yellow.shade600,
      Colors.lightGreenAccent.shade400,
      Colors.lightBlueAccent,
      Colors.purpleAccent,
    ];

    double start = -pi / 2;
    final sweep = 2 * pi / colors.length;
    final segPaint = Paint()..style = PaintingStyle.fill;

    for (final c in colors) {
      segPaint.shader = RadialGradient(
        colors: [
          _shade(c, lightnessDelta: -0.08),
          c,
          _shade(c, lightnessDelta: 0.06),
        ],
        stops: const [0.0, 0.7, 1.0],
        center: const Alignment(0.0, -0.2),
        radius: 1.0,
      ).createShader(rect);

      canvas.drawArc(rect, start, sweep, true, segPaint);
      start += sweep;
    }

    // 外周リム
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..shader = SweepGradient(
        startAngle: -pi / 2,
        endAngle: 3 * pi / 2,
        colors: [
          Colors.white.withOpacity(0.7),
          Colors.white.withOpacity(0.0),
          Colors.black.withOpacity(0.12),
          Colors.white.withOpacity(0.4),
        ],
      ).createShader(rect);
    canvas.drawCircle(center, r - 1, rimPaint);

    // 中心の白丸
    final hubR = r * 0.45;
    final hubRect = Rect.fromCircle(
      center: center,
      radius: hubR,
    );
    final hubPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white,
          Colors.grey.shade200,
        ],
        center: const Alignment(-0.15, -0.15),
        radius: 1.0,
      ).createShader(hubRect);
    canvas.drawCircle(center, hubR, hubPaint);

    final hubStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.black.withOpacity(0.10);
    canvas.drawCircle(center, hubR, hubStroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) =>
      false;
}

// ===== BLOCK 3B: quick input page =====

class QuickInputPage extends StatefulWidget {
  final RouletteDef? initial;

  const QuickInputPage({super.key, this.initial});

  @override
  State<QuickInputPage> createState() =>
      _QuickInputPageState();
}

class _QuickInputPageState extends State<QuickInputPage> {
  // ★ 追加：最大項目数と乱数
  static const int _maxItems = 30;
  final Random _rand = Random();

  final List<TextEditingController> _nameCtls = [];
  final List<TextEditingController> _weightCtls = [];
  final List<int> _colors = [];


  @override
  void initState() {
    super.initState();

    if (widget.initial != null) {
      for (final it in widget.initial!.items) {
        _nameCtls.add(
          TextEditingController(text: it.name),
        );
        _weightCtls.add(
          TextEditingController(text: it.weight.toString()),
        );
        _colors.add(it.color);
      }
      if (_nameCtls.length < 2) _ensureMinRows();
    } else {
      _ensureMinRows();
    }
  }

  void _ensureMinRows() {
    while (_nameCtls.length < 2) {
      _addRow();
    }
  }

  void _addRow({
    String name = '',
    int weight = 1,
    int? color,
  }) {
    // ★ ここで最大数チェック
    if (_nameCtls.length >= _maxItems) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('項目は30個まで追加できます'),
        ),
      );
      return;
    }

    setState(() {
      _nameCtls.add(
        TextEditingController(text: name),
      );
      _weightCtls.add(
        TextEditingController(text: weight.toString()),
      );

      // ★ 色が指定されている（保存済み読み込みなど）ときはそのまま使う
      if (color != null) {
        _colors.add(color);
        return;
      }

      // ★ 新しく作るとき用：明るめパレットからランダムに選ぶ
      final palette = <Color>[
        const Color(0xFFFF6B6B), // ちょい暗めレッド
        const Color(0xFFFFA94D), // オレンジ
        const Color(0xFFFFD93D), // 濃いめイエロー（ギリ白文字OK）
        const Color(0xFF6BCB77), // グリーン
        const Color(0xFF4D96FF), // ブルー（薄い水色より濃く）
        const Color(0xFF9D4EDD), // パープル
        const Color(0xFFE056FD), // ピンク寄りパープル
        const Color(0xFFFB6F92), // ピンク
        const Color(0xFFFF7B54), // 赤寄りオレンジ
        const Color(0xFF2D9CDB), // さらに濃いブルー
      ];





      // すでに使っている色はできるだけ避ける
      final used = _colors.toSet();
      final available = palette
          .where((c) => !used.contains(c.value))
          .toList();

      final picked = (available.isNotEmpty
          ? available[_rand.nextInt(available.length)]
          : palette[_rand.nextInt(palette.length)]);

      _colors.add(picked.value);
    });
  }


  void _removeRow(int index) {
    if (_nameCtls.length <= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('項目は最低2つ必要です'),
        ),
      );
      return;
    }

    setState(() {
      _nameCtls[index].dispose();
      _weightCtls[index].dispose();
      _nameCtls.removeAt(index);
      _weightCtls.removeAt(index);
      _colors.removeAt(index);
    });
  }

  @override
  void dispose() {
    for (final c in _nameCtls) {
      c.dispose();
    }
    for (final c in _weightCtls) {
      c.dispose();
    }
    super.dispose();
  }

  int _parseWeight(TextEditingController c) {
    final v = int.tryParse(c.text.trim()) ?? 1;
    return v.clamp(1, 100);
  }

  Future<void> _onSpin() async {
    final List<RouletteItem> items = [];

    for (int i = 0; i < _nameCtls.length; i++) {
      final name = _nameCtls[i].text.trim();
      if (name.isEmpty) continue;

      final w = _parseWeight(_weightCtls[i]);
      final color = _colors[i];

      items.add(
        RouletteItem(
          name: name,
          weight: w,
          color: color,
        ),
      );
    }

    if (items.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('項目を2つ以上入力してください'),
        ),
      );
      return;
    }

    final now = DateTime.now().toIso8601String();

    final def = RouletteDef(
      id: UniqueKey().toString(),
      title: '未保存ルーレット',
      items: items,
      createdAt: now,
      updatedAt: now,
      lastUsedAt: null,
      isPinned: false,
    );

    // 設定読み込み（クイック結果用）
    final settings = await Store.loadSettings();

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SpinPage(
          def: def,
          quickResult: settings.quickResult,
        ),
      ),
    );
  }

  InputDecoration _fieldDec(
      BuildContext context,
      String label,
      ) {
    final cs = Theme.of(context).colorScheme;

    return InputDecoration(
      labelText: label,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 12,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(
          width: 1.4,
          color: Color(0xFFDBDEE3),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(
          width: 1.4,
          color: Color(0xFFDBDEE3),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          width: 2,
          color: cs.primary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('ルーレットを作る')),
      body: SafeArea(
        child: Padding(
          padding:
          const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 140),
            itemCount: _nameCtls.length,
            itemBuilder: (context, index) {
              final canDelete = _nameCtls.length > 2;
              return Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 6,
                ),
                child: Row(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _nameCtls[index],
                        maxLength: 30,
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.black87,
                        ),
                        decoration: _fieldDec(
                          context,
                          '項目名',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 88,
                      child: TextField(
                        controller: _weightCtls[index],
                        textAlign: TextAlign.center,
                        keyboardType:
                        TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter
                              .digitsOnly,
                        ],
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.black87,
                        ),
                        decoration: _fieldDec(
                          context,
                          '比率',
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: '削除',
                      icon: const Icon(
                        Icons.delete_outline,
                      ),
                      onPressed: canDelete
                          ? () => _removeRow(index)
                          : null,
                      color: canDelete
                          ? Colors.red.shade400
                          : Colors.black26,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 🔻 広告（ここで左右16のパディングを指定）
            const BottomBanner(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            ),

            const SizedBox(height: 10),

            // 🔻 「項目を追加」ボタン（広告とは別に余白をつける）
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: SizedBox(
                height: 52,
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: _addRow,
                  icon: const Icon(Icons.add),
                  label: const Text('項目を追加'),
                  style: FilledButton.styleFrom(
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                    ),
                    backgroundColor: cs.secondaryContainer,
                    foregroundColor: cs.onSecondaryContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // 🔻 「ルーレットを回す」ボタン
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                height: 72,
                width: double.infinity,
                child: FilledButton(
                  onPressed: _onSpin,
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  child: const Text('ルーレットを回す'),
                ),
              ),
            ),
          ],
        ),
      ),

    );
  }
}

// ===== BLOCK 3C: saved list page =====

class SavedListPage extends StatefulWidget {
  const SavedListPage({super.key});

  @override
  State<SavedListPage> createState() =>
      _SavedListPageState();
}

class _SavedListPageState extends State<SavedListPage> {
  List<RouletteDef> _saved = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final seeded = await Store.hasSeededDefault(); // ★ 追加
    var list = await Store.loadSaved();

    // ★ まだ seed してなくて、保存が0件のときだけ運勢ルーレットを入れる
    if (!seeded && list.isEmpty) {
      final def = Store.defaultOmikuji();  // ← ここを修正
      list = [def];
      await Store.saveSaved(list);
      await Store.setSeededDefault();      // 二度と自動追加しない
    }

    list.sort((a, b) {
      final pin = (b.isPinned ? 1 : 0) - (a.isPinned ? 1 : 0);
      if (pin != 0) return pin;
      return (b.lastUsedAt ?? '').compareTo(a.lastUsedAt ?? '');
    });

    setState(() => _saved = list);
  }



  Future<void> _saveAll(List<RouletteDef> list) async {
    await Store.saveSaved(list);
    await _load();
  }

  Future<void> _togglePin(RouletteDef d) async {
    final list = await Store.loadSaved();
    final i = list.indexWhere((e) => e.id == d.id);
    if (i >= 0) {
      list[i] = RouletteDef(
        id: d.id,
        title: d.title,
        items: d.items,
        createdAt: d.createdAt,
        updatedAt:
        DateTime.now().toIso8601String(),
        lastUsedAt: d.lastUsedAt,
        isPinned: !d.isPinned,
      );
      await _saveAll(list);
    }
  }

  Future<void> _rename(RouletteDef d) async {
    final titleCtl =
    TextEditingController(text: d.title);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('名前を変更'),
        content: TextField(
          controller: titleCtl,
          maxLength: 30,
          decoration: const InputDecoration(
            labelText: 'タイトル',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    var newTitle = titleCtl.text.trim().isEmpty
        ? d.title
        : titleCtl.text.trim();

    final list = await Store.loadSaved();

    if (list.any(
          (e) => e.id != d.id && e.title == newTitle,
    )) {
      int n = 2;
      while (list.any(
            (e) => e.id != d.id && e.title == '$newTitle$n',
      )) {
        n++;
      }
      newTitle = '$newTitle$n';
    }

    final i = list.indexWhere((e) => e.id == d.id);
    if (i >= 0) {
      list[i] = RouletteDef(
        id: d.id,
        title: newTitle,
        items: d.items,
        createdAt: d.createdAt,
        updatedAt:
        DateTime.now().toIso8601String(),
        lastUsedAt: d.lastUsedAt,
        isPinned: d.isPinned,
      );
      await _saveAll(list);
    }
  }

  Future<void> _confirmDelete(RouletteDef d) async {
    final cs = Theme.of(context).colorScheme;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('削除しますか？'),
        content: Text(
          '「${d.title}」を削除します。元に戻せません。',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            onPressed: () =>
                Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final list = await Store.loadSaved();
    list.removeWhere((e) => e.id == d.id);
    await _saveAll(list);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('削除しました'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(
            16,
            0,
            16,
            80,
          ),
          backgroundColor:
          cs.surfaceTint.withOpacity(0.9),
        ),
      );
    }
  }

  Widget _emptyState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.inbox_outlined,
            size: 56,
            color: Colors.black26,
          ),
          const SizedBox(height: 10),
          const Text(
            'まだ保存されたルーレットはありません',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                  const QuickInputPage(),
                ),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('新しく作る'),
            style: FilledButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius:
                BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        titleSpacing: 8,
        title: Row(
          children: [
            Icon(
              Icons.save_alt_rounded,
              color: Theme.of(context).colorScheme.primary,
              size: 26,
            ),
            const SizedBox(width: 8),
            const Text(
              '保存済みルーレット',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),

      // ← ここがさっき貼ってくれた body
      body: _saved.isEmpty
          ? _emptyState(context)
          : ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: _saved.length,
        itemBuilder: (context, i) {
          final d = _saved[i];
          final preview = d.items
              .take(3)
              .map((e) => e.name)
              .join('、') +
              (d.items.length > 3 ? '…' : '');

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Material(
              color: Colors.white,
              elevation: 2,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => QuickInputPage(initial: d),
                    ),
                  ).then((_) => _load());
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '名前変更',
                            icon: Icon(
                              Icons.edit_outlined,
                              color: cs.primary.withOpacity(0.95),
                            ),
                            onPressed: () => _rename(d),
                          ),
                          IconButton(
                            tooltip: d.isPinned ? 'お気に入り解除' : 'お気に入り',
                            icon: Icon(
                              d.isPinned ? Icons.star : Icons.star_border,
                              color: d.isPinned ? cs.primary : Colors.black45,
                            ),
                            onPressed: () => _togglePin(d),
                          ),
                          IconButton(
                            tooltip: '削除',
                            icon: Icon(
                              Icons.delete_outline,
                              color: Colors.red.shade700,
                            ),
                            onPressed: () => _confirmDelete(d),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),

      // 🔻 ここを追加：保存済み画面用のバナー
      bottomNavigationBar: const BottomBanner(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
      ),
    );
  }

}

// ===== BLOCK 5: spin page =====

class SpinPage extends StatefulWidget {
  final RouletteDef def;
  final bool quickResult; // ★ 追加

  const SpinPage({
    super.key,
    required this.def,
    this.quickResult = false,
  });

  @override
  State<SpinPage> createState() => _SpinPageState();
}

class _SpinPageState extends State<SpinPage>
    with TickerProviderStateMixin {
  late AnimationController wheelCtrl;
  late Animation<double> wheelAnim;

  // ★ ここ追加：設定で変わる値
  late Duration _spinDuration;
  late int _spinsCount;

  // TAP! アニメ
  late AnimationController _tapCtrl;
  late Animation<double> _tapScale;

  // 結果オーバーレイ
  late AnimationController _resultCtrl;
  late Animation<double> _cardScale;
  late Animation<double> _cardOpacity;
  late Animation<Offset> _sheetOffset;

  final rand = Random();

  bool _spinning = false;
  double _angle = 0.0;
  String? _resultName;

  ui.Image? _wheelImage;
  Size? _wheelImageSize;
  bool _buildingImage = false;

  @override
  void initState() {
    super.initState();

    // デフォ値
    _spinDuration =
    const Duration(milliseconds: 5000);
    _spinsCount = 15;

    wheelCtrl = AnimationController(
      vsync: this,
      duration: _spinDuration,
    );

    // 設定から時間モードを反映
    _loadSpinSettings();

    _tapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _tapScale = Tween<double>(
      begin: 0.94,
      end: 1.08,
    ).animate(
      CurvedAnimation(
        parent: _tapCtrl,
        curve: Curves.easeInOutQuad,
      ),
    );
    _tapCtrl.repeat(reverse: true);

    _resultCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _cardScale = Tween<double>(
      begin: 0.95,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _resultCtrl,
        curve: Curves.easeOutBack,
      ),
    );
    _cardOpacity = CurvedAnimation(
      parent: _resultCtrl,
      curve: Curves.easeOutCubic,
    );
    _sheetOffset = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _resultCtrl,
        curve: Curves.easeOutCubic,
      ),
    );

    // ★ 結果をすぐ表示モードなら、画面表示後すぐ結果決定
    if (widget.quickResult) {
      WidgetsBinding.instance.addPostFrameCallback(
            (_) {
          _spin();
        },
      );
    }
  }

  Future<void> _loadSpinSettings() async {
    final settings = await Store.loadSettings();
    if (!mounted) return;

    switch (settings.timeMode) {
      case RouletteTimeMode.short:
        _spinDuration =
        const Duration(milliseconds: 2500);
        _spinsCount = 11;
        break;
      case RouletteTimeMode.normal:
        _spinDuration =
        const Duration(milliseconds: 5000);
        _spinsCount = 15;
        break;
      case RouletteTimeMode.long:
        _spinDuration =
        const Duration(milliseconds: 8000);
        _spinsCount = 20;
        break;
    }
    wheelCtrl.duration = _spinDuration;
  }

  @override
  void didUpdateWidget(covariant SpinPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.def.items != widget.def.items) {
      _wheelImage?.dispose();
      _wheelImage = null;
      _wheelImageSize = null;
    }
  }

  @override
  void dispose() {
    wheelCtrl.dispose();
    _tapCtrl.dispose();
    _resultCtrl.dispose();
    _wheelImage?.dispose();
    super.dispose();
  }

  Future<void> _spin() async {
    if (_spinning || _resultName != null) return;

    final items = widget.def.items;
    if (items.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("候補は2件以上必要です"),
        ),
      );
      return;
    }

    setState(() {
      _spinning = true;
      _resultName = null;
    });

    // 重み付きで当たりを決定
    final weights = items.map((e) => e.weight).toList();
    final total =
    weights.reduce((a, b) => a + b);

    int r = rand.nextInt(total),
        acc = 0,
        idx = 0;

    for (int i = 0; i < weights.length; i++) {
      acc += weights[i];
      if (r < acc) {
        idx = i;
        break;
      }
    }

    // ★ クイック結果モード：アニメなしですぐ結果表示
    if (widget.quickResult) {
      setState(() {
        _spinning = false;
        _resultName = items[idx].name;
      });
      _resultCtrl
        ..reset()
        ..forward();
      await _updateLastAndBumpSaved();
      return;
    }

    // ここからは従来のアニメ付きスピン
    final targetAngle = _targetAngleForIndex(idx);
    final begin = _angle;
    final end = begin +
        _spinsCount * 2 * pi +
        _normalizeDelta(begin, targetAngle);

    wheelAnim = CurvedAnimation(
      parent: wheelCtrl,
      curve: Curves.easeOutCubic,
    );

    wheelCtrl
      ..reset()
      ..addListener(() {
        setState(() {
          _angle = begin +
              (end - begin) * wheelAnim.value;
        });
      });

    await wheelCtrl.forward();

    setState(() {
      _angle = end;
      _spinning = false;
      _resultName = items[idx].name;
    });

    _resultCtrl
      ..reset()
      ..forward();

    await _updateLastAndBumpSaved();
  }

  double _normalizeDelta(double begin, double target) {
    double d = target - (begin % (2 * pi));
    while (d < 0) d += 2 * pi;
    return d;
  }

  double _targetAngleForIndex(int index) {
    final items = widget.def.items;
    final sum = items.fold<int>(
      0,
          (s, e) => s + e.weight,
    );

    double acc = 0;
    for (int i = 0; i < index; i++) {
      acc += items[i].weight / sum;
    }

    final w = items[index].weight / sum;
    final center = acc + w / 2;
    double a = -center * 2 * pi;
    while (a < 0) a += 2 * pi;
    return a;
  }

  String _displayName(String s) =>
      s.runes.length <= 12
          ? s
          : String.fromCharCodes(
        s.runes.take(12),
      ) +
          "…";

  Future<void> _updateLastAndBumpSaved() async {
    final now = DateTime.now().toIso8601String();
    final d = widget.def;

    final def = RouletteDef(
      id: d.id,
      title: d.title,
      items: d.items,
      createdAt: d.createdAt,
      updatedAt: now,
      lastUsedAt: now,
      isPinned: d.isPinned,
    );

    await Store.saveLast(def);

    final saved = await Store.loadSaved();
    final i = saved.indexWhere((e) => e.id == d.id);
    if (i >= 0) {
      saved[i] = def;
      await Store.saveSaved(saved);
    }
  }

  void _resetForNext() {
    _resultCtrl.reset();
    setState(() {
      _resultName = null;
    });

    // ★ クイック結果モードなら、すぐ次の結果を出す
    if (widget.quickResult) {
      _spin();
    }
  }

  // SpinPage 保存ダイアログ（保存後この画面に留まる）
  Future<void> _saveFromSpinWithDialog() async {
    if (widget.def.items.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          const SnackBar(
            content: Text("候補は2件以上必要です"),
          ),
        );
      }
      return;
    }

    final saved = await Store.loadSaved();
    final defaultTitle =
    await _nextDefaultTitleForSave();

    final titleCtl = TextEditingController(
      text: defaultTitle,
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("ルーレットを保存"),
        content: TextField(
          controller: titleCtl,
          maxLength: 30,
          decoration: const InputDecoration(
            labelText: "タイトル（100文字まで）",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, false),
            child: const Text("キャンセル"),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, true),
            child: const Text("保存"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    var title = titleCtl.text.trim().isEmpty
        ? defaultTitle
        : titleCtl.text.trim();

    if (saved.any((e) => e.title == title)) {
      int n = 2;
      while (saved.any(
            (e) => e.title == "$title$n",
      )) {
        n++;
      }
      title = "$title$n";
    }

    final now = DateTime.now().toIso8601String();
    final d = widget.def;
    final idx =
    saved.indexWhere((e) => e.id == d.id);

    final def = RouletteDef(
      id: d.id,
      title: title,
      items: List<RouletteItem>.from(d.items),
      createdAt:
      idx >= 0 ? saved[idx].createdAt : now,
      updatedAt: now,
      lastUsedAt: now,
      isPinned:
      idx >= 0 ? saved[idx].isPinned : false,
    );

    if (idx >= 0) {
      saved[idx] = def;
    } else {
      saved.insert(0, def);
    }

    await Store.saveSaved(saved);
    await Store.saveLast(def);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("保存しました")),
      );
    }
  }

  Future<String> _nextDefaultTitleForSave() async {
    final saved = await Store.loadSaved();
    final used = <int>{};

    final re = RegExp(r'^ルーレット(\d+)$');
    for (final d in saved) {
      final m = re.firstMatch(d.title);
      if (m != null) {
        final n =
        int.tryParse(m.group(1) ?? '');
        if (n != null) used.add(n);
      }
    }

    int n = 1;
    while (used.contains(n)) n++;
    return "ルーレット$n";
  }

  // ラジアル文字（SpinPage側で使用）
  void _paintRadialTextInward(
      Canvas canvas, {
        required Offset center,
        required String text,
        required double midAngle,
        required double radiusForMaxWidth,
        double fontSize = 14,
        Color fillColor = Colors.white,
        Color outlineColor = Colors.black,
        double outlineWidth = 2,
      }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: fillColor,
          shadows: const [
            Shadow(
              offset: Offset(0, 1),
              blurRadius: 3,
              color: Colors.black26,
            ),
          ],
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: "…",
    )..layout(maxWidth: radiusForMaxWidth);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    tp.paint(
      canvas,
      Offset(-tp.width / 2, -tp.height / 2),
    );
    canvas.restore();
  }

  // BLOCK5内ユーティリティ（フォールバック描画で使用）
  Color _shade(
      Color c, {
        double lightnessDelta = -0.08,
      }) {
    final hsl = HSLColor.fromColor(c);
    final l = (hsl.lightness + lightnessDelta)
        .clamp(0.0, 1.0);
    return hsl.withLightness(l).toColor();
  }

  void _paintOutlinedText(
      Canvas canvas, {
        required Offset center,
        required String text,
        double fontSize = 14,
        Color fillColor = Colors.white,
        double maxWidth = 120,
        TextAlign align = TextAlign.center,
        Color? outlineColor,
        double? outlineWidth,
        Color? bgColor,
      }) {
    final ow =
    (outlineWidth ?? (fontSize / 7)).clamp(1.0, 2.2);

    final oc = outlineColor ??
        ((bgColor != null &&
            ThemeData.estimateBrightnessForColor(
              bgColor,
            ) ==
                Brightness.dark)
            ? Colors.white.withOpacity(0.85)
            : Colors.black.withOpacity(0.9));

    final base = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          height: 1.1,
          fontWeight: FontWeight.w600,
          color: fillColor,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 2,
      ellipsis: "…",
    )..layout(maxWidth: maxWidth);

    final outline = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          height: 1.1,
          fontWeight: FontWeight.w800,
          color: oc,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 2,
      ellipsis: "…",
    )..layout(maxWidth: maxWidth);

    final dx = -base.width / 2;
    final dy = -base.height / 2;

    final offsets = <Offset>[
      Offset(-ow, 0),
      Offset(ow, 0),
      Offset(0, -ow),
      Offset(0, ow),
      Offset(-ow, -ow),
      Offset(-ow, ow),
      Offset(ow, -ow),
      Offset(ow, ow),
    ];

    for (final o in offsets) {
      outline.paint(
        canvas,
        center + Offset(dx, dy) + o,
      );
    }

    base.paint(
      canvas,
      center + Offset(dx, dy),
    );
  }

  // 画像キャッシュ生成
  Future<void> _ensureWheelImage(Size size) async {
    if (_buildingImage) return;
    if (_wheelImage != null &&
        _wheelImageSize != null &&
        (size.width - _wheelImageSize!.width).abs() < 1 &&
        (size.height - _wheelImageSize!.height)
            .abs() <
            1) {
      return;
    }

    _buildingImage = true;
    try {
      final items = widget.def.items;
      final total = items.fold<int>(
        0,
            (s, e) => s + e.weight,
      );

      final dpr = ui.window.devicePixelRatio;
      final w =
      (size.width * dpr).toInt().clamp(64, 4096);
      final h =
      (size.height * dpr).toInt().clamp(64, 4096);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(
          0,
          0,
          w.toDouble(),
          h.toDouble(),
        ),
      );

      canvas.scale(dpr, dpr);

      final r = (size.shortestSide * 0.44);
      final center = Offset(
        size.width / 2,
        size.height / 2,
      );
      final rect = Rect.fromCircle(
        center: center,
        radius: r,
      );

      // 落ち影
      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.18)
        ..maskFilter = ui.MaskFilter.blur(
          ui.BlurStyle.normal,
          18,
        );
      canvas.drawCircle(
        center + const Offset(0, 8),
        r * 0.94,
        shadowPaint,
      );

      if (total > 0) {
        double start = -pi / 2;
        final segPaint = Paint()
          ..style = PaintingStyle.fill;
        final sepPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white.withOpacity(0.85);

        for (final it in items) {
          final sweep =
              (it.weight / total) * 2 * pi;
          final base = Color(it.color);

          segPaint.shader = RadialGradient(
            colors: [
              _shade(
                base,
                lightnessDelta: -0.05,
              ),
              base,
              _shade(
                base,
                lightnessDelta: 0.06,
              ),
            ],
            stops: const [0.0, 0.82, 1.0],
            center: Alignment.center,
            radius: 0.98,
          ).createShader(rect);

          canvas.drawArc(
            rect,
            start,
            sweep,
            true,
            segPaint,
          );
          canvas.drawArc(
            rect,
            start,
            sweep,
            true,
            sepPaint,
          );

          final frac = it.weight / total;
          final fs =
          (12 + (frac * 24)).clamp(12, 20).toDouble();
          final mid = start + sweep / 2;

          final labelR = r * 0.72;
          final labelCenter = Offset(
            center.dx + cos(mid) * labelR,
            center.dy + sin(mid) * labelR,
          );

          final segPath = Path()
            ..moveTo(center.dx, center.dy)
            ..arcTo(rect, start, sweep, false)
            ..close();

          final chord =
              2 * labelR * sin(sweep / 2);
          final maxW = chord * 0.88;

          canvas.save();
          canvas.clipPath(segPath);
          _paintRadialTextInward(
            canvas,
            center: labelCenter,
            text: it.name,
            midAngle: mid,
            radiusForMaxWidth: maxW,
            fontSize: fs,
            fillColor: Colors.white,
            outlineColor: Colors.black,
            outlineWidth:
            (fs / 7).clamp(1.0, 2.2),
          );
          canvas.restore();

          start += sweep;
        }

        // 外周リム
        final rimPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..shader = SweepGradient(
            startAngle: -pi / 2,
            endAngle: 3 * pi / 2,
            colors: [
              Colors.white.withOpacity(0.7),
              Colors.white.withOpacity(0.0),
              Colors.black.withOpacity(0.12),
              Colors.white.withOpacity(0.4),
            ],
          ).createShader(rect);
        canvas.drawCircle(center, r - 1, rimPaint);

        // 白ハブ
        final hubR = r * 0.45;
        final hubRect = Rect.fromCircle(
          center: center,
          radius: hubR,
        );
        final hubPaint = Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white,
              Colors.grey.shade200,
            ],
            center: const Alignment(-0.15, -0.15),
            radius: 1.0,
          ).createShader(hubRect);
        canvas.drawCircle(center, hubR, hubPaint);

        final hubStroke = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.black.withOpacity(0.10);
        canvas.drawCircle(center, hubR, hubStroke);
      }

      final picture = recorder.endRecording();
      final image =
      await picture.toImage(w, h);

      _wheelImage?.dispose();

      if (mounted) {
        setState(() {
          _wheelImage = image;
          _wheelImageSize = size;
        });
      } else {
        image.dispose();
      }
    } finally {
      _buildingImage = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.def.items;
    final sum = items.fold<int>(
      0,
          (s, e) => s + e.weight,
    );
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: true,
        title: const SizedBox.shrink(),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: (_spinning || _resultName != null)
            ? null
            : _spin,
        child: Stack(
          children: [
            // ① ルーレット本体
            Column(
              children: [
                const SizedBox(height: 12),
                Expanded(
                  flex: 8,
                  child: LayoutBuilder(
                    builder: (_, c) {
                      final sz = Size(
                        c.maxWidth,
                        c.maxHeight,
                      );
                      _ensureWheelImage(sz);

                      final wheelRadius =
                          sz.shortestSide * 0.44;
                      final centerY =
                          sz.height / 2;
                      final wheelTop =
                          centerY - wheelRadius;

                      const pointerSize = 44.0;
                      const gap = 4.0;

                      double pointerTop =
                          wheelTop -
                              gap -
                              pointerSize * 0.95;

                      if (pointerTop < 0) {
                        pointerTop = 0;
                      }

                      double tapTop =
                          pointerTop - 32;
                      if (tapTop < 0) tapTop = 0;

                      return Stack(
                        children: [
                          Align(
                            alignment:
                            Alignment.center,
                            child: _wheelImage !=
                                null &&
                                _wheelImageSize !=
                                    null
                                ? CustomPaint(
                              size: sz,
                              painter:
                              _ImageWheelPainter(
                                image:
                                _wheelImage!,
                                angle: _angle,
                              ),
                            )
                                : CustomPaint(
                              size: sz,
                              painter: _WheelFallbackPainter(
                                items: items,
                                total: sum,
                                angle: _angle,
                              ),
                            ),

                          ),
                          if (!_spinning &&
                              _resultName == null)
                            Positioned(
                              top: tapTop,
                              left: 0,
                              right: 0,
                              child: Center(
                                child:
                                ScaleTransition(
                                  scale: _tapScale,
                                  child: const Text(
                                    'TAP!',
                                    style: TextStyle(
                                      fontSize: 26,
                                      fontWeight:
                                      FontWeight
                                          .w800,
                                      color: Color(
                                        0xFFFFD93D,
                                      ),
                                      shadows: [
                                        Shadow(
                                          offset:
                                          Offset(
                                            0,
                                            1,
                                          ),
                                          blurRadius:
                                          3,
                                          color: Colors
                                              .black26,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            top: pointerTop,
                            left: (sz.width -
                                pointerSize) /
                                2,
                            child: SizedBox(
                              width: pointerSize,
                              height: pointerSize,
                              child: CustomPaint(
                                painter:
                                _PointerPainterGlow(),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),

            // ② 結果オーバーレイ（ぼかし＋カード＋下のボタンシート）
            if (_resultName != null)
              Positioned.fill(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(
                          sigmaX: 6,
                          sigmaY: 6,
                        ),
                        child: Container(
                          color: Colors.black
                              .withOpacity(0.28),
                        ),
                      ),
                    ),
                    Center(
                      child: FadeTransition(
                        opacity: _cardOpacity,
                        child: ScaleTransition(
                          scale: _cardScale,
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 32),
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18), // ★余白詰めた
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.18),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize:
                              MainAxisSize.min,
                              children: [
                                Text(
                                  '結果',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight:
                                    FontWeight
                                        .w600,
                                    color:
                                    cs.primary,
                                  ),
                                ),
                                const SizedBox(
                                  height: 6,
                                ),
                                Text(
                                  _displayName(
                                    _resultName!,
                                  ),
                                  textAlign:
                                  TextAlign
                                      .center,
                                  style:
                                  const TextStyle(
                                    fontSize: 44,
                                    fontWeight:
                                    FontWeight
                                        .w800,
                                    color: Colors
                                        .black87,
                                    letterSpacing:
                                    0.3,
                                  ),
                                ),
                                const SizedBox(
                                  height: 8,
                                ),
                                Text(
                                  '${_resultName!} が当たりました',
                                  textAlign:
                                  TextAlign
                                      .center,
                                  style:
                                  const TextStyle(
                                    fontSize: 14,
                                    color: Colors
                                        .black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: SlideTransition(
                        position: _sheetOffset,
                        child: Container(
                          width: double.infinity,
                          padding:
                          const EdgeInsets
                              .fromLTRB(
                            16,
                            12,
                            16,
                            20,
                          ),
                          decoration:
                          BoxDecoration(
                            color: Colors.white,
                            borderRadius:
                            const BorderRadius
                                .vertical(
                              top:
                              Radius.circular(
                                22,
                              ),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black
                                    .withOpacity(
                                  0.2,
                                ),
                                blurRadius: 18,
                                offset:
                                const Offset(
                                  0,
                                  -4,
                                ),
                              ),
                            ],
                          ),
                          child: SafeArea(
                            top: false,
                            child: Column(
                              mainAxisSize:
                              MainAxisSize.min,
                              children: [
                                // ← この灰色バーを削除！
                                SizedBox(height: 4), // ★必要ならちょい余白だけ残す
                                SizedBox(
                                  width:
                                  double.infinity,
                                  height: 52,
                                  child:
                                  FilledButton
                                      .icon(
                                    onPressed:
                                    _resetForNext,
                                    icon: const Icon(
                                      Icons.refresh,
                                    ),
                                    label: const Text(
                                      'もう一度回す',
                                    ),
                                    style: FilledButton
                                        .styleFrom(
                                      backgroundColor:
                                      cs.primary,
                                      foregroundColor:
                                      cs.onPrimary,
                                      textStyle:
                                      const TextStyle(
                                        fontSize: 17,
                                        fontWeight:
                                        FontWeight
                                            .w700,
                                      ),
                                      shape:
                                      RoundedRectangleBorder(
                                        borderRadius:
                                        BorderRadius
                                            .circular(
                                          16,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(
                                  height: 10,
                                ),
                                SizedBox(
                                  width:
                                  double.infinity,
                                  height: 48,
                                  child: FilledButton
                                      .tonalIcon(
                                    onPressed:
                                    _saveFromSpinWithDialog,
                                    icon: const Icon(
                                      Icons.save_alt,
                                    ),
                                    label: const Text(
                                      'ルーレットを保存',
                                    ),
                                    style: FilledButton
                                        .styleFrom(
                                      backgroundColor: cs
                                          .primaryContainer,
                                      foregroundColor: cs
                                          .onPrimaryContainer,
                                      textStyle:
                                      const TextStyle(
                                        fontSize: 15,
                                        fontWeight:
                                        FontWeight
                                            .w700,
                                      ),
                                      shape:
                                      RoundedRectangleBorder(
                                        borderRadius:
                                        BorderRadius
                                            .circular(
                                          14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(
                                  height: 8,
                                ),
                                SizedBox(
                                  width:
                                  double.infinity,
                                  height: 48,
                                  child: FilledButton
                                      .tonalIcon(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              QuickInputPage(
                                                initial:
                                                widget.def,
                                              ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons
                                          .edit_outlined,
                                    ),
                                    label: const Text(
                                      'ルーレットを編集',
                                    ),
                                    style: FilledButton
                                        .styleFrom(
                                      backgroundColor: cs
                                          .secondaryContainer,
                                      foregroundColor: cs
                                          .onSecondaryContainer,
                                      textStyle:
                                      const TextStyle(
                                        fontSize: 15,
                                        fontWeight:
                                        FontWeight
                                            .w700,
                                      ),
                                      shape:
                                      RoundedRectangleBorder(
                                        borderRadius:
                                        BorderRadius
                                            .circular(
                                          14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(
                                  height: 8,
                                ),
                                SizedBox(
                                  width:
                                  double.infinity,
                                  height: 48,
                                  child: FilledButton
                                      .tonalIcon(
                                    onPressed: () {
                                      Navigator.of(
                                        context,
                                      ).popUntil(
                                            (route) =>
                                        route.isFirst,
                                      );
                                    },
                                    icon: const Icon(
                                      Icons
                                          .home_outlined,
                                    ),
                                    label: const Text(
                                      'タイトルへ戻る',
                                    ),
                                    style: FilledButton
                                        .styleFrom(
                                      backgroundColor:
                                      Colors.white,
                                      foregroundColor:
                                      cs.primary,
                                      textStyle:
                                      const TextStyle(
                                        fontSize: 15,
                                        fontWeight:
                                        FontWeight
                                            .w700,
                                      ),
                                      shape:
                                      RoundedRectangleBorder(
                                        borderRadius:
                                        BorderRadius
                                            .circular(
                                          14,
                                        ),
                                        side: BorderSide(
                                          color: cs.primary
                                              .withOpacity(
                                            0.40,
                                          ),
                                          width: 1.2,
                                        ),
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
                  ],
                ),
              ),

            // ③ 一番手前：結果表示中だけ上部にバナーを出す
            if (_resultName != null)
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: SafeArea(
                  top: true,
                  bottom: false,
                  child: Center(
                    child: BottomBanner(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    ),
                  ),
                ),
              ),

          ],
        ),
      ),
    );
  }
}

// ---------- 画像を回すだけの軽量ペインタ ----------
class _ImageWheelPainter extends CustomPainter {
  final ui.Image image;
  final double angle;

  _ImageWheelPainter({
    required this.image,
    required this.angle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final dst = Rect.fromLTWH(
      0,
      0,
      size.width,
      size.height,
    );
    final center = Offset(
      size.width / 2,
      size.height / 2,
    );

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.low,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ImageWheelPainter old) =>
      old.image != image || old.angle != angle;
}

// ---------- フォールバック（画像生成中だけ一瞬使う） ----------
class _WheelFallbackPainter extends CustomPainter {
  final List<RouletteItem> items;
  final int total;
  final double angle;

  const _WheelFallbackPainter({
    required this.items,
    required this.total,
    required this.angle,
  });

  Color _shade(Color c, {double lightnessDelta = -0.08}) {
    final hsl = HSLColor.fromColor(c);
    final l = (hsl.lightness + lightnessDelta).clamp(0.0, 1.0);
    return hsl.withLightness(l).toColor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide * 0.44;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: r);

    // 影（SpinPage の画像版とほぼ同じ）
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.18)
      ..maskFilter = const ui.MaskFilter.blur(
        ui.BlurStyle.normal,
        18,
      );
    canvas.drawCircle(center + const Offset(0, 8), r * 0.94, shadowPaint);

    if (total <= 0) return;

    // ここで一度キャンバスごと回転させて、angle を反映
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.translate(-center.dx, -center.dy);

    double start = -pi / 2;
    final segPaint = Paint()..style = PaintingStyle.fill;
    final sepPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withOpacity(0.85);

    for (final it in items) {
      final sweep = (it.weight / total) * 2 * pi;
      final base = Color(it.color);

      // グラデーションも画像版と合わせる
      segPaint.shader = RadialGradient(
        colors: [
          _shade(base, lightnessDelta: -0.05),
          base,
          _shade(base, lightnessDelta: 0.06),
        ],
        stops: const [0.0, 0.82, 1.0],
        center: Alignment.center,
        radius: 0.98,
      ).createShader(rect);

      canvas.drawArc(rect, start, sweep, true, segPaint);
      canvas.drawArc(rect, start, sweep, true, sepPaint);

      // 文字も同じテイスト（白＋うっすら影）
      final frac = it.weight / total;
      final fs = (12 + (frac * 24)).clamp(12, 20).toDouble();
      final mid = start + sweep / 2;

      final labelR = r * 0.72;
      final labelCenter = Offset(
        center.dx + cos(mid) * labelR,
        center.dy + sin(mid) * labelR,
      );
      final chord = 2 * labelR * sin(sweep / 2);
      final maxW = chord * 0.88;

      final tp = TextPainter(
        text: TextSpan(
          text: it.name,
          style: TextStyle(
            fontSize: fs,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            shadows: const [
              Shadow(
                offset: Offset(0, 1),
                blurRadius: 3,
                color: Colors.black26,
              ),
            ],
          ),
        ),
        maxLines: 2,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        ellipsis: '…',
      )..layout(maxWidth: maxW);

      final segPath = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(rect, start, sweep, false)
        ..close();

      canvas.save();
      canvas.clipPath(segPath);
      canvas.translate(labelCenter.dx, labelCenter.dy);
      canvas.rotate(mid + pi); // 放射状に内向き
      tp.paint(
        canvas,
        Offset(-tp.width / 2, -tp.height / 2),
      );
      canvas.restore();

      start += sweep;
    }

    canvas.restore(); // ← angle 回転の restore

    // 外周リム
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..shader = SweepGradient(
        startAngle: -pi / 2,
        endAngle: 3 * pi / 2,
        colors: [
          Colors.white.withOpacity(0.7),
          Colors.white.withOpacity(0.0),
          Colors.black.withOpacity(0.12),
          Colors.white.withOpacity(0.4),
        ],
      ).createShader(rect);
    canvas.drawCircle(center, r - 1, rimPaint);

    // 中央の白丸
    final hubR = r * 0.45;
    final hubRect = Rect.fromCircle(center: center, radius: hubR);
    final hubPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white,
          Colors.grey.shade200,
        ],
        center: const Alignment(-0.15, -0.15),
        radius: 1.0,
      ).createShader(hubRect);
    canvas.drawCircle(center, hubR, hubPaint);

    final hubStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.black.withOpacity(0.10);
    canvas.drawCircle(center, hubR, hubStroke);
  }

  @override
  bool shouldRepaint(covariant _WheelFallbackPainter old) =>
      old.items != items || old.total != total || old.angle != angle;
}


// ===== PATCH: pointer painter — tip points DOWN toward the wheel =====
class _PointerPainterGlow extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    final glow = Paint()
      ..color = Colors.redAccent.withOpacity(0.28)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(
        BlurStyle.normal,
        6,
      );
    final fill = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final path = Path()
      ..moveTo(w * 0.50, h * 0.95)
      ..lineTo(w * 0.18, h * 0.20)
      ..lineTo(w * 0.82, h * 0.20)
      ..close();

    canvas.drawPath(path, glow);
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) =>
      false;
}

// ===== BLOCK 6: Ads =====

class AdIds {
  static String get bannerTest {
    if (kIsWeb) return ''; // webは未対応（空文字で無効化）

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'ca-app-pub-3940256099942544/6300978111';
      case TargetPlatform.iOS:
        return 'ca-app-pub-3940256099942544/2934735716';
      default:
        return 'ca-app-pub-3940256099942544/6300978111'; // デフォはAndroid
    }
  }

  // 本番ID（ビルド前に差し替え）
  static String get banner => bannerTest;
}

/// 画面下に固定するアンカード・アダプティブバナー
class BottomBanner extends StatefulWidget {
  /// 画面端からの余白
  final EdgeInsets padding;

  /// 上側のノッチ / ステータスバーを避けるか
  final bool safeTop;

  /// 下側のホームバーなどを避けるか
  final bool safeBottom;

  const BottomBanner({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 8),
    this.safeTop = false,   // デフォルトは「下に置く想定」なので false
    this.safeBottom = true, // 下は避ける
  });

  @override
  State<BottomBanner> createState() => _BottomBannerState();
}


class _BottomBannerState extends State<BottomBanner>
    with WidgetsBindingObserver {
  BannerAd? _ad;
  AdSize? _loadedSize;
  Orientation? _lastOrientation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // 端末の向きが変わったらサイズを取り直す
    final ori = MediaQuery.of(context).orientation;
    if (_lastOrientation != ori) {
      _lastOrientation = ori;
      _load();
    }
  }

  @override
  void didChangeMetrics() {
    // 画面幅が変わる（分割/キーボード/回転）時も安全に張り替え
    WidgetsBinding.instance.addPostFrameCallback(
          (_) => _load(),
    );
  }

  Future<void> _load() async {
    if (!mounted) return;

    // 既存を破棄してサイズを取り直す
    _ad?.dispose();
    _ad = null;
    _loadedSize = null;

    // ▼ ここを変更：パディングを引いた幅でサイズを取得
    final fullWidth =
        MediaQuery.of(context).size.width;
    final usableWidth = (fullWidth -
        widget.padding.horizontal)
        .clamp(0, double.infinity);
    final width = usableWidth.truncate();
    if (width <= 0) return;

    final size =
    await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(
      width,
    );
    if (!mounted || size == null) return;

    final ad = BannerAd(
      adUnitId: AdIds.banner,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) return;
          setState(() {
            _ad = ad as BannerAd;
            _loadedSize = size;
          });
        },
        onAdFailedToLoad: (ad, err) {
          ad.dispose();
        },
      ),
    );

    await ad.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ad == null || _loadedSize == null) {
      return const SizedBox.shrink();
    }

    return SafeArea(
      top: widget.safeTop,
      bottom: widget.safeBottom,
      child: Padding(
        padding: widget.padding,
        child: SizedBox(
          width: double.infinity,
          height: _loadedSize!.height.toDouble(),
          child: Align(
            alignment: Alignment.center,
            child: AdWidget(ad: _ad!),
          ),
        ),
      ),
    );
  }


}
