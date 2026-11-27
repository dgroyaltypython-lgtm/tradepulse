import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const TradePulseApp());

const navy = Color(0xFF101A32);
const ink = Color(0xFF17233D);
const teal = Color(0xFF16B8A6);
const green = Color(0xFF20B486);
const red = Color(0xFFE45B69);
const muted = Color(0xFF8792A8);
final money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

class TradePulseApp extends StatelessWidget {
  const TradePulseApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TradePulse OI', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, scaffoldBackgroundColor: const Color(0xFFF4F6FA),
      colorScheme: ColorScheme.fromSeed(seedColor: teal, brightness: Brightness.light),
      fontFamily: 'Roboto', appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF4F6FA), foregroundColor: ink, elevation: 0)),
    home: const HomeShell());
}

class Trade {
  String symbol, side, setup, status, notes;
  double entry, exit, stop, target, qty, charges;
  DateTime date;
  Trade({required this.symbol, required this.side, required this.setup, required this.status, required this.notes,
    required this.entry, required this.exit, required this.stop, required this.target, required this.qty,
    required this.charges, required this.date});
  double get pnl => status == 'Open' ? 0 : (side == 'BUY' ? exit-entry : entry-exit) * qty - charges;
  Map<String,dynamic> toJson()=>{'symbol':symbol,'side':side,'setup':setup,'status':status,'notes':notes,'entry':entry,'exit':exit,'stop':stop,'target':target,'qty':qty,'charges':charges,'date':date.toIso8601String()};
  factory Trade.fromJson(Map<String,dynamic> j)=>Trade(symbol:j['symbol'],side:j['side'],setup:j['setup']??'',status:j['status'],notes:j['notes']??'',entry:(j['entry'] as num).toDouble(),exit:(j['exit'] as num).toDouble(),stop:(j['stop'] as num).toDouble(),target:(j['target'] as num).toDouble(),qty:(j['qty'] as num).toDouble(),charges:(j['charges'] as num).toDouble(),date:DateTime.parse(j['date']));
}

class OptionRow {
  final double strike, ceLtp, ceChange, ceOi, ceOiChange, ceVolume, ceIv;
  final double peLtp, peChange, peOi, peOiChange, peVolume, peIv;
  final bool ceValid, peValid;

  const OptionRow({
    required this.strike, required this.ceLtp, required this.ceChange,
    required this.ceOi, required this.ceOiChange, required this.ceVolume,
    required this.ceIv, required this.peLtp, required this.peChange,
    required this.peOi, required this.peOiChange, required this.peVolume,
    required this.peIv, required this.ceValid, required this.peValid,
  });

  Map<String, dynamic> toJson() => {
    'strike': strike, 'ceLtp': ceLtp, 'ceChange': ceChange, 'ceOi': ceOi,
    'ceOiChange': ceOiChange, 'ceVolume': ceVolume, 'ceIv': ceIv,
    'peLtp': peLtp, 'peChange': peChange, 'peOi': peOi,
    'peOiChange': peOiChange, 'peVolume': peVolume, 'peIv': peIv,
    'ceValid': ceValid, 'peValid': peValid,
  };

  factory OptionRow.fromJson(Map<String, dynamic> j) => OptionRow(
    strike: numVal(j['strike']), ceLtp: numVal(j['ceLtp']),
    ceChange: numVal(j['ceChange']), ceOi: numVal(j['ceOi']),
    ceOiChange: numVal(j['ceOiChange']), ceVolume: numVal(j['ceVolume']),
    ceIv: numVal(j['ceIv']), peLtp: numVal(j['peLtp']),
    peChange: numVal(j['peChange']), peOi: numVal(j['peOi']),
    peOiChange: numVal(j['peOiChange']), peVolume: numVal(j['peVolume']),
    peIv: numVal(j['peIv']), ceValid: j['ceValid'] == true,
    peValid: j['peValid'] == true,
  );
}

class OptionComparison {
  final double strike;
  final OptionRow previous, current;
  final double cePremiumDelta, ceOiDelta, pePremiumDelta, peOiDelta;
  final bool ceValid, peValid;

  const OptionComparison({
    required this.strike, required this.previous, required this.current,
    required this.cePremiumDelta, required this.ceOiDelta,
    required this.pePremiumDelta, required this.peOiDelta,
    required this.ceValid, required this.peValid,
  });

  Signal get ceSignal => ceValid
      ? classify(cePremiumDelta, ceOiDelta, call: true)
      : const Signal('Insufficient Data', 'CE premium or OI is missing in one snapshot', 'Not calculated', muted);
  Signal get peSignal => peValid
      ? classify(pePremiumDelta, peOiDelta, call: false)
      : const Signal('Insufficient Data', 'PE premium or OI is missing in one snapshot', 'Not calculated', muted);
}

class Signal { final String title, detail, bias; final Color color; const Signal(this.title,this.detail,this.bias,this.color); }
Signal classify(double premiumChange,double oiChange,{required bool call}) {
  if (premiumChange>0 && oiChange>0) return Signal('Fresh Long Build-up','Premium ↑  •  OI ↑',call?'Bullish CE positioning':'Bearish PE positioning',green);
  if (premiumChange<0 && oiChange>0) return Signal('Short Build-up','Premium ↓  •  OI ↑',call?'Bearish CE positioning':'Bullish PE positioning',red);
  if (premiumChange>0 && oiChange<0) return Signal('Short Covering','Premium ↑  •  OI ↓',call?'Bullish recovery in CE':'Bearish pressure easing in PE',teal);
  if (premiumChange<0 && oiChange<0) return Signal('Long Unwinding','Premium ↓  •  OI ↓',call?'Bullish CE positions reducing':'Bearish PE positions reducing',Colors.orange);
  return const Signal('Neutral / No clear signal','Insufficient directional change','Neutral',muted);
}

double numVal(dynamic v) { if(v==null) return 0; final s=v.toString().trim().replaceAll(',','').replaceAll('−','-'); if(s.isEmpty||s=='-'||s.toLowerCase()=='nan') return 0; return double.tryParse(s)??0; }

double? nullableNumVal(dynamic v) { if (v == null) return null; final s = v.toString().trim().replaceAll(',', '').replaceAll('−', '-'); if (s.isEmpty || s == '-' || s.toLowerCase() == 'nan' || s.toLowerCase() == 'null') return null; return double.tryParse(s); }

String _headerKey(dynamic value) => value.toString().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

