// ===== BLOCK 1: imports & main =====
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';




// ===== UTIL: outlined text & color tweak =====
Color _shade(Color c, {double lightnessDelta = -0.08}) {
  final hsl = HSLColor.fromColor(c);
  final l = (hsl.lightness + lightnessDelta).clamp(0.0, 1.0);
  return hsl.withLightness(l).toColor();
}

/// アウトライン付きテキスト描画（キャンバスに直描き）
/// - pos は左上ではなく「テキスト中央」を置きたい座標を渡す
/// - maxWidth で自動改行（最大2行）、長文は省略記号
void paintOutlinedText(
    Canvas canvas, {
      required Offset center,
      required String text,
      double fontSize = 14,
      Color fillColor = Colors.white,
      Color outlineColor = Colors.black,
      double outlineWidth = 2.0,
      double maxWidth = 120,
      TextAlign align = TextAlign.center,
    }) {
  // 本文
  final base = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: fontSize,
        height: 1.1,
        fontWeight: FontWeight.w800,
        color: fillColor,
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: align,
    maxLines: 2,
    ellipsis: "…",
  )..layout(maxWidth: maxWidth);

  // アウトライン（8方向にオフセット描画）
  final outline = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: fontSize,
        height: 1.1,
        fontWeight: FontWeight.w900,
        color: outlineColor,
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
    Offset(-outlineWidth, 0),
    Offset(outlineWidth, 0),
    Offset(0, -outlineWidth),
    Offset(0, outlineWidth),
    Offset(-outlineWidth, -outlineWidth),
    Offset(-outlineWidth, outlineWidth),
    Offset(outlineWidth, -outlineWidth),
    Offset(outlineWidth, outlineWidth),
  ];
  for (final o in offsets) {
    outline.paint(canvas, center + Offset(dx, dy) + o);
  }
  base.paint(canvas, center + Offset(dx, dy));
}


void main() => runApp(const RouletteApp());

class RouletteApp extends StatelessWidget {
  const RouletteApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ルーレット',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue, // ← 既存の colorSchemeSeed を活かす
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(120, 44),                // 触りやすい最小サイズ
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.3),
          ),
        ),
        // 他のTheme設定があればここに残してOK
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

// ===== BLOCK 3: root page (home) — simple, fixed create button, floating snackbars =====
class RootPage extends StatefulWidget {
  const RootPage({super.key});
  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  RouletteDef? last;
  List<RouletteDef> saved = [];

  // スナックバー（下固定ボタンに被らないよう浮かせる）
  SnackBar _okBar(String msg) => SnackBar(
    content: Text(msg),
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
  );

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
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(_okBar("削除しました"));
    }
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

  Future<void> _goDefine({RouletteDef? initial}) async {
    // 戻り値は使わない（＝一覧で削除する押下時も単に戻るだけ）
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DefinePage(initial: initial)),
    );
    if (!mounted) return;
    await _loadAll();
  }

  Widget _savedTile(RouletteDef d) {
    final preview =
        d.items.take(3).map((e) => e.name).join(", ") + (d.items.length > 3 ? "…" : "");
    final pinned = d.isPinned;

    return Card(
      child: ListTile(
        leading: Icon(pinned ? Icons.push_pin : Icons.circle_outlined),
        title: Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == "pin") _togglePin(d.id, !pinned);
            if (v == "edit") _goDefine(initial: d);
            if (v == "del") _deleteSaved(d.id);
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: "pin", child: Text(pinned ? "ピン解除" : "ピン留め")),
            const PopupMenuItem(value: "edit", child: Text("編集")),
            const PopupMenuItem(value: "del", child: Text("削除")),
          ],
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SpinPage(def: d)),
        ).then((_) => _loadAll()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pinned = saved.where((e) => e.isPinned).toList();
    final others = saved.where((e) => !e.isPinned).toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.casino, size: 26),
            const SizedBox(width: 8),
            const Text(
              "ルーレット一覧",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        centerTitle: false,
      ),

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
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => SpinPage(def: last!)),
                          ).then((_) => _loadAll()),
                          child: const Text("▶ 回す"),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: () => _goDefine(initial: last),
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
          if (pinned.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text("📌 ピン留め"),
            ),
          ...pinned.map(_savedTile),
          if (others.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text("最近使った順"),
            ),
          ...others.map(_savedTile),
          const SizedBox(height: 100), // 最下部の安全マージン
        ],
      ),

      // 👇 ここが変更ポイント！bottomNavigationBar を削除して floatingActionButton に
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _goDefine(),
        icon: const Icon(Icons.add, size: 30),
        label: const Text(
          "新規作成",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        // 少し大きめに
        extendedPadding: const EdgeInsets.symmetric(horizontal: 24),
        // 色統一
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}



// ===== BLOCK 4: define page — responsive inputs, default numbering, save limit dialog =====
class DefinePage extends StatefulWidget {
  final RouletteDef? initial;
  const DefinePage({super.key, this.initial});
  @override
  State<DefinePage> createState() => _DefinePageState();
}

class _DefinePageState extends State<DefinePage> {
  // 追加用（常に表示・追加後も残す）
  final _newNameCtl = TextEditingController();
  final _newWeightCtl = TextEditingController(text: "1");
  final _newPercent = ValueNotifier<String>("--%");
  final _newNameFocus = FocusNode();

