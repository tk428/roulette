import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const RouletteApp());

class RouletteApp extends StatelessWidget {
  const RouletteApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ルーレット',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const RootPage(),
    );
  }
}

/* ===================== モデル & 永続化 ===================== */

class RouletteItem {
  final String name;
  final int weight; // 1-100
  final int color;  // Color.value
  RouletteItem({required this.name, required this.weight, required this.color});
  Map<String, dynamic> toJson() => {"name": name, "weight": weight, "color": color};
  static RouletteItem fromJson(Map<String, dynamic> j) =>
      RouletteItem(name: j["name"], weight: j["weight"], color: j["color"]);
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
        items: (j["items"] as List).map((e) => RouletteItem.fromJson(Map<String, dynamic>.from(e))).toList(),
        createdAt: j["createdAt"],
        updatedAt: j["updatedAt"],
        lastUsedAt: j["lastUsedAt"],
        isPinned: j["isPinned"] ?? false,
      );
}

class Store {
  static const _kLast = "last_roulette";
  static const _kSaved = "saved_roulettes";

  static Future<Map<String, dynamic>?> loadLast() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kLast);
    return s == null ? null : jsonDecode(s);
  }

  static Future<void> saveLast(RouletteDef def) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLast, jsonEncode(def.toJson()));
  }

  static Future<List<RouletteDef>> loadSaved() async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_kSaved) ?? [];
    return list.map((s) => RouletteDef.fromJson(jsonDecode(s))).toList();
  }

  static Future<void> saveSaved(List<RouletteDef> defs) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kSaved, defs.map((d) => jsonEncode(d.toJson())).toList());
  }
}

/* ===================== ルート画面 ===================== */

class RootPage extends StatefulWidget {
  const RootPage({super.key});
  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  RouletteDef? last;
  List<RouletteDef> saved = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final lastJson = await Store.loadLast();
    final savedList = await Store.loadSaved();
    setState(() {
      last = lastJson == null ? null : RouletteDef.fromJson(lastJson);
      final pinned = savedList.where((e) => e.isPinned).toList();
      final others = savedList.where((e) => !e.isPinned).toList()
        ..sort((a, b) => (b.lastUsedAt ?? "").compareTo(a.lastUsedAt ?? ""));
      saved = [...pinned, ...others];
    });
  }

  void _deleteSaved(String id) async {
    final list = await Store.loadSaved();
    list.removeWhere((e) => e.id == id);
    await Store.saveSaved(list);
    _loadAll();
  }

  void _togglePin(String id, bool pin) async {
    final list = await Store.loadSaved();
    final i = list.indexWhere((e) => e.id == id);
    if (i >= 0) {
      final d = list[i];
      list[i] = RouletteDef(
        id: d.id,
        title: d.title,
        items: d.items,
        createdAt: d.createdAt,
        updatedAt: d.updatedAt,
        lastUsedAt: d.lastUsedAt,
        isPinned: pin,
      );
      await Store.saveSaved(list);
      _loadAll();
    }
  }

  Widget _savedTile(RouletteDef d) {
    final preview = d.items.take(3).map((e) => e.name).join(", ") + (d.items.length > 3 ? "…" : "");
    final pinned = d.isPinned;
    return Card(
      child: ListTile(
        leading: Icon(pinned ? Icons.push_pin : Icons.circle_outlined),
        title: Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == "pin") _togglePin(d.id, !pinned);
            if (v == "edit") Navigator.push(context, MaterialPageRoute(builder: (_) => DefinePage(initial: d))).then((_) => _loadAll());
            if (v == "del") _deleteSaved(d.id);
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: "pin", child: Text(pinned ? "ピン解除" : "ピン留め")),
            const PopupMenuItem(value: "edit", child: Text("編集")),
            const PopupMenuItem(value: "del", child: Text("削除")),
          ],
        ),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SpinPage(def: d))).then((_) => _loadAll()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pinned = saved.where((e) => e.isPinned).toList();
    final others = saved.where((e) => !e.isPinned).toList();

    return Scaffold(
      appBar: AppBar(title: const Text("ルーレット")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text("前回のルーレット", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (last != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(last!.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        FilledButton(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SpinPage(def: last!))).then((_) => _loadAll()),
                          child: const Text("▶ 回す"),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DefinePage(initial: last!))).then((_) => _loadAll()),
                          child: const Text("✎ 編集する"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          else
            const Text("（前回のルーレットはまだありません）"),
          const SizedBox(height: 24),
          const Text("保存したルーレット", style: TextStyle(fontWeight: FontWeight.bold)),
          if (pinned.isNotEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text("📌 ピン留め")),
          ...pinned.map(_savedTile),
          if (others.isNotEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text("最近使った順")),
          ...others.map(_savedTile),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DefinePage())).then((_) => _loadAll()),
            child: const Text("＋ 新規ルーレットを作成"),
          ),
        ],
      ),
    );
  }
}