class HomeShell extends StatefulWidget { const HomeShell({super.key}); @override State<HomeShell> createState()=>_HomeShellState(); }
class _HomeShellState extends State<HomeShell> {
  int tab = 0;
  List<Trade> trades = [];
  List<OptionRow> options = [];
  List<List<OptionRow>> snapshots = [];
  List<String> snapshotNames = [];
  List<OptionComparison> comparisons = [];
  String importedName = 'No CSV imported';
  DateTimeRange? range;
  String search = '';
  bool isImporting = false;

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final rawTrades = p.getString('trades');
    if (rawTrades != null) {
      try { trades = (jsonDecode(rawTrades) as List).map((e) => Trade.fromJson(Map<String, dynamic>.from(e))).toList(); }
      catch (_) { trades = []; }
    }
    final rawSnapshots = p.getString('oi_snapshots');
    if (rawSnapshots != null) {
      try {
        final saved = jsonDecode(rawSnapshots) as List;
        for (final item in saved) {
          final record = Map<String, dynamic>.from(item as Map);
          final rowList = (record['rows'] as List).map((e) => OptionRow.fromJson(Map<String, dynamic>.from(e as Map))).toList();
          snapshots.add(rowList);
          snapshotNames.add((record['name'] ?? 'Saved snapshot').toString());
        }
        if (snapshots.isNotEmpty) {
          options = snapshots.last;
          importedName = snapshotNames.last;
          if (snapshots.length >= 2) comparisons = _compareSnapshots(snapshots[snapshots.length - 2], snapshots.last);
        }
      } catch (_) {
        snapshots = []; snapshotNames = []; options = []; comparisons = [];
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('trades', jsonEncode(trades.map((e) => e.toJson()).toList()));
  }

  Future<void> saveSnapshots() async {
    final p = await SharedPreferences.getInstance();
    final data = List.generate(snapshots.length, (i) => {
      'name': snapshotNames[i],
      'rows': snapshots[i].map((row) => row.toJson()).toList(),
    });
    await p.setString('oi_snapshots', jsonEncode(data));
  }

  List<OptionComparison> _compareSnapshots(List<OptionRow> previous, List<OptionRow> current) {
    final oldByStrike = <String, OptionRow>{
      for (final row in previous) row.strike.toStringAsFixed(2): row,
    };
    final result = <OptionComparison>[];
    for (final now in current) {
      final old = oldByStrike[now.strike.toStringAsFixed(2)];
      if (old == null) continue;
      result.add(OptionComparison(
        strike: now.strike, previous: old, current: now,
        cePremiumDelta: now.ceLtp - old.ceLtp,
        ceOiDelta: now.ceOi - old.ceOi,
        pePremiumDelta: now.peLtp - old.peLtp,
        peOiDelta: now.peOi - old.peOi,
        ceValid: old.ceValid && now.ceValid,
        peValid: old.peValid && now.peValid,
      ));
    }
    result.sort((a, b) => a.strike.compareTo(b.strike));
    return result;
  }

  List<Trade> get filtered {
    var x = trades.where((t) => search.isEmpty || t.symbol.toLowerCase().contains(search.toLowerCase()) || t.setup.toLowerCase().contains(search.toLowerCase()));
    if (range != null) {
      x = x.where((t) => !t.date.isBefore(range!.start) || DateUtils.isSameDay(t.date, range!.start));
      x = x.where((t) => !t.date.isAfter(range!.end) || DateUtils.isSameDay(t.date, range!.end));
    }
    return x.toList()..sort((a, b) => b.date.compareTo(a.date));
  }

  double get totalPnl => filtered.fold(0, (s, t) => s + t.pnl);

  Future<void> importCsv() async {
    if (isImporting) return;
    setState(() => isImporting = true);
    try {
      // FileType.any avoids Android document providers hiding CSV files that report text/plain MIME types.
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withReadStream: true,
        dialogTitle: 'Choose an option-chain CSV file',
      );
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.single;
      if (!file.name.toLowerCase().trim().endsWith('.csv')) {
        throw Exception('Please select a .csv file. The selected file was ${file.name}.');
      }

      List<int> bytes = [];
      if (file.readStream != null) {
        bytes = await file.readStream!.fold<List<int>>(<int>[], (all, part) { all.addAll(part); return all; });
      }
      if (bytes.isEmpty && file.bytes != null) bytes = file.bytes!;
      if (bytes.isEmpty && file.path != null && file.path!.isNotEmpty) bytes = await File(file.path!).readAsBytes();
      if (bytes.isEmpty) {
        throw Exception('Android selected the file but did not return its contents. Please copy the CSV to Downloads or Documents and select it again.');
      }

      var csvText = utf8.decode(bytes, allowMalformed: true).replaceFirst('\uFEFF', '');
      csvText = csvText.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      final rows = const CsvToListConverter(eol: '\n', shouldParseNumbers: false).convert(csvText);
      final headerIndex = rows.indexWhere((row) => row.any((cell) => _headerKey(cell) == 'STRIKE'));
      if (headerIndex < 0) throw Exception('STRIKE column was not found. Use the NIFTY option-chain CSV export.');
      final header = rows[headerIndex];
      final strikeIndex = header.indexWhere((cell) => _headerKey(cell) == 'STRIKE');

      int findColumn(String name, int start, int end) {
        for (var i = start; i < end && i < header.length; i++) {
          if (_headerKey(header[i]) == name) return i;
        }
        return -1;
      }
      final ceOi = findColumn('OI', 0, strikeIndex);
      final ceOiChange = findColumn('CHNGINOI', 0, strikeIndex);
      final ceLtp = findColumn('LTP', 0, strikeIndex);
      final ceChange = findColumn('CHNG', 0, strikeIndex);
      final peChange = findColumn('CHNG', strikeIndex + 1, header.length);
      final peLtp = findColumn('LTP', strikeIndex + 1, header.length);
      final peOiChange = findColumn('CHNGINOI', strikeIndex + 1, header.length);
      final peOi = findColumn('OI', strikeIndex + 1, header.length);
      final requiredColumns = [strikeIndex, ceOi, ceOiChange, ceLtp, ceChange, peChange, peLtp, peOiChange, peOi];
      if (requiredColumns.any((index) => index < 0)) {
        throw Exception('CSV columns are incomplete. Required fields: CE OI, CE change in OI, CE LTP, CE premium change, Strike, PE premium change, PE LTP, PE change in OI and PE OI.');
      }

      dynamic cell(List<dynamic> row, int index) => index >= 0 && index < row.length ? row[index] : null;
      final parsed = <OptionRow>[];
      for (final row in rows.skip(headerIndex + 1)) {
        final strikeValue = nullableNumVal(cell(row, strikeIndex));
        if (strikeValue == null || strikeValue <= 0) continue;
        final ceLtpValue = nullableNumVal(cell(row, ceLtp));
        final ceOiValue = nullableNumVal(cell(row, ceOi));
        final peLtpValue = nullableNumVal(cell(row, peLtp));
        final peOiValue = nullableNumVal(cell(row, peOi));
        parsed.add(OptionRow(
          strike: strikeValue,
          ceLtp: ceLtpValue ?? 0, ceChange: numVal(cell(row, ceChange)),
          ceOi: ceOiValue ?? 0, ceOiChange: numVal(cell(row, ceOiChange)),
          ceVolume: numVal(cell(row, findColumn('VOLUME', 0, strikeIndex))),
          ceIv: numVal(cell(row, findColumn('IV', 0, strikeIndex))),
          peLtp: peLtpValue ?? 0, peChange: numVal(cell(row, peChange)),
          peOi: peOiValue ?? 0, peOiChange: numVal(cell(row, peOiChange)),
          peVolume: numVal(cell(row, findColumn('VOLUME', strikeIndex + 1, header.length))),
          peIv: numVal(cell(row, findColumn('IV', strikeIndex + 1, header.length))),
          ceValid: ceLtpValue != null && ceOiValue != null,
          peValid: peLtpValue != null && peOiValue != null,
        ));
      }
      if (parsed.isEmpty) throw Exception('No valid strike rows were found in this CSV. Check the exported option-chain format.');

      final previousCount = snapshots.length;
      setState(() {
        options = parsed;
        snapshots.add(parsed);
        snapshotNames.add(file.name);
        if (snapshots.length > 10) { snapshots.removeAt(0); snapshotNames.removeAt(0); }
        importedName = file.name;
        comparisons = snapshots.length >= 2 ? _compareSnapshots(snapshots[snapshots.length - 2], snapshots.last) : [];
        tab = 1;
      });
      await saveSnapshots();
      if (!mounted) return;
      final message = previousCount == 0
          ? 'Baseline saved: ${parsed.length} strikes. Upload another CSV to calculate CE / PE positioning.'
          : 'Compared ${comparisons.length} matching strikes. CE and PE signals are ready.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 4)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('CSV import failed: $e'), duration: const Duration(seconds: 6)));
    } finally {
      if (mounted) setState(() => isImporting = false);
    }
  }