  // 行ごとコントローラ（常時編集）
  final List<TextEditingController> _nameCtls = [];
  final List<TextEditingController> _weightCtls = [];

  List<RouletteItem> items = [];

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) items = List<RouletteItem>.from(widget.initial!.items);
    _rebuildControllers();
    _newWeightCtl.addListener(_updateNewPercent);
    _updateNewPercent();
  }

  @override
  void dispose() {
    _newNameCtl.dispose();
    _newWeightCtl.dispose();
    _newPercent.dispose();
    _newNameFocus.dispose();
    for (final c in _nameCtls) c.dispose();
    for (final c in _weightCtls) c.dispose();
    super.dispose();
  }

  int get totalWeight => items.fold<int>(0, (s, e) => s + e.weight);

  void _rebuildControllers() {
    for (final c in _nameCtls) c.dispose();
    for (final c in _weightCtls) c.dispose();
    _nameCtls
      ..clear()
      ..addAll(items.map((e) => TextEditingController(text: e.name)));
    _weightCtls
      ..clear()
      ..addAll(items.map((e) => TextEditingController(text: e.weight.toString())));
    for (int i = 0; i < _weightCtls.length; i++) {
      _weightCtls[i].addListener(() => _applyEdit(i));
    }
    for (int i = 0; i < _nameCtls.length; i++) {
      _nameCtls[i].addListener(() => _applyEdit(i));
    }
    setState(() {});
  }

  void _applyEdit(int index) {
    if (index < 0 || index >= items.length) return;
    final name = _nameCtls[index].text;
    var w = int.tryParse(_weightCtls[index].text) ?? items[index].weight;
    w = w.clamp(1, 100);
    items[index] = RouletteItem(name: name, weight: w, color: items[index].color);
    setState(() {}); // % 再計算用
  }

  void _updateNewPercent() {
    final w = int.tryParse(_newWeightCtl.text) ?? 1;
    final tot = totalWeight + max(1, w);
    final p = tot == 0 ? "--" : (w / tot * 100).toStringAsFixed(1);
    _newPercent.value = "$p%";
  }

  void _add() {
    final name = _newNameCtl.text.trim();
    if (name.isEmpty) {
      _newNameFocus.requestFocus();
      return;
    }
    if (items.length >= 100) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("最大100件までです")));
      return;
    }
    var w = int.tryParse(_newWeightCtl.text) ?? 1;
    w = w.clamp(1, 100);
    setState(() {
      final color = Colors.primaries[items.length % Colors.primaries.length]
          .shade400
          .value;
      items.add(RouletteItem(name: name, weight: w, color: color));
      _newNameCtl.clear();
      _newWeightCtl.text = "1";
      _updateNewPercent();
      _rebuildControllers();
      _newNameFocus.requestFocus();
    });
  }

  // 欠番の最小Nで「ルーレットN」を返す
  String _nextDefaultTitle(List<RouletteDef> saved) {
    final used = <int>{};
    final re = RegExp(r'^ルーレット(\d+)$');
    for (final d in saved) {
      final m = re.firstMatch(d.title);
      if (m != null) {
        final n = int.tryParse(m.group(1) ?? '');
        if (n != null) used.add(n);
      }
    }
    int n = 1;
    while (used.contains(n)) n++;
    return "ルーレット$n";
  }

  Future<void> _saveDialog() async {
    if (items.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("候補は2件以上必要です")),
      );
      return;
    }
    final saved = await Store.loadSaved();
    final defaultTitle = _nextDefaultTitle(saved);

    final titleCtl = TextEditingController(text: defaultTitle);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("ルーレットを保存"),
        content: TextField(
          controller: titleCtl,
          maxLength: 100,
          decoration:
          const InputDecoration(labelText: "タイトル（100文字まで）"),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("キャンセル")),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("保存")),
        ],
      ),
    );
    if (ok != true) return;

    var title = titleCtl.text.trim().isEmpty
        ? defaultTitle
        : titleCtl.text.trim();

    // タイトル重複は末尾に数字を足して回避
    if (saved.any((e) => e.title == title)) {
      int n = 2;
      while (saved.any((e) => e.title == "$title$n")) n++;
      title = "$title$n";
    }

    // 上限チェック（サイレント削除しない）
    const maxSaves = 100;
    if (saved.length >= maxSaves) {
      if (context.mounted) {
        final goList = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("保存数の上限"),
            content: const Text("ルーレット保存数が上限に達しています。\n不要なルーレットを削除してください。"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("閉じる"),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("一覧で削除する"),
              ),
            ],
          ),
        );

        if (goList == true) {
          // ★ どこから来ていても RootPage（最初のRoute＝一覧）まで戻る
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }
      return; // 保存処理はしない
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
    await Store.saveSaved(saved);
    await Store.saveLast(def);

    if (!mounted) return;
    // RootPage側の下固定ボタンに被らないスナックバー（RootPageでも定義してるが、ここでも安全に浮かせる）
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("保存しました"),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final sum = totalWeight;

    return Scaffold(
      appBar: AppBar(
          title:
          Text(widget.initial == null ? "新規ルーレット作成" : "ルーレット編集")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 新規入力エリア：項目名を広め・比率は柔軟に縮む
            Card(
              elevation: 1.5,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("新規項目を追加",
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 8),
                    // ← ここから置換（Row → Column 縦積み）
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 項目名：フル幅
                        TextField(
                          focusNode: _newNameFocus,
                          controller: _newNameCtl,
                          maxLength: 100,
                          decoration: const InputDecoration(
                            labelText: "項目名（100文字まで）",
                            counterText: "",
                          ),
                        ),
                        const SizedBox(height: 8),

                        // 比率 + %：横並び（必要に応じて縮む）
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _newWeightCtl,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                decoration: const InputDecoration(
                                  labelText: "比率", // ← （1-100）の括弧はやめて短く
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ValueListenableBuilder<String>(
                              valueListenable: _newPercent,
                              builder: (_, v, __) => Text(
                                v, // 例: "23.1%"
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),

                        // 追記：少し補足（任意なら消してOK）
                        const SizedBox(height: 4),
                        const Text(
                          "※ 比率は1〜100、%は現在の合計に対する目安です。",
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),

                        const SizedBox(height: 12),

                        // 追加ボタン：下にフル幅で
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _add,
                            icon: const Icon(Icons.add),
                            label: const Text("追加"),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 4),
                    const Text("※ このカードは“入力中”。下の一覧は“追加済み”。",
                        style:
                        TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ),
            ),

            const Align(
              alignment: Alignment.centerLeft,
              child: Text("追加済みの項目",
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            const SizedBox(height: 6),

            // 追加済みリスト（白背景のまま・レスポンシブ）
            Expanded(
              child: ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final e = items[i];
                  final p = sum == 0
                      ? "--"
                      : (e.weight / sum * 100).toStringAsFixed(1);
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 6, horizontal: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: CircleAvatar(
                              backgroundColor: Color(e.color), radius: 9),
                        ),
                        // 項目名（広く取る）
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _nameCtls[i],
                            maxLength: 100,
                            decoration: const InputDecoration(
                              labelText: "項目名",
                              counterText: "",
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // 比率（最小幅を確保しつつ縮む）
                        Flexible(
                          flex: 1,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: TextField(
                                  controller: _weightCtls[i],
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: "比率",
                                    isDense: true,
                                  ),
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                sum == 0 ? "--%" : "$p%",
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    color: Colors.black87),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: "削除",
                          onPressed: () {
                            setState(() {
                              items.removeAt(i);
                            });
                            _rebuildControllers();
                          },
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // アクション
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: items.length >= 2 ? () {
                    final tmp = RouletteDef(
                      id: UniqueKey().toString(),
                      title: "未保存ルーレット",
                      items: List<RouletteItem>.from(items),
                      createdAt: DateTime.now().toIso8601String(),
                      updatedAt: DateTime.now().toIso8601String(),
                    );
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => SpinPage(def: tmp)),
                    );
                  } : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text("回す"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _saveDialog,
                  icon: const Icon(Icons.save),
                  label: const Text("保存"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                    foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
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


// ===== BLOCK 5: spin page (cached wheel image, wait full 5s, overlay result after stop) =====
class SpinPage extends StatefulWidget {
  final RouletteDef def;
  const SpinPage({super.key, required this.def});
  @override
  State<SpinPage> createState() => _SpinPageState();
}

class _SpinPageState extends State<SpinPage> with TickerProviderStateMixin {
  late AnimationController wheelCtrl;
  late Animation<double> wheelAnim;

  final rand = Random();
  bool _spinning = false;     // 回転中ガード
  double _angle = 0.0;        // 現在角度
  String? _resultName;        // 停止後のみセット & 表示

  static const _spinDuration = Duration(milliseconds: 5000); // ★5秒回す
  static const _spinsCount = 15; // ★回転数（体感調整用）

  // --- 高速化：円盤を一度だけ画像に描いてキャッシュ ---
  ui.Image? _wheelImage;
  Size? _wheelImageSize;
  bool _buildingImage = false;

  @override
  void initState() {
    super.initState();
    wheelCtrl = AnimationController(vsync: this, duration: _spinDuration);
  }

  @override
  void didUpdateWidget(covariant SpinPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 編集して戻ってきたなど、項目が変わったら画像キャッシュ破棄
    if (oldWidget.def.items != widget.def.items) {
      _wheelImage?.dispose();
      _wheelImage = null;
      _wheelImageSize = null;
    }
  }

  @override
  void dispose() {
    wheelCtrl.dispose();
    _wheelImage?.dispose();
    super.dispose();
  }

  Future<void> _spin() async {
    if (_spinning || _resultName != null) return; // 結果表示中は回せない
    final items = widget.def.items;
    if (items.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("候補は2件以上必要です")));
      return;
    }

    setState(() {
      _spinning = true;
      _resultName = null; // 前回結果を消す
    });

    // 大きめ・丸め角・フル幅の共通ボタン
    Widget _bigButtonSolid({
      required BuildContext context,
      required String label,
      required IconData icon,
      required VoidCallback? onPressed,
      required Color bg,
      required Color fg,
    }) {
      return SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
          style: FilledButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      );
    }

    Widget _bigButtonTonal({
      required BuildContext context,
      required String label,
      required IconData icon,
      required VoidCallback? onPressed,
      required Color bg,
      required Color fg,
    }) {
      return SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton.tonal(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon),
              const SizedBox(width: 10),
              Text(label),
            ],
          ),
        ),
      );
    }


    // --- 重み付き抽選で idx 決定 ---
    final weights = items.map((e) => e.weight).toList();
    final total = weights.reduce((a, b) => a + b);
    int r = rand.nextInt(total), acc = 0, idx = 0;
    for (int i = 0; i < weights.length; i++) { acc += weights[i]; if (r < acc) { idx = i; break; } }

    // idx に対応する停止角（上ポインタ基準で中央に来る）
    final targetAngle = _targetAngleForIndex(idx);

    final begin = _angle;
    final end = begin + _spinsCount * 2 * pi + _normalizeDelta(begin, targetAngle);

    // --- 5秒アニメーション（easeOut） ---
    wheelAnim = CurvedAnimation(parent: wheelCtrl, curve: Curves.easeOutCubic);
    wheelCtrl
      ..reset()
      ..addListener(() {
        setState(() {
          _angle = begin + (end - begin) * wheelAnim.value;
        });
      });
    await wheelCtrl.forward(); // ★ 完全停止まで待つ

    // --- 停止と同時にだけ結果表示 ---
    setState(() {
      _angle = end;                 // 念のため最終角度に固定
      _spinning = false;
      _resultName = items[idx].name;
    });

    await _updateLastAndBumpSaved();
  }

  // begin から target まで“正方向の最短差”に正規化
  double _normalizeDelta(double begin, double target) {
    double d = target - (begin % (2 * pi));
    while (d < 0) d += 2 * pi;
    return d;
  }

  // 上のポインタに対して index セグメントの中心角を返す（上＝-π/2 位置）
  double _targetAngleForIndex(int index) {
    final items = widget.def.items;
    final sum = items.fold<int>(0, (s, e) => s + e.weight);
    double acc = 0;
    for (int i = 0; i < index; i++) acc += items[i].weight / sum;
    final w = items[index].weight / sum;
    final center = acc + w / 2;          // 0..1 の中心位置
    double a = -center * 2 * pi;         // 時計回りを正として上に合わせる
    while (a < 0) a += 2 * pi;
    return a;
  }

  String _displayName(String s) =>
      s.runes.length <= 12 ? s : String.fromCharCodes(s.runes.take(12)) + "…";

  Future<void> _updateLastAndBumpSaved() async {
    final now = DateTime.now().toIso8601String();
    final d = widget.def;
    final def = RouletteDef(
      id: d.id, title: d.title, items: d.items,
      createdAt: d.createdAt, updatedAt: now, lastUsedAt: now, isPinned: d.isPinned,
    );
    await Store.saveLast(def);
    final saved = await Store.loadSaved();
    final i = saved.indexWhere((e) => e.id == d.id);
    if (i >= 0) { saved[i] = def; await Store.saveSaved(saved); }
  }

  void _resetForNext() {
    setState(() {
      _resultName = null; // 結果を消して次のスピンを許可
    });
  }

  // 保存時のデフォルト名（DefinePageと同等のロジック）
  Future<String> _nextDefaultTitleForSave() async {
    final saved = await Store.loadSaved();
    final used = <int>{};
    final re = RegExp(r'^ルーレット(\d+)$');
    for (final d in saved) {
      final m = re.firstMatch(d.title);
      if (m != null) {
        final n = int.tryParse(m.group(1) ?? '');
        if (n != null) used.add(n);
      }
    }
    int n = 1;
    while (used.contains(n)) n++;
    return "ルーレット$n";
  }