/* ===================== 定義画面（比率デフォ=1） ===================== */

class DefinePage extends StatefulWidget {
  final RouletteDef? initial;
  const DefinePage({super.key, this.initial});
  @override
  State<DefinePage> createState() => _DefinePageState();
}

class _DefinePageState extends State<DefinePage> {
  final itemController = TextEditingController();
  final weightController = TextEditingController(text: "1");

  List<RouletteItem> items = [];

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      items = List<RouletteItem>.from(widget.initial!.items);
    }
  }

  void _add() {
    final name = itemController.text.trim();
    if (name.isEmpty) return;
    if (items.length >= 100) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("最大100件までです")));
      return;
    }
    int w = int.tryParse(weightController.text) ?? 1;
    if (w < 1) w = 1;
    if (w > 100) w = 100;
    setState(() {
      final color = Colors.primaries[items.length % Colors.primaries.length].shade400.value;
      items.add(RouletteItem(name: name, weight: w, color: color));
      itemController.clear();
      weightController.text = "1";
    });
  }

  Future<void> _saveDialog() async {
    if (items.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("候補は2件以上必要です")));
      return;
    }
    final saved = await Store.loadSaved();
    String base = "ルーレット";
    int num = 1;
    String candidate() => "$base$num";
    while (saved.any((e) => e.title == candidate())) num++;
    final titleCtl = TextEditingController(text: candidate());
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("ルーレットを保存"),
        content: TextField(
          controller: titleCtl,
          maxLength: 100,
          decoration: const InputDecoration(labelText: "タイトル（100文字まで）"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("キャンセル")),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("保存")),
        ],
      ),
    );
    if (ok != true) return;

    var title = titleCtl.text.trim().isEmpty ? candidate() : titleCtl.text.trim();
    if (saved.any((e) => e.title == title)) {
      int n = 2;
      while (saved.any((e) => e.title == "$title$n")) n++;
      title = "$title$n";
    }

    final now = DateTime.now().toIso8601String();
    final def = RouletteDef(
      id: UniqueKey().toString(),
      title: title,
      items: List<RouletteItem>.from(items),
      createdAt: now,
      updatedAt: now,
      lastUsedAt: null,
      isPinned: false,
    );
    saved.insert(0, def);
    if (saved.length > 10) saved.removeLast();
    await Store.saveSaved(saved);
    await Store.saveLast(def);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("保存しました")));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = items.fold<int>(0, (s, e) => s + e.weight);

    return Scaffold(
      appBar: AppBar(title: Text(widget.initial == null ? "新規ルーレット定義" : "ルーレット編集")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: itemController,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: "項目名（100文字まで）"),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: weightController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: "比率(1-100)"),
                ),
              ),
              IconButton(onPressed: _add, icon: const Icon(Icons.add)),
            ]),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final e = items[i];
                  final p = total == 0 ? "--" : (e.weight / total * 100).toStringAsFixed(1);
                  return ListTile(
                    leading: CircleAvatar(backgroundColor: Color(e.color)),
                    title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Text(total == 0 ? "--%" : "$p%"),
                    onLongPress: () => setState(() => items.removeAt(i)),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FilledButton(
                  onPressed: items.length >= 2
                      ? () {
                          final tmp = RouletteDef(
                            id: UniqueKey().toString(),
                            title: "未保存ルーレット",
                            items: List<RouletteItem>.from(items),
                            createdAt: DateTime.now().toIso8601String(),
                            updatedAt: DateTime.now().toIso8601String(),
                          );
                          Navigator.push(context, MaterialPageRoute(builder: (_) => SpinPage(def: tmp)));
                        }
                      : null,
                  child: const Text("▶ 回す"),
                ),
                FilledButton(onPressed: _saveDialog, child: const Text("💾 保存")),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/* ===================== 回す画面（豪華版） ===================== */

class SpinPage extends StatefulWidget {
  final RouletteDef def;
  const SpinPage({super.key, required this.def});
  @override
  State<SpinPage> createState() => _SpinPageState();
}

class _SpinPageState extends State<SpinPage> with TickerProviderStateMixin {
  // アニメ系
  late AnimationController wheelCtrl;     // 本回転（加減速）
  late AnimationController settleCtrl;    // ちょい戻り
  late Animation<double> wheelAnim;
  late Animation<double> settleAnim;

  late AnimationController slotCtrl;      // スロット（スクロール）
  late FixedExtentScrollController listController;

  late AnimationController resultCtrl;    // 結果バウンド
  late Animation<double> resultScale;

  // パーティクル
  late AnimationController particleCtrl;
  List<_Particle> particles = [];

  final rand = Random();
  int? selectedIndex;
  double startAngle = 0.0; // 現在の円盤角度（ラジアン）

  @override
  void initState() {
    super.initState();

    wheelCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200));
    settleCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    slotCtrl   = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200));
    listController = FixedExtentScrollController();

    wheelAnim = TweenSequence<double>([
      TweenSequenceItem(tween: CurveTween(curve: Curves.easeInCubic), weight: 22),
      TweenSequenceItem(tween: CurveTween(curve: Curves.easeOutCubic), weight: 78),
    ]).animate(wheelCtrl);
    settleAnim = CurvedAnimation(parent: settleCtrl, curve: Curves.easeOutBack);

    resultCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
    resultScale = Tween(begin: 1.0, end: 1.12).animate(CurvedAnimation(
      parent: resultCtrl, curve: Curves.easeOutBack));

    particleCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    wheelCtrl.dispose();
    settleCtrl.dispose();
    slotCtrl.dispose();
    resultCtrl.dispose();
    particleCtrl.dispose();
    listController.dispose();
    super.dispose();
  }

  void _spawnParticles(Offset center) {
    particles = List.generate(20, (_) {
      final a = rand.nextDouble() * 2 * pi;
      final v = 90 + rand.nextDouble() * 180; // 速度
      final life = 0.6 + rand.nextDouble() * 0.4;
      final color = Colors.primaries[rand.nextInt(Colors.primaries.length)];
      return _Particle(
        origin: center,
        angle: a,
        velocity: v,
        life: life,
        color: color,
      );
    });
    particleCtrl
      ..reset()
      ..forward();
  }

  void _spin() async {
    final items = widget.def.items;
    if (items.isEmpty) return;

    // 1) 当選（重み付き）
    final weights = items.map((e) => e.weight).toList();
    final total = weights.reduce((a, b) => a + b);
    int r = rand.nextInt(total), acc = 0, idx = 0;
    for (int i = 0; i < weights.length; i++) {
      acc += weights[i];
      if (r < acc) { idx = i; break; }
    }
    setState(() => selectedIndex = idx);

    // 2) 目標角
    final targetAngle = _targetAngleForIndex(idx);

    // 3) スロット中央へ
    listController.animateToItem(idx,
      duration: const Duration(milliseconds: 4200),
      curve: Curves.decelerate);

    // 4) 円盤：ギュン 12回転 + 3%オーバー → ちょい戻し
    final begin = startAngle;
    final spins = 12 * 2 * pi;
    final end   = spins + targetAngle;

    // 本回転
    wheelCtrl
      ..reset()
      ..addListener(() {
        setState(() {
          startAngle = begin + (end - begin) * wheelAnim.value;
        });
      })
      ..forward().whenComplete(() async {
        final overshoot = end + (2 * pi * 0.03);
        setState(() => startAngle = overshoot);

        settleCtrl
          ..reset()
          ..addListener(() {
            setState(() {
              startAngle = overshoot - (overshoot - end) * settleAnim.value;
            });
          })
          ..forward().whenComplete(() async {
            // バウンド & パーティクル
            resultCtrl
              ..reset()
              ..forward();
            _spawnParticles(Offset.zero); // 実描画で中心に変換
            await _updateLastAndBumpSaved();
            // TODO: ここでSE/バイブを鳴らす
          });
      });
  }

  double _targetAngleForIndex(int index) {
    final items = widget.def.items;
    final sum = items.fold<int>(0, (s, e) => s + e.weight);
    double acc = 0;
    for (int i = 0; i < index; i++) {
      acc += items[i].weight / sum;
    }
    final w = items[index].weight / sum;
    final center = acc + w / 2; // [0,1)
    final angleAtCenter = center * 2 * pi;
    return angleAtCenter - pi / 2; // 12時に合わせる
  }

  Future<void> _updateLastAndBumpSaved() async {
    final now = DateTime.now().toIso8601String();
    final def = RouletteDef(
      id: widget.def.id,
      title: widget.def.title,
      items: widget.def.items,
      createdAt: widget.def.createdAt,
      updatedAt: now,
      lastUsedAt: now,
      isPinned: widget.def.isPinned,
    );
    await Store.saveLast(def);

    final saved = await Store.loadSaved();
    final i = saved.indexWhere((e) => e.id == widget.def.id);
    if (i >= 0) {
      saved[i] = def;
      await Store.saveSaved(saved);
    }
  }

  String _displayName(String s) {
    if (s.runes.length <= 10) return s;
    return String.fromCharCodes(s.runes.take(10)) + "……";
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.def.items;
    final sum = items.fold<int>(0, (s, e) => s + e.weight);

    return Scaffold(
      appBar: AppBar(title: Text(widget.def.title)),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _spin,
        child: Container(
          decoration: const BoxDecoration(
            // 背景：縦グラデ
            gradient: LinearGradient(
              colors: [Color(0xFFECF3FF), Color(0xFFFDF7FF)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Stack(
            children: [
              // ほんのりビネット
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _VignettePainter()),
                ),
              ),
              Column(
                children: [
                  const SizedBox(height: 12),
                  // ルーレット円盤＋ポインタ＋パーティクル
                  Expanded(
                    flex: 6,
                    child: LayoutBuilder(
                      builder: (_, c) {
                        final center = Offset(c.maxWidth / 2, c.maxHeight / 2);
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            CustomPaint(
                              painter: _WheelPainter(items: items, total: sum, angle: startAngle),
                              size: Size(c.maxWidth, c.maxHeight),
                            ),
                            // センターハブ（金属風）
                            CustomPaint(
                              size: Size(c.maxWidth, c.maxHeight),
                              painter: _HubPainter(),
                            ),
                            // ポインタ（発光）
                            Align(
                              alignment: Alignment.topCenter,
                              child: Transform.translate(
                                offset: const Offset(0, 10),
                                child: CustomPaint(
                                  size: const Size(30, 30),
                                  painter: _PointerPainterGlow(),
                                ),
                              ),
                            ),
                            // パーティクル
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: _ParticlePainter(
                                    particles: particles,
                                    progress: particleCtrl.value,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  // スロット（中央1行・上下半透明）
                  Expanded(
                    flex: 3,
                    child: ScaleTransition(
                      scale: resultScale,
                      child: ListWheelScrollView.useDelegate(
                        controller: listController,
                        physics: const NeverScrollableScrollPhysics(),
                        itemExtent: 56,
                        perspective: 0.001,
                        overAndUnderCenterOpacity: 0.35,
                        childDelegate: ListWheelChildBuilderDelegate(
                          builder: (_, i) {
                            if (i == null || i < 0 || i >= items.length) return null;
                            final isCenter = i == selectedIndex;
                            return Center(
                              child: Text(
                                _displayName(items[i].name),
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                style: TextStyle(
                                  fontSize: isCenter ? 28 : 22,
                                  fontWeight: isCenter ? FontWeight.w800 : FontWeight.w600,
                                  color: isCenter ? Colors.black : Colors.black.withOpacity(0.7),
                                  shadows: isCenter
                                      ? const [
                                          Shadow(blurRadius: 6, color: Colors.white, offset: Offset(0, 0)),
                                          Shadow(blurRadius: 12, color: Colors.white, offset: Offset(0, 0)),
                                        ]
                                      : null,
                                ),
                              ),
                            );
                          },
                          childCount: items.length,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        FilledButton(onPressed: _spin, child: const Text("▶ もう一度回す")),
                        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text("← ルーレットを選ぶ")),
                        FilledButton(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DefinePage(initial: widget.def))),
                          child: const Text("✎ 編集する"),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ===================== Painterたち ===================== */

// 円盤（扇形＋回る文字＋煌めき）
class _WheelPainter extends CustomPainter {
  final List<RouletteItem> items;
  final int total;
  final double angle; // 現在角（ラジアン）
  _WheelPainter({required this.items, required this.total, required this.angle});

  String _short(String s) => s.runes.length <= 10
      ? s
      : String.fromCharCodes(s.runes.take(10)) + "……";

  @override
  void paint(Canvas canvas, Size size) {
    final rBase  = min(size.width, size.height) * 0.44;
    final center = Offset(size.width / 2, size.height / 2);
    final rect   = Rect.fromCircle(center: center, radius: rBase);

    // 背景
    canvas.drawCircle(center, rBase, Paint()..color = Colors.black.withOpacity(.04));
    if (total <= 0) return;

    // 扇形 & テキスト
    double start = angle;
    for (final e in items) {
      final sweep = (e.weight / total) * 2 * pi;

      // セグメント（放射グラデ）
      final seg = Paint()
        ..style = PaintingStyle.fill
        ..shader = RadialGradient(
          colors: [Color(e.color), Color(e.color).withOpacity(0.9)],
          radius: 0.9,
        ).createShader(rect);
      canvas.drawArc(rect, start, sweep, true, seg);

      // セグメント境界の細線（視認性UP）
      final sep = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = Colors.white.withOpacity(0.85);
      canvas.drawArc(rect, start, sweep, true, sep);

      // 中心角
      final midAngle = start + sweep / 2;
      // ラベル位置
      final labelR   = rBase * 0.62;
      final labelPos = Offset(center.dx + cos(midAngle) * labelR,
                               center.dy + sin(midAngle) * labelR);

      // テキスト
      final span = TextSpan(
        text: _short(e.name),
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      );
      final tp = TextPainter(text: span, textDirection: TextDirection.ltr)..layout(maxWidth: rBase*0.9);

      canvas.save();
      // 文字が円と一緒に回る見た目（読みやすさ優先で+90°）
      canvas.translate(labelPos.dx, labelPos.dy);
      canvas.rotate(midAngle + pi/2);
      tp.paint(canvas, Offset(-tp.width/2, -tp.height/2));
      canvas.restore();

      start += sweep;
    }

    // 外縁
    canvas.drawCircle(center, rBase, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withOpacity(.95));

    // 回転角に同期した「煌めき」スイープ
    final sheen = Paint()
      ..shader = SweepGradient(
        startAngle: angle,
        endAngle: angle + pi/3,
        colors: [
          Colors.white.withOpacity(0.0),
          Colors.white.withOpacity(0.10),
          Colors.white.withOpacity(0.0),
        ],
      ).createShader(rect)
      ..blendMode = BlendMode.plus;
    canvas.drawCircle(center, rBase * .98, sheen);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) =>
      old.items != items || old.total != total || old.angle != angle;
}

// ポインタ（発光）
class _PointerPainterGlow extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..close();

    // グロー
    final glow = Paint()
      ..color = Colors.orangeAccent.withOpacity(0.5)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 8);
    canvas.drawPath(path, glow);

    // 本体
    final body = Paint()..color = Colors.orange.shade700;
    canvas.drawPath(path, body);

    // 縁取り
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withOpacity(0.9);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// 中央ハブ（金属風）
class _HubPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rBase  = min(size.width, size.height) * 0.44;
    final center = Offset(size.width / 2, size.height / 2);

    // 外環
    final r1 = rBase * 0.14;
    final r2 = rBase * 0.10;

    // 放射グラデ
    final outer = Paint()
      ..shader = RadialGradient(
        colors: [Colors.grey.shade300, Colors.grey.shade100],
      ).createShader(Rect.fromCircle(center: center, radius: r1));
    canvas.drawCircle(center, r1, outer);

    final inner = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white, Colors.grey.shade200],
      ).createShader(Rect.fromCircle(center: center, radius: r2));
    canvas.drawCircle(center, r2, inner);

    // 細い十字の装飾
    final line = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(center.dx - r2, center.dy), Offset(center.dx + r2, center.dy), line);
    canvas.drawLine(Offset(center.dx, center.dy - r2), Offset(center.dx, center.dy + r2), line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ほんのりビネット
class _VignettePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.9,
        colors: [Colors.transparent, Colors.black.withOpacity(0.06)],
        stops: const [0.7, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/* ========== パーティクル ========== */

class _Particle {
  final Offset origin;
  final double angle;   // rad
  final double velocity; // px/s
  final double life;    // 秒
  final MaterialColor color;
  _Particle({
    required this.origin,
    required this.angle,
    required this.velocity,
    required this.life,
    required this.color,
  });
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress; // 0..1
  _ParticlePainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (particles.isEmpty) return;
    final center = Offset(size.width / 2, size.height / 2 - size.shortestSide * 0.06);

    for (final p in particles) {
      final t = (progress / p.life).clamp(0.0, 1.0);
      final dist = p.velocity * t * 0.012 * size.shortestSide / 400; // スケール
      final pos = center + Offset(cos(p.angle) * dist, sin(p.angle) * dist);
      final alpha = (1.0 - t).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = p.color.shade400.withOpacity(alpha)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 2.5);
      canvas.drawCircle(pos, 3, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) =>
      old.particles != particles || old.progress != progress;
}