  Future<void> addTrade([Trade? old]) async {
    final result = await showModalBottomSheet<Trade>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => TradeEditor(existing: old));
    if (result != null) {
      setState(() { if (old == null) trades.add(result); else { final i = trades.indexOf(old); if (i >= 0) trades[i] = result; } });
      await save();
    }
  }

  Future<void> exportCsv() async {
    final rows = [['Date','Symbol','Side','Entry','Exit','Quantity','Stop Loss','Target','Charges','P&L','Status','Setup','Notes'], ...filtered.map((t) => [DateFormat('yyyy-MM-dd').format(t.date),t.symbol,t.side,t.entry,t.exit,t.qty,t.stop,t.target,t.charges,t.pnl,t.status,t.setup,t.notes])];
    final csv = const ListToCsvConverter().convert(rows);
    await Share.shareXFiles([XFile.fromData(utf8.encode(csv), mimeType: 'text/csv', name: 'tradepulse_report.csv')], text: 'TradePulse trading report');
  }

  Future<void> exportPdf() async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(build: (c) => [
      pw.Text('TRADEPULSE — TRADING REPORT', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 8), pw.Text('Generated ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}'),
      pw.Text('Trades: ${filtered.length}   Net P&L: ${money.format(totalPnl)}'), pw.SizedBox(height: 16),
      pw.Table.fromTextArray(headers: ['Date','Symbol','Side','Entry','Exit','Qty','P&L','Status'], data: filtered.map((t) => [DateFormat('dd/MM/yy').format(t.date),t.symbol,t.side,t.entry.toStringAsFixed(2),t.exit.toStringAsFixed(2),t.qty.toString(),t.pnl.toStringAsFixed(2),t.status]).toList()),
    ]));
    await Printing.layoutPdf(onLayout: (_) => doc.save());
  }

  Future<void> shareTip() async {
    final msg = await showModalBottomSheet<String>(context: context, isScrollControlled: true, builder: (_) => const TipEditor());
    if (msg != null && msg.trim().isNotEmpty) await Share.share(msg, subject: 'Trading Setup');
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(trades: filtered, pnl: totalPnl, onImport: importCsv, onAdd: () => addTrade(), onAnalyze: () => setState(() => tab = 1), onJournal: () => setState(() => tab = 2), options: options, comparisons: comparisons, importedName: importedName),
      AnalyzerPage(options: options, comparisons: comparisons, importName: importedName, previousImportName: snapshotNames.length > 1 ? snapshotNames[snapshotNames.length - 2] : '', snapshotCount: snapshots.length, isImporting: isImporting, onImport: importCsv),
      JournalPage(trades: filtered, search: search, onSearch: (s) => setState(() => search = s), range: range, onRange: (r) => setState(() => range = r), onAdd: () => addTrade(), onEdit: addTrade, onDelete: (t) async { setState(() => trades.remove(t)); await save(); }),
      ReportsPage(trades: filtered, pnl: totalPnl, onCsv: exportCsv, onPdf: exportPdf, onTip: shareTip),
    ];
    return Scaffold(body: SafeArea(child: Column(children: [
      Expanded(child: IndexedStack(index: tab, children: pages)),
      NavigationBar(selectedIndex: tab, onDestinationSelected: (v) => setState(() => tab = v), destinations: const [
        NavigationDestination(icon: Icon(Icons.dashboard_rounded), label: 'Overview'),
        NavigationDestination(icon: Icon(Icons.analytics_rounded), label: 'OI Analyzer'),
        NavigationDestination(icon: Icon(Icons.receipt_long_rounded), label: 'Journal'),
        NavigationDestination(icon: Icon(Icons.insights_rounded), label: 'Reports'),
      ]),
    ])));
  }
}