// スピン画面からの保存ダイアログ（保存後もこの画面に留まる）
  Future<void> _saveFromSpinWithDialog() async {
    if (widget.def.items.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("候補は2件以上必要です")));
      }
      return;
    }

    final saved = await Store.loadSaved();
    final defaultTitle = await _nextDefaultTitleForSave();

    final titleCtl = TextEditingController(text: defaultTitle);
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

    var title = titleCtl.text.trim().isEmpty ? defaultTitle : titleCtl.text.trim();

    // タイトル重複は末尾に数字を足して回避
    if (saved.any((e) => e.title == title)) {
      int n = 2;
      while (saved.any((e) => e.title == "$title$n")) n++;
      title = "$title$n";
    }

    final now = DateTime.now().toIso8601String();
    final d = widget.def;

    // 既に同IDが保存済みなら上書き（タイトルは新しいものに）
    final idx = saved.indexWhere((e) => e.id == d.id);
    final def = RouletteDef(
      id: d.id,
      title: title,
      items: List<RouletteItem>.from(d.items),
      createdAt: idx >= 0 ? saved[idx].createdAt : now,
      updatedAt: now,
      lastUsedAt: now,
      isPinned: idx >= 0 ? saved[idx].isPinned : false,
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


  // 既存の保存済み一覧から「ルーレットN」の次番号を決める
  Future<String> _nextDefaultTitle() async {
    final saved = await Store.loadSaved();
    final used = <int>{};
    final re = RegExp(r'^ルーレット(\d+)$');
    for (final d in saved) {
      final m = re.firstMatch(d.title);
      if (m != null) {
        final n = int.tryParse(m.group(1) ?? '');
        if (n != null) used.add(n);
      }
    }
    int n = 1;
    while (used.contains(n)) n++;
    return "ルーレット$n";
  }

// SpinPage から即保存（すでに保存済みなら updated/lastUsed を更新）
  Future<void> _quickSave() async {
    final now = DateTime.now().toIso8601String();
    final d = widget.def;
    final saved = await Store.loadSaved();
    final idx = saved.indexWhere((e) => e.id == d.id);

    if (idx >= 0) {
      final updated = RouletteDef(
        id: d.id,
        title: saved[idx].title, // 既存タイトル維持
        items: d.items,
        createdAt: saved[idx].createdAt,
        updatedAt: now,
        lastUsedAt: now,
        isPinned: saved[idx].isPinned,
      );
      saved[idx] = updated;
      await Store.saveSaved(saved);
      await Store.saveLast(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("保存を更新しました")),
        );
      }
      return;
    }

    final title = await _nextDefaultTitle();
    final def = RouletteDef(
      id: d.id,
      title: title,
      items: List<RouletteItem>.from(d.items),
      createdAt: now,
      updatedAt: now,
      lastUsedAt: now,
      isPinned: false,
    );
    saved.insert(0, def);
    await Store.saveSaved(saved);
    await Store.saveLast(def);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("保存しました")),
      );
    }
  }


  // 円周の「半径方向」に合わせて回転（文字の“下”が中心側＝内向き）
  void _paintRadialTextInward(
      Canvas canvas, {
        required Offset center,
        required String text,
        required double midAngle,          // セグメント中央角（rad）
        required double radiusForMaxWidth, // 行幅の上限見積り
        double fontSize = 14,
        Color fillColor = Colors.white,
        Color outlineColor = Colors.black,
        double outlineWidth = 2,
      }) {
    // ラベルは「内向き（中心へ向けて下向き）」にしたいので
    // キャンバスを “半径方向” に合わせて回す: rot = midAngle + π
    // （通常のテキストは上が -Y ＝画面上なので、π 回転で下が中心側に来る）
    double rot = midAngle + pi;

    // テキストを描画
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: fillColor,
          shadows: [
            Shadow(
              offset: const Offset(0, 0),
              blurRadius: 0,
              color: outlineColor,
            ),
          ],
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: radiusForMaxWidth);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rot);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }



  // ---- 共通ボタンヘルパー ----
  Widget _bigButtonSolid({
    required BuildContext context,
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    required Color bg,
    required Color fg,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _bigButtonTonal({
    required BuildContext context,
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    required Color bg,
    required Color fg,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.tonal(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon),
            const SizedBox(width: 10),
            Text(label),
          ],
        ),
      ),
    );
  }


  // ---------- ここから：BLOCK5内だけで完結する描画ユーティリティ ----------
  Color _shade(Color c, {double lightnessDelta = -0.08}) {
    final hsl = HSLColor.fromColor(c);
    final l = (hsl.lightness + lightnessDelta).clamp(0.0, 1.0);
    return hsl.withLightness(l).toColor();
  }

  // アウトライン付きテキスト（中央座標指定・最大2行）