class PageHeader extends StatelessWidget {final String title,subtitle; final Widget? trailing; const PageHeader(this.title,this.subtitle,{this.trailing,super.key}); @override Widget build(BuildContext c)=>Padding(padding:const EdgeInsets.fromLTRB(20,18,20,14),child:Row(children:[Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontSize:25,fontWeight:FontWeight.w800,color:ink)),const SizedBox(height:3),Text(subtitle,style:const TextStyle(color:muted,fontSize:12))])),if(trailing!=null)trailing!]));}
class Surface extends StatelessWidget {final Widget child; final EdgeInsets padding; const Surface({required this.child,this.padding=const EdgeInsets.all(16),super.key}); @override Widget build(BuildContext c)=>Container(width:double.infinity,padding:padding,decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(20),boxShadow:[BoxShadow(color:navy.withOpacity(.045),blurRadius:18,offset:const Offset(0,6))]),child:child);}
class Metric extends StatelessWidget {final String label,value,caption;final Color color;final IconData icon;const Metric(this.label,this.value,this.caption,this.color,this.icon,{super.key});@override Widget build(BuildContext c)=>Surface(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(icon,color:color,size:19),const SizedBox(height:12),Text(value,style:TextStyle(fontSize:19,fontWeight:FontWeight.w800,color:color)),Text(label,style:const TextStyle(fontWeight:FontWeight.w700,color:ink,fontSize:12)),Text(caption,style:const TextStyle(color:muted,fontSize:10))]));}
class DashboardPage extends StatelessWidget {
  final List<Trade> trades;
  final double pnl;
  final VoidCallback onImport, onAdd, onAnalyze, onJournal;
  final List<OptionRow> options;
  final List<OptionComparison> comparisons;
  final String importedName;

  const DashboardPage({
    required this.trades,
    required this.pnl,
    required this.onImport,
    required this.onAdd,
    required this.onAnalyze,
    required this.onJournal,
    required this.options,
    required this.comparisons,
    required this.importedName,
    super.key,
  });

  @override
  Widget build(BuildContext c) {
    final wins = trades.where((t) => t.pnl > 0).length;
    final openTrades = trades.where((t) => t.status == 'Open').length;
    final ceLongs = comparisons.where((o) => o.ceSignal.title == 'Fresh Long Build-up').length;
    final peLongs = comparisons.where((o) => o.peSignal.title == 'Fresh Long Build-up').length;

    return ListView(
      padding: const EdgeInsets.only(bottom: 20),
      children: [
        PageHeader(
          'TradePulse',
          'Your trading desk • Market intelligence',
          trailing: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: navy, borderRadius: BorderRadius.circular(13)),
            child: const Icon(Icons.show_chart, color: teal),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF101A32), Color(0xFF263B60)]),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('TOTAL REALISED P&L', style: TextStyle(color: Color(0xFFB7C3D8), fontSize: 11, letterSpacing: 1.3)),
                const SizedBox(height: 7),
                Text(money.format(pnl), style: TextStyle(color: pnl >= 0 ? const Color(0xFF55D9B4) : const Color(0xFFFF8791), fontSize: 31, fontWeight: FontWeight.w800)),
                const SizedBox(height: 15),
                Row(children: [
                  _heroStat('${trades.length}', 'TRADES'),
                  const SizedBox(width: 25),
                  _heroStat('${trades.isEmpty ? 0 : (wins / trades.length * 100).toStringAsFixed(0)}%', 'WIN RATE'),
                  const Spacer(),
                  const Icon(Icons.trending_up, color: teal, size: 30),
                ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(child: Metric('Open records', '$openTrades', 'Active positions', teal, Icons.track_changes)),
            const SizedBox(width: 10),
            Expanded(child: Metric('Winning trades', '$wins', 'Profitable closed trades', green, Icons.emoji_events)),
            const SizedBox(width: 10),
            Expanded(child: Metric('Option strikes', '${options.length}', 'Latest CSV import', Colors.deepPurple, Icons.table_chart)),
          ]),
        ),
        const SizedBox(height: 20),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text('QUICK ACTIONS', style: TextStyle(fontWeight: FontWeight.w800, color: ink, letterSpacing: 1)),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(child: _action('Import Option CSV', Icons.upload_file, onImport)),
            const SizedBox(width: 10),
            Expanded(child: _action('Analyze OI', Icons.query_stats, onAnalyze)),
            const SizedBox(width: 10),
            Expanded(child: _action('Add Trade', Icons.add_chart, onAdd)),
          ]),
        ),
        const SizedBox(height: 17),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.auto_graph, color: teal),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Latest market analysis', style: TextStyle(fontWeight: FontWeight.w800, color: ink))),
                  TextButton(onPressed: onAnalyze, child: const Text('View all')),
                ]),
                Text(importedName, style: const TextStyle(fontSize: 11, color: muted)),
                const SizedBox(height: 9),
                if (options.isEmpty)
                  const Text('Import an option-chain CSV to start OI analysis.', style: TextStyle(color: muted, fontSize: 13))
                else if (comparisons.isEmpty)
                  const Text('Baseline saved. Upload a second CSV to calculate the latest CE / PE positioning.', style: TextStyle(color: muted, fontSize: 13))
                else
                  Text('$ceLongs CE fresh long signals • $peLongs PE fresh long signals • ${comparisons.length} strikes compared', style: const TextStyle(color: ink, fontSize: 13)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Surface(
            child: Row(children: [
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Trading journal', style: TextStyle(fontWeight: FontWeight.w800, color: ink)),
                Text('Review and manage your latest trades', style: TextStyle(color: muted, fontSize: 11)),
              ])),
              TextButton(onPressed: onJournal, child: const Text('Open journal')),
            ]),
          ),
        ),
      ],
    );
  }
}
Widget _heroStat(String value,String label)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(value,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w800,fontSize:17)),Text(label,style:const TextStyle(color:Color(0xFFB7C3D8),fontSize:9,letterSpacing:1))]);
Widget _action(String title,IconData icon,VoidCallback tap)=>InkWell(onTap:tap,borderRadius:BorderRadius.circular(17),child:Surface(padding:const EdgeInsets.symmetric(vertical:17,horizontal:7),child:Column(children:[Icon(icon,color:teal,size:25),const SizedBox(height:8),Text(title,textAlign:TextAlign.center,style:const TextStyle(color:ink,fontSize:11,fontWeight:FontWeight.w700))])));