// 互換性のため outlineColor / outlineWidth を残しつつ、未指定なら自動調整します。
// 任意で bgColor を渡すと縁色の自動判定がより賢くなります。
  void _paintOutlinedText(
      Canvas canvas, {
        required Offset center,
        required String text,
        double fontSize = 14,
        Color fillColor = Colors.white,
        double maxWidth = 120,
        TextAlign align = TextAlign.center,

        // 既存呼び出し互換
        Color? outlineColor,
        double? outlineWidth,

        // 追加: 背景色（あれば縁色を自動決定に利用）
        Color? bgColor,
      }) {
    // アウトライン幅：指定なければフォントサイズから算出（細字ほど細く）
    final ow = (outlineWidth ?? (fontSize / 7)).clamp(1.0, 2.2);

    // 縁色：指定なければ背景の明暗から自動
    final oc = outlineColor ??
        ((bgColor != null &&
            ThemeData.estimateBrightnessForColor(bgColor) ==
                Brightness.dark)
            ? Colors.white.withOpacity(0.85)
            : Colors.black.withOpacity(0.9));

    // 本体（太すぎると潰れるので w600）
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

    // 縁（やや太め w800）
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

    // 8方向オフセット（必要十分の4方向でもOKだが読みやすさ優先）
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
      outline.paint(canvas, center + Offset(dx, dy) + o);
    }
    base.paint(canvas, center + Offset(dx, dy));
  }


  // ---------- ここまでユーティリティ ----------

  // ================== 高速化：一度だけ画像に描画 ==================
  Future<void> _ensureWheelImage(Size size) async {
    if (_buildingImage) return;
    if (_wheelImage != null &&
        _wheelImageSize != null &&
        (size.width - _wheelImageSize!.width).abs() < 1 &&
        (size.height - _wheelImageSize!.height).abs() < 1) return;

    _buildingImage = true;
    try {
      final items = widget.def.items;
      final total = items.fold<int>(0, (s, e) => s + e.weight);
      final dpr = ui.window.devicePixelRatio;
      final w = (size.width * dpr).toInt().clamp(64, 4096);
      final h = (size.height * dpr).toInt().clamp(64, 4096);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
      canvas.scale(dpr, dpr);

      final r = (size.shortestSide * 0.44);
      final center = Offset(size.width / 2, size.height / 2);
      final rect = Rect.fromCircle(center: center, radius: r);

      // うっすら外縁
      final bg = Paint()..color = Colors.black.withOpacity(.04);
      canvas.drawCircle(center, r, bg);

      if (total > 0) {
        double start = -pi / 2; // 上基準
        final segPaint = Paint()..style = PaintingStyle.fill;
        final sepPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white.withOpacity(0.85);

        for (final it in items) {
          final sweep = (it.weight / total) * 2 * pi;

          // --- セグメント塗り（放射グラデーションで外周を少し明るく）
          final base = Color(it.color);
          segPaint.shader = RadialGradient(
            colors: [
              _shade(base, lightnessDelta: -0.05), // 内側やや暗め
              base,                                 // 中間
              _shade(base, lightnessDelta: 0.06), // 外周ほんのり明るく
            ],
            stops: const [0.0, 0.82, 1.0],
            center: Alignment.center,
            radius: 0.98,
          ).createShader(rect);
          canvas.drawArc(rect, start, sweep, true, segPaint);

          // セパレーターの白細線
          canvas.drawArc(rect, start, sweep, true, sepPaint);

          // --- ラベル（内向き）※セクターからはみ出さない
          final frac = it.weight / total;
          final fs = (12 + (frac * 24)).clamp(12, 20).toDouble();
          final mid = start + sweep / 2;
          final labelR = r * 0.62;
          final labelCenter = Offset(
            center.dx + cos(mid) * labelR,
            center.dy + sin(mid) * labelR,
          );

// 1) このセグメントのパスを作成（中心→弧→中心）
          final segPath = Path()
            ..moveTo(center.dx, center.dy)
            ..arcTo(rect, start, sweep, false)
            ..close();

// 2) ラベルが置かれる半径での弧の弦長（＝許容幅の上限）
          final chord = 2 * labelR * sin(sweep / 2);
          final maxW = chord * 0.88; // ちょい内側に寄せる

          canvas.save();
          canvas.clipPath(segPath);          // ← セクターでクリップ
// 内向きに回転して中央に描画、幅は maxW までに制限（ellipsis は内部で）
          _paintRadialTextInward(
            canvas,
            center: labelCenter,
            text: it.name,
            midAngle: mid,
            radiusForMaxWidth: maxW,
            fontSize: fs,
            fillColor: Colors.white,
            outlineColor: Colors.black,
            outlineWidth: (fs / 7).clamp(1.0, 2.2),
          );
          canvas.restore();




          start += sweep;
        }

        // ハブ
        final hub = Paint()..color = Colors.white;
        canvas.drawCircle(center, r * 0.12, hub);
        final hubStroke = Paint()
          ..color = Colors.black.withOpacity(.08)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
        canvas.drawCircle(center, r * 0.12, hubStroke);
      }

      final picture = recorder.endRecording();
      final image = await picture.toImage(w, h);

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
    final sum = items.fold<int>(0, (s, e) => s + e.weight);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: true, // ← 戻る矢印だけ出す
        title: const SizedBox.shrink(),  // ← タイトルは何も表示しない
      ),


      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: (_spinning || _resultName != null) ? null : _spin, // 結果表示中は無効
        child: Stack(
          children: [
            // ---- 円盤本体（画像キャッシュで超軽量） ----
            Column(
              children: [
                const SizedBox(height: 12),
                Expanded(
                  flex: 8,
                  child: LayoutBuilder(builder: (_, c) {
                    final sz = Size(c.maxWidth, c.maxHeight);
                    _ensureWheelImage(sz); // 非同期生成。生成中はフォールバック。
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        if (_wheelImage != null && _wheelImageSize != null)
                          CustomPaint(
                            size: sz,
                            painter: _ImageWheelPainter(image: _wheelImage!, angle: _angle),
                          )
                        else
                          CustomPaint(
                            size: sz,
                            painter: _WheelFallbackPainter(
                              items: items,
                              total: sum,
                              angle: _angle,
                              shade: _shade,
                              paintOutlinedText: _paintOutlinedText,
                            ),
                          ),
                        CustomPaint(size: sz, painter: _HubPainter()),
                        Align(
                          alignment: Alignment.topCenter,
                          child: Transform.translate(
                            offset: const Offset(0, 10),
                            child: CustomPaint(size: const Size(30, 30), painter: _PointerPainterGlow()),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
                const SizedBox(height: 16),
                if (!_spinning && _resultName == null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _saveFromSpinWithDialog,        // ← 保存ダイアログを呼ぶ
                          icon: const Icon(Icons.save_alt),
                          label: const Text("保存する"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => DefinePage(initial: widget.def)),
                          ),
                          icon: const Icon(Icons.edit),
                          label: const Text("編集する"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                            foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),

              ],
            ),


            // ---- 結果オーバーレイ（停止後のみ）----
            if (_resultName != null)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.40),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 当選名（中央ドン）
                          Text(
                            _displayName(_resultName!),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 56,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.3,
                              shadows: [Shadow(offset: Offset(1, 2), blurRadius: 6, color: Colors.black87)],
                            ),
                          ),
                          const SizedBox(height: 28),

                          // 縦並びボタン：一番上だけ少し大きい
                          ElevatedButton.icon(
                            onPressed: _resetForNext,
                            icon: const Icon(Icons.refresh, size: 26),
                            label: const Text("もう一度回す"),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(260, 54),   // ← 少し大きめ
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              foregroundColor: Theme.of(context).colorScheme.onPrimary,
                              textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(height: 12),

                          ElevatedButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.list_alt),
                            label: const Text("ルーレットを選ぶ"),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(240, 46),
                              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                              foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
                            ),
                          ),
                          const SizedBox(height: 10),

                          ElevatedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => DefinePage(initial: widget.def)),
                            ),
                            icon: const Icon(Icons.edit),
                            label: const Text("編集する"),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(240, 46),
                              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                              foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
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
    );
  }
}