class AnalyzerPage extends StatefulWidget {
  final List<OptionRow> options;
  final List<OptionComparison> comparisons;
  final String importName, previousImportName;
  final int snapshotCount;
  final bool isImporting;
  final VoidCallback onImport;

  const AnalyzerPage({
    required this.options, required this.comparisons, required this.importName,
    required this.previousImportName, required this.snapshotCount,
    required this.isImporting, required this.onImport, super.key,
  });

  @override
  State<AnalyzerPage> createState() => _AnalyzerPageState();
}

class _AnalyzerPageState extends State<AnalyzerPage> {
  final TextEditingController strikeController = TextEditingController();
  double? selectedStrike;
  String? lookupMessage;

  @override
  void dispose() { strikeController.dispose(); super.dispose(); }

  @override
  void didUpdateWidget(covariant AnalyzerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.snapshotCount >= 2 && selectedStrike != null) {
      final exists = widget.comparisons.any((item) => (item.strike - selectedStrike!).abs() < 0.01);
      lookupMessage = exists ? null : 'Strike not found in both latest snapshots, or its rows could not be compared.';
    }
  }

  OptionComparison? get selectedComparison {
    if (selectedStrike == null) return null;
    for (final item in widget.comparisons) {
      if ((item.strike - selectedStrike!).abs() < 0.01) return item;
    }
    return null;
  }

  void lookupStrike() {
    final strike = nullableNumVal(strikeController.text);
    if (strike == null) { setState(() { selectedStrike = null; lookupMessage = 'Enter a valid strike price.'; }); return; }
    if (widget.snapshotCount < 2) { setState(() { selectedStrike = strike; lookupMessage = 'Upload a second CSV snapshot before checking the market status.'; }); return; }
    final found = widget.comparisons.any((item) => (item.strike - strike).abs() < 0.01);
    setState(() { selectedStrike = strike; lookupMessage = found ? null : 'Strike not found in both snapshots, or its rows could not be compared.'; });
  }

  void selectStrike(double strike) {
    strikeController.text = strike.toStringAsFixed(0);
    setState(() { selectedStrike = strike; lookupMessage = null; });
  }

  @override
  Widget build(BuildContext context) {
    final maxCe = widget.options.isEmpty ? null : widget.options.reduce((a, b) => a.ceOi > b.ceOi ? a : b);
    final maxPe = widget.options.isEmpty ? null : widget.options.reduce((a, b) => a.peOi > b.peOi ? a : b);
    final sorted = [...widget.comparisons]..sort((a, b) => a.strike.compareTo(b.strike));
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      PageHeader('OI Analyzer', 'Compare snapshots • Check CE / PE positioning', trailing: IconButton(onPressed: widget.isImporting ? null : widget.onImport, icon: const Icon(Icons.upload_file, color: teal))),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.file_present, color: teal), const SizedBox(width: 8), const Expanded(child: Text('Option-chain CSV snapshots', style: TextStyle(fontWeight: FontWeight.w800, color: ink))),
          FilledButton.tonalIcon(onPressed: widget.isImporting ? null : widget.onImport, icon: widget.isImporting ? const SizedBox(width: 16,height: 16,child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload_file), label: Text(widget.isImporting ? 'Reading…' : 'Upload CSV')),
        ]),
        const SizedBox(height: 7),
        Text('Latest: ${widget.importName}', style: const TextStyle(color: muted, fontSize: 11)),
        const SizedBox(height: 4),
        Text('Saved snapshots: ${widget.snapshotCount}', style: const TextStyle(color: muted, fontSize: 11)),
        const SizedBox(height: 9),
        if (widget.snapshotCount == 0) const Text('Upload your first option-chain CSV. It becomes the baseline snapshot.', style: TextStyle(color: muted, fontSize: 13))
        else if (widget.snapshotCount == 1) const Text('Baseline saved. Upload a second CSV later to calculate changes in premium and OI.', style: TextStyle(color: teal, fontWeight: FontWeight.w700, fontSize: 12))
        else Text('Comparing ${widget.importName} against ${widget.previousImportName}. ${widget.comparisons.length} matching strikes found.', style: const TextStyle(color: green, fontWeight: FontWeight.w700, fontSize: 12)),
      ]))),
      if (widget.options.isNotEmpty) ...[
        const SizedBox(height: 14),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
          Expanded(child: Metric('Highest CE OI', maxCe!.strike.toStringAsFixed(0), 'Call OI ${_fmt(maxCe.ceOi)}', red, Icons.arrow_downward)),
          const SizedBox(width: 10),
          Expanded(child: Metric('Highest PE OI', maxPe!.strike.toStringAsFixed(0), 'Put OI ${_fmt(maxPe.peOi)}', green, Icons.arrow_upward)),
        ])),
      ],
      const SizedBox(height: 14),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('CHECK A PARTICULAR STRIKE', style: TextStyle(fontWeight: FontWeight.w800, color: ink)),
        const SizedBox(height: 9),
        Row(children: [
          Expanded(child: TextField(controller: strikeController, keyboardType: const TextInputType.numberWithOptions(decimal: true), onSubmitted: (_) => lookupStrike(), decoration: InputDecoration(hintText: 'Enter strike, e.g. 26000', prefixIcon: const Icon(Icons.search), filled: true, fillColor: const Color(0xFFF4F6FA), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(vertical: 13)))),
          const SizedBox(width: 8),
          FilledButton(onPressed: lookupStrike, style: FilledButton.styleFrom(backgroundColor: navy, padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 15)), child: const Text('Check')),
        ]),
        if (lookupMessage != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(lookupMessage!, style: const TextStyle(color: red, fontSize: 11))),
        if (selectedComparison != null) ...[
          const SizedBox(height: 12),
          Text('STRIKE ${selectedComparison!.strike.toStringAsFixed(0)} • CHANGE SINCE PREVIOUS UPLOAD', style: const TextStyle(fontWeight: FontWeight.w800, color: ink, fontSize: 11)),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _sideComparisonCard('CALL (CE)', selectedComparison!.ceSignal, selectedComparison!.current.ceLtp, selectedComparison!.current.ceOi, selectedComparison!.cePremiumDelta, selectedComparison!.ceOiDelta, selectedComparison!.ceValid)),
            const SizedBox(width: 9),
            Expanded(child: _sideComparisonCard('PUT (PE)', selectedComparison!.peSignal, selectedComparison!.current.peLtp, selectedComparison!.current.peOi, selectedComparison!.pePremiumDelta, selectedComparison!.peOiDelta, selectedComparison!.peValid)),
          ]),
        ],
      ]))),
      const SizedBox(height: 14),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('OI POSITIONING GUIDE', style: TextStyle(fontWeight: FontWeight.w800, color: ink)),
        const SizedBox(height: 10),
        _signalLine('Short Build-up', 'Premium ↓  •  OI ↑', red),
        _signalLine('Short Covering', 'Premium ↑  •  OI ↓', teal),
        _signalLine('Fresh Long Build-up', 'Premium ↑  •  OI ↑', green),
        _signalLine('Long Unwinding', 'Premium ↓  •  OI ↓', Colors.orange),
        const SizedBox(height: 5),
        const Text('Each uploaded CSV is compared with the immediately previous snapshot. CE and PE are calculated independently.', style: TextStyle(color: muted, fontSize: 11)),
      ]))),
      if (widget.snapshotCount >= 2) ...[
        const SizedBox(height: 14),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Surface(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('STRIKE-BY-STRIKE COMPARISON', style: TextStyle(fontWeight: FontWeight.w800, color: ink)),
          const SizedBox(height: 5),
          const Text('Tap any strike to open its CE and PE status.', style: TextStyle(fontSize: 11, color: muted)),
          const Divider(height: 18),
          if (sorted.isEmpty) const Text('No common strike prices were found between these snapshots.', style: TextStyle(color: muted, fontSize: 12))
          else ...sorted.map((item) => _comparisonListTile(item)),
        ]))),
      ],
      const Padding(padding: EdgeInsets.all(16), child: Text('Educational analysis only. Snapshot comparison indicates changes in contract positioning; it is not a guaranteed trading signal. Verify live prices, liquidity and risk before trading.', style: TextStyle(color: muted, fontSize: 11))),
    ]);
  }

  Widget _comparisonListTile(OptionComparison item) => InkWell(
    onTap: () => selectStrike(item.strike),
    borderRadius: BorderRadius.circular(10),
    child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(children: [
      Row(children: [Text(item.strike.toStringAsFixed(0), style: const TextStyle(fontWeight: FontWeight.w800, color: ink)), const Spacer(), const Text('View CE / PE', style: TextStyle(color: muted, fontSize: 9))]),
      const SizedBox(height: 5),
      Row(children: [
        Expanded(child: _miniComparisonStatus('CE', item.ceSignal)),
        const SizedBox(width: 7),
        Expanded(child: _miniComparisonStatus('PE', item.peSignal)),
      ]),
      const Divider(height: 13),
    ])),
  );
}

Widget _miniComparisonStatus(String label, Signal signal) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
  decoration: BoxDecoration(color: signal.color.withOpacity(.08), borderRadius: BorderRadius.circular(8)),
  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: TextStyle(color: signal.color, fontSize: 9, fontWeight: FontWeight.w900)),
    Text(signal.title, style: TextStyle(color: signal.color, fontSize: 10, fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
  ]),
);

Widget _sideComparisonCard(String label, Signal signal, double ltp, double oi, double premiumDelta, double oiDelta, bool valid) => Container(
  padding: const EdgeInsets.all(11),
  decoration: BoxDecoration(color: signal.color.withOpacity(.08), borderRadius: BorderRadius.circular(13), border: Border.all(color: signal.color.withOpacity(.22))),
  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: TextStyle(color: signal.color, fontWeight: FontWeight.w900, fontSize: 10)),
    const SizedBox(height: 5),
    Text(signal.title, style: TextStyle(color: signal.color, fontWeight: FontWeight.w800, fontSize: 13), maxLines: 2),
    const SizedBox(height: 8),
    _deltaLine('Premium Δ', valid ? _signed(premiumDelta, currency: true) : 'N/A'),
    _deltaLine('OI Δ', valid ? _signed(oiDelta) : 'N/A'),
    const Divider(height: 13),
    _deltaLine('Latest LTP', valid ? money.format(ltp) : 'N/A'),
    _deltaLine('Latest OI', valid ? _fmt(oi) : 'N/A'),
    const SizedBox(height: 4),
    Text(signal.bias, style: const TextStyle(color: muted, fontSize: 9)),
  ]),
);

Widget _deltaLine(String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [Expanded(child: Text(label, style: const TextStyle(color: muted, fontSize: 9))), Text(value, style: const TextStyle(color: ink, fontSize: 10, fontWeight: FontWeight.w700))]));
String _signed(double value, {bool currency = false}) {
  final prefix = value > 0 ? '+' : '';
  final formatted = NumberFormat('#,##0.##', 'en_IN').format(value);
  return currency ? '$prefix${money.format(value)}' : '$prefix$formatted';
}
String _fmt(double n) => NumberFormat.compact(locale: 'en_IN').format(n);
Widget _signalLine(String a, String b, Color color) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 9), Expanded(child: Text(a, style: const TextStyle(fontSize: 12, color: ink, fontWeight: FontWeight.w700))), Text(b, style: const TextStyle(color: muted, fontSize: 11))]));

class JournalPage extends StatelessWidget {
  final List<Trade> trades;
  final String search;
  final ValueChanged<String> onSearch;
  final DateTimeRange? range;
  final ValueChanged<DateTimeRange?> onRange;
  final VoidCallback onAdd;
  final ValueChanged<Trade> onEdit;
  final ValueChanged<Trade> onDelete;