// ---------- 画像を回すだけの軽量ペインタ ----------
class _ImageWheelPainter extends CustomPainter {
  final ui.Image image;
  final double angle;
  _ImageWheelPainter({required this.image, required this.angle});

  @override
  void paint(Canvas canvas, Size size) {
    final dpr = ui.window.devicePixelRatio;
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawImageRect(image, src, dst, Paint()..isAntiAlias = true..filterQuality = FilterQuality.medium);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ImageWheelPainter old) => old.image != image || old.angle != angle;
}

// ---------- フォールバック（画像生成中だけ一瞬使う） ----------
class _WheelFallbackPainter extends CustomPainter {
  final List<RouletteItem> items;
  final int total;
  final double angle;

  // SpinPage内のユーティリティを橋渡し（関数参照を受け取る）
  final Color Function(Color c, {double lightnessDelta}) shade;
  final void Function(Canvas canvas,
      {required Offset center,
      required String text,
      double fontSize,
      Color fillColor,
      Color outlineColor,
      double outlineWidth,
      double maxWidth,
      TextAlign align}) paintOutlinedText;

  _WheelFallbackPainter({
    required this.items,
    required this.total,
    required this.angle,
    required this.shade,
    required this.paintOutlinedText,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.shortestSide * 0.44);
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: r);

    // 外縁のうっすら影
    canvas.drawCircle(center, r, Paint()..color = Colors.black.withOpacity(.04));
    if (total <= 0) return;

    double start = angle - pi / 2; // 上基準
    final segPaint = Paint()..style = PaintingStyle.fill;
    final sepPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withOpacity(0.85);

    for (final it in items) {
      final sweep = (it.weight / total) * 2 * pi;

      final base = Color(it.color);
      segPaint.shader = RadialGradient(
        colors: [
          shade(base, lightnessDelta: -0.05),
          base,
          shade(base, lightnessDelta: 0.06),
        ],
        stops: const [0.0, 0.82, 1.0],
        center: Alignment.center,
        radius: 0.98,
      ).createShader(rect);
      canvas.drawArc(rect, start, sweep, true, segPaint);
      canvas.drawArc(rect, start, sweep, true, sepPaint);

      // ラベル（フォールバックなので控えめサイズ）
      final frac = it.weight / total;
      final fs = (12 + (frac * 24)).clamp(12, 18).toDouble();
      final mid = start + sweep / 2;
      final labelR = r * 0.62;
      final labelCenter = Offset(
        center.dx + cos(mid) * labelR,
        center.dy + sin(mid) * labelR,
      );
      // 半径方向・内向きに回してから、(0,0) 中心に描画
      canvas.save();
      canvas.translate(labelCenter.dx, labelCenter.dy);
      canvas.rotate(mid + pi); // ← 内向き
      // セクターパス
      final segPath = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(rect, start, sweep, false)
        ..close();

// ラベル半径での弦長を上限とする
      final chord = 2 * labelR * sin(sweep / 2);
      final maxW = chord * 0.88;

      canvas.save();
      canvas.clipPath(segPath);           // ← はみ出し防止
      canvas.translate(labelCenter.dx, labelCenter.dy);
      canvas.rotate(mid + pi);            // ← 内向き（中心側が“下”）

      paintOutlinedText(
        canvas,
        center: Offset.zero,
        text: it.name,
        fontSize: fs,
        fillColor: Colors.white,
        outlineColor: Colors.black,
        outlineWidth: 2.0,
        maxWidth: maxW,                   // ← 幅制限
        align: TextAlign.center,
      );
      canvas.restore();


      start += sweep;
    }