  const JournalPage({
    required this.trades,
    required this.search,
    required this.onSearch,
    required this.range,
    required this.onRange,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  @override
  Widget build(BuildContext c) {
    final dateLabel = range == null
        ? 'All dates'
        : '${DateFormat('dd MMM').format(range!.start)} – ${DateFormat('dd MMM').format(range!.end)}';
    return Column(children: [
      PageHeader('Trading Journal', 'Track every entry, exit and decision', trailing: IconButton(onPressed: onAdd, icon: const Icon(Icons.add_circle, color: teal, size: 30))),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          onChanged: onSearch,
          decoration: InputDecoration(
            hintText: 'Search symbol, setup or notes...',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 9, 16, 12),
        child: Row(children: [
          Expanded(child: OutButton(
            icon: Icons.calendar_month,
            label: dateLabel,
            onTap: () async {
              final selected = await showDateRangePicker(
                context: c,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                initialDateRange: range,
              );
              onRange(selected);
            },
          )),
          if (range != null) IconButton(onPressed: () => onRange(null), icon: const Icon(Icons.close)),
        ]),
      ),
      Expanded(
        child: trades.isEmpty
            ? const Center(child: Text('No trades yet. Add your first trade.', style: TextStyle(color: muted)))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                itemCount: trades.length,
                separatorBuilder: (_, __) => const SizedBox(height: 9),
                itemBuilder: (context, i) {
                  final t = trades[i];
                  return InkWell(
                    onTap: () => onEdit(t),
                    onLongPress: () => _confirmDelete(context, t, onDelete),
                    child: Surface(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(color: (t.pnl >= 0 ? green : red).withOpacity(.1), borderRadius: BorderRadius.circular(12)),
                          child: Icon(t.side == 'BUY' ? Icons.north_east : Icons.south_west, color: t.side == 'BUY' ? green : red),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(t.symbol, style: const TextStyle(fontWeight: FontWeight.w800, color: ink)),
                          Text('${t.side} • ${DateFormat('dd MMM yyyy').format(t.date)} • ${t.status}', style: const TextStyle(color: muted, fontSize: 10)),
                          Text('Entry ${t.entry}  →  Exit ${t.exit}', style: const TextStyle(color: muted, fontSize: 10)),
                        ])),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(money.format(t.pnl), style: TextStyle(color: t.pnl >= 0 ? green : red, fontWeight: FontWeight.w800)),
                          const Text('P&L', style: TextStyle(color: muted, fontSize: 9)),
                        ]),
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}
Future<void> _confirmDelete(BuildContext c,Trade t,ValueChanged<Trade> cb)async{final yes=await showDialog<bool>(context:c,builder:(c)=>AlertDialog(title:const Text('Delete trade?'),content:Text('Remove ${t.symbol} from your journal?'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),TextButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Delete'))]));if(yes==true)cb(t);}
class OutButton extends StatelessWidget {final IconData icon;final String label;final VoidCallback onTap;const OutButton({required this.icon,required this.label,required this.onTap});@override Widget build(BuildContext c)=>OutlinedButton.icon(onPressed:onTap,icon:Icon(icon,size:17),label:Text(label),style:OutlinedButton.styleFrom(foregroundColor:ink,backgroundColor:Colors.white,side:BorderSide.none,alignment:Alignment.centerLeft));}

class ReportsPage extends StatelessWidget {
  final List<Trade> trades;
  final double pnl;
  final VoidCallback onCsv, onPdf, onTip;

  const ReportsPage({required this.trades, required this.pnl, required this.onCsv, required this.onPdf, required this.onTip, super.key});

  @override
  Widget build(BuildContext c) {
    final profit = trades.where((t) => t.pnl > 0).fold<double>(0, (s, t) => s + t.pnl);
    final loss = trades.where((t) => t.pnl < 0).fold<double>(0, (s, t) => s + t.pnl);
    final wins = trades.where((t) => t.pnl > 0).length;
    final winRate = trades.isEmpty ? '0.0' : (wins / trades.length * 100).toStringAsFixed(1);

    return ListView(
      padding: const EdgeInsets.only(bottom: 25),
      children: [
        PageHeader('Reports & Sharing', 'Performance summary and trade communication'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Surface(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('PERFORMANCE SUMMARY', style: TextStyle(fontWeight: FontWeight.w800, color: ink)),
              const SizedBox(height: 15),
              _reportRow('Total trades', '${trades.length}'),
              _reportRow('Gross winning P&L', money.format(profit), green),
              _reportRow('Gross losing P&L', money.format(loss), red),
              _reportRow('Net realised P&L', money.format(pnl), pnl >= 0 ? green : red),
              _reportRow('Average P&L', money.format(trades.isEmpty ? 0 : pnl / trades.length)),
              _reportRow('Win rate', '$winRate%'),
            ]),
          ),
        ),
        const SizedBox(height: 15),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Surface(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('EXPORT REPORTS', style: TextStyle(fontWeight: FontWeight.w800, color: ink)),
              const SizedBox(height: 10),
              _reportAction(c, Icons.table_chart, 'Export CSV', 'Share or save your trade data', onCsv),
              const Divider(),
              _reportAction(c, Icons.picture_as_pdf, 'Export PDF', 'Generate a printable PDF report', onPdf),
            ]),
          ),
        ),
        const SizedBox(height: 15),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(19),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF172440), Color(0xFF344B70)]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.send_rounded, color: teal, size: 27),
              const SizedBox(height: 9),
              const Text('Share a trading setup', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 4),
              const Text('Prepare a clear Buy / Sell tip with entry, stop-loss and targets.', style: TextStyle(color: Color(0xFFB7C3D8), fontSize: 12)),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onTip,
                icon: const Icon(Icons.chat),
                label: const Text('Create WhatsApp tip'),
                style: FilledButton.styleFrom(backgroundColor: teal, foregroundColor: navy),
              ),
            ]),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(18),
          child: Text('Reports are calculated from the trades saved on this device. CSV and PDF exports are generated locally.', style: TextStyle(color: muted, fontSize: 11)),
        ),
      ],
    );
  }
}
Widget _reportRow(String a,String b,[Color color=ink])=>Padding(padding:const EdgeInsets.symmetric(vertical:7),child:Row(children:[Expanded(child:Text(a,style:const TextStyle(color:muted,fontSize:12))),Text(b,style:TextStyle(color:color,fontWeight:FontWeight.w800,fontSize:13))]));
Widget _reportAction(BuildContext c,IconData i,String t,String d,VoidCallback f)=>ListTile(contentPadding:EdgeInsets.zero,leading:CircleAvatar(backgroundColor:teal.withOpacity(.1),child:Icon(i,color:teal)),title:Text(t,style:const TextStyle(fontWeight:FontWeight.w700,color:ink)),subtitle:Text(d,style:const TextStyle(fontSize:11,color:muted)),trailing:const Icon(Icons.chevron_right),onTap:f);