    // 中心ハブ（簡易）
    final hub = Paint()..color = Colors.white;
    canvas.drawCircle(center, r * 0.12, hub);
  }

  @override
  bool shouldRepaint(covariant _WheelFallbackPainter old) =>
      old.items != items || old.total != total || old.angle != angle;
}



// ===== BLOCK 6: painters =====
class _WheelPainter extends CustomPainter {
  final List<RouletteItem> items;
  final int total;
  final double angle;
  _WheelPainter({required this.items, required this.total, required this.angle});

  String _short(String s) => s.runes.length <= 10 ? s : String.fromCharCodes(s.runes.take(10)) + "……";

  @override
  void paint(Canvas canvas, Size size) {
    final r = min(size.width, size.height) * 0.44;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: r);
    canvas.drawCircle(center, r, Paint()..color = Colors.black.withOpacity(.04));
    if (total <= 0) return;

    double start = angle - pi / 2;
    for (final e in items) {
      final sweep = (e.weight / total) * 2 * pi;

      final seg = Paint()
        ..style = PaintingStyle.fill
        ..shader = RadialGradient(
          colors: [Color(e.color), Color(e.color).withOpacity(0.9)],
          radius: 0.9,
        ).createShader(rect);
      canvas.drawArc(rect, start, sweep, true, seg);

      final sep = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = Colors.white.withOpacity(0.85);
      canvas.drawArc(rect, start, sweep, true, sep);

      final mid = start + sweep / 2;
      final labelR = r * 0.62;
      final labelPos = Offset(center.dx + cos(mid) * labelR, center.dy + sin(mid) * labelR);

      final tp = TextPainter(
        text: TextSpan(text: _short(e.name), style: const TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: r * 0.9);

      canvas.save();
      canvas.translate(labelPos.dx, labelPos.dy);
      canvas.rotate(mid + pi / 2);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();

      start += sweep;
    }

    canvas.drawCircle(center, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = Colors.white.withOpacity(.95));

    final sheen = Paint()
      ..shader = SweepGradient(
        startAngle: angle, endAngle: angle + pi / 3,
        colors: [Colors.white.withOpacity(0), Colors.white.withOpacity(0.1), Colors.white.withOpacity(0)],
      ).createShader(rect)
      ..blendMode = BlendMode.plus;
    canvas.drawCircle(center, r * .98, sheen);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) => old.items != items || old.total != total || old.angle != angle;
}