class TradeEditor extends StatefulWidget {final Trade? existing;const TradeEditor({this.existing});@override State<TradeEditor> createState()=>_TradeEditorState();}
class _TradeEditorState extends State<TradeEditor>{final form=GlobalKey<FormState>();late final symbol=TextEditingController(text:widget.existing?.symbol??'NIFTY');late final entry=TextEditingController(text:widget.existing?.entry.toString()??'');late final exit=TextEditingController(text:widget.existing?.exit.toString()??'');late final qty=TextEditingController(text:widget.existing?.qty.toString()??'1');late final stop=TextEditingController(text:widget.existing?.stop.toString()??'');late final target=TextEditingController(text:widget.existing?.target.toString()??'');late final charges=TextEditingController(text:widget.existing?.charges.toString()??'0');late final notes=TextEditingController(text:widget.existing?.notes??'');late String side=widget.existing?.side??'BUY',status=widget.existing?.status??'Closed',setup=widget.existing?.setup??'Intraday';late DateTime date=widget.existing?.date??DateTime.now();@override Widget build(BuildContext c)=>Padding(padding:EdgeInsets.only(bottom:MediaQuery.of(c).viewInsets.bottom),child:Container(height:MediaQuery.of(c).size.height*.88,padding:const EdgeInsets.all(20),decoration:const BoxDecoration(color:Color(0xFFF4F6FA),borderRadius:BorderRadius.vertical(top:Radius.circular(25))),child:Form(key:form,child:ListView(children:[Row(children:[Expanded(child:Text(widget.existing==null?'Add trade':'Edit trade',style:const TextStyle(fontSize:22,fontWeight:FontWeight.w800,color:ink))),IconButton(onPressed:()=>Navigator.pop(c),icon:const Icon(Icons.close))]),_field('Symbol / Instrument',symbol),Row(children:[Expanded(child:_drop('Side',side,['BUY','SELL'],(v)=>setState(()=>side=v))),const SizedBox(width:10),Expanded(child:_drop('Status',status,['Open','Closed'],(v)=>setState(()=>status=v)))]),_drop('Setup',setup,['Intraday','Swing','Positional','Options','Futures','Investment'],(v)=>setState(()=>setup=v)),Row(children:[Expanded(child:_field('Entry price',entry,num:true)),const SizedBox(width:10),Expanded(child:_field('Exit price',exit,num:true))]),Row(children:[Expanded(child:_field('Quantity',qty,num:true)),const SizedBox(width:10),Expanded(child:_field('Charges',charges,num:true))]),Row(children:[Expanded(child:_field('Stop-loss',stop,num:true)),const SizedBox(width:10),Expanded(child:_field('Take profit',target,num:true))]),ListTile(contentPadding:EdgeInsets.zero,title:Text('Trade date: ${DateFormat('dd MMM yyyy').format(date)}'),trailing:const Icon(Icons.calendar_month),onTap:()async{final d=await showDatePicker(context:c,firstDate:DateTime(2020),lastDate:DateTime.now().add(const Duration(days:365)),initialDate:date);if(d!=null)setState(()=>date=d);}),_field('Notes / Strategy',notes),const SizedBox(height:10),FilledButton(onPressed:(){if(!form.currentState!.validate())return;Navigator.pop(c,Trade(symbol:symbol.text.trim().toUpperCase(),side:side,setup:setup,status:status,notes:notes.text,entry:numVal(entry.text),exit:numVal(exit.text),qty:numVal(qty.text),stop:numVal(stop.text),target:numVal(target.text),charges:numVal(charges.text),date:date));},style:FilledButton.styleFrom(backgroundColor:navy,padding:const EdgeInsets.all(16)),child:const Text('Save trade'))]))));}
Widget _field(String label,TextEditingController ctrl,{bool num=false})=>Padding(padding:const EdgeInsets.only(bottom:10),child:TextFormField(controller:ctrl,keyboardType:num?const TextInputType.numberWithOptions(decimal:true):TextInputType.text,validator:(v)=>v==null||v.trim().isEmpty?'Required':null,decoration:InputDecoration(labelText:label,filled:true,fillColor:Colors.white,border:OutlineInputBorder(borderRadius:BorderRadius.circular(12),borderSide:BorderSide.none))));
Widget _drop(String label,String value,List<String> values,ValueChanged<String> change)=>Padding(padding:const EdgeInsets.only(bottom:10),child:DropdownButtonFormField<String>(value:value,decoration:InputDecoration(labelText:label,filled:true,fillColor:Colors.white,border:OutlineInputBorder(borderRadius:BorderRadius.circular(12),borderSide:BorderSide.none)),items:values.map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v){if(v!=null)change(v);}));

class TipEditor extends StatefulWidget {const TipEditor();@override State<TipEditor> createState()=>_TipEditorState();}
class _TipEditorState extends State<TipEditor>{final symbol=TextEditingController(text:'NIFTY');final entry=TextEditingController();final sl=TextEditingController();final t1=TextEditingController();final t2=TextEditingController();final reason=TextEditingController(text:'OI positioning and price action confirmation');String side='BUY',kind='Options';@override Widget build(BuildContext c)=>Padding(padding:EdgeInsets.only(bottom:MediaQuery.of(c).viewInsets.bottom),child:Container(height:MediaQuery.of(c).size.height*.85,padding:const EdgeInsets.all(20),decoration:const BoxDecoration(color:Colors.white,borderRadius:BorderRadius.vertical(top:Radius.circular(24))),child:ListView(children:[const Text('WhatsApp tip builder',style:TextStyle(fontSize:21,fontWeight:FontWeight.w800,color:ink)),const SizedBox(height:12),_field('Instrument',symbol),_drop('Trade type',kind,['Equity','Options','Futures'],(v)=>setState(()=>kind=v)),_drop('Action',side,['BUY','SELL'],(v)=>setState(()=>side=v)),_field('Entry price',entry,num:true),_field('Stop-loss',sl,num:true),_field('Target 1',t1,num:true),_field('Target 2 (optional)',t2,num:true),_field('Analysis / reason',reason),const SizedBox(height:10),FilledButton.icon(onPressed:(){if(entry.text.isEmpty||sl.text.isEmpty||t1.text.isEmpty){ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content:Text('Enter entry, stop-loss and target 1')));return;}final msg='📊 *TRADEPULSE TRADE SETUP*\n\nInstrument: *${symbol.text.toUpperCase()}*\nSegment: $kind\nAction: *$side*\nEntry: ${entry.text}\nStop-loss: ${sl.text}\nTarget 1: ${t1.text}${t2.text.isEmpty?'':'\nTarget 2: ${t2.text}'}\n\nAnalysis: ${reason.text}\n\n⚠️ Educational market idea, not a guaranteed return. Follow your own risk management.';Navigator.pop(c,msg);},icon:const Icon(Icons.share),label:const Text('Prepare WhatsApp message'),style:FilledButton.styleFrom(backgroundColor:teal,foregroundColor:navy,padding:const EdgeInsets.all(15)))])));
}