// ===== PATCH: pointer painter — tip points DOWN toward the wheel =====
class _PointerPainterGlow extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    // 影(グロー)
    final glow = Paint()
      ..color = Colors.redAccent.withOpacity(0.28)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    // 本体
    final fill = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.fill;

    // 縁取り
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // ▼ 下向き三角形（アラインは Align.topCenter、キャンバス下側が円盤側）
    // apex（先端）を下に、台側を上に配置
    final path = Path()
      ..moveTo(w * 0.50, h * 0.95)  // 先端（下）
      ..lineTo(w * 0.18, h * 0.20)  // 左上
      ..lineTo(w * 0.82, h * 0.20)  // 右上
      ..close();

    canvas.drawPath(path, glow);
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}



class _HubPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = min(size.width, size.height) * 0.44;
    final c = Offset(size.width / 2, size.height / 2);
    final r1 = r * 0.14, r2 = r * 0.10;
    canvas.drawCircle(c, r1, Paint()..shader = RadialGradient(colors: [Colors.grey.shade300, Colors.grey.shade100]).createShader(Rect.fromCircle(center: c, radius: r1)));
    canvas.drawCircle(c, r2, Paint()..shader = RadialGradient(colors: [Colors.white, Colors.grey.shade200]).createShader(Rect.fromCircle(center: c, radius: r2)));
    final line = Paint()..color = Colors.white.withOpacity(0.8)..strokeWidth = 1.2;
    canvas.drawLine(Offset(c.dx - r2, c.dy), Offset(c.dx + r2, c.dy), line);
    canvas.drawLine(Offset(c.dx, c.dy - r2), Offset(c.dx, c.dy + r2), line);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ===== 共通ボタンビルダー =====
Widget _mainButton({
  required BuildContext context,
  required String label,
  required IconData icon,
  required VoidCallback onPressed,
}) {
  final cs = Theme.of(context).colorScheme;
  return SizedBox(
    width: double.infinity,
    height: 56,
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary, cs.primaryContainer],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        icon: Icon(icon, size: 24),
        label: Text(label),
        onPressed: onPressed,
      ),
    ),
  );
}

Widget _subButton({
  required BuildContext context,
  required String label,
  required IconData icon,
  required VoidCallback onPressed,
}) {
  final cs = Theme.of(context).colorScheme;
  return SizedBox(
    width: double.infinity,
    height: 52,
    child: ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: cs.secondaryContainer,
        foregroundColor: cs.onSecondaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      icon: Icon(icon, size: 22),
      label: Text(label),
      onPressed: onPressed,
    ),
  );
}


// ===== BLOCK 7: particles (unused now, kept for future) =====
class _Particle {
  final Offset origin;
  final double angle;   // rad
  final double velocity; // px/s
  final double life;    // sec
  final MaterialColor color;
  _Particle({required this.origin, required this.angle, required this.velocity, required this.life, required this.color});
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress; // 0..1
  _ParticlePainter({required this.particles, required this.progress});
  @override
  void paint(Canvas canvas, Size size) {}
  @override
  bool shouldRepaint(covariant _ParticlePainter old) => false;
}
