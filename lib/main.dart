import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'theme.dart';
import 'ui/home_page.dart';
import 'ui/settings_page.dart';
import 'ui/stats_page.dart';
import 'ui/today_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }
  final app = AppController();
  await app.bootstrap();
  runApp(ChangeNotifierProvider.value(value: app, child: const MedApp()));
}

class MedApp extends StatefulWidget {
  const MedApp({super.key});

  @override
  State<MedApp> createState() => _MedAppState();
}

class _MedAppState extends State<MedApp> {
  int _tab = 0;

  static const _pages = [TodayPage(), HomePage(), StatsPage(), SettingsPage()];
  static const _labels = ['今天', '药品', '统计', '设置'];
  static const _icons = [
    Icons.today_outlined,
    Icons.medication_outlined,
    Icons.insights_outlined,
    Icons.settings_outlined,
  ];
  static const _activeIcons = [
    Icons.today,
    Icons.medication,
    Icons.insights,
    Icons.settings,
  ];

  @override
  Widget build(BuildContext context) {
    final colorStyle = context.watch<AppController>().settings.colorStyle;
    final mode = context.watch<AppController>().settings.themeMode;
    return MaterialApp(
      title: '用药记录',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildAppTheme(AppTokens.pick(colorStyle, Brightness.light)),
      darkTheme: buildAppTheme(AppTokens.pick(colorStyle, Brightness.dark)),
      themeMode: switch (mode) {
        1 => ThemeMode.light,
        2 => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      home: Builder(
        builder: (context) {
          final t = AppTokens.of(context);
          final wide = MediaQuery.sizeOf(context).width >= 760;
          final stack = IndexedStack(index: _tab, children: _pages);
          if (!wide) {
            return Scaffold(
              backgroundColor: t.bg,
              body: stack,
              bottomNavigationBar: NavigationBar(
                elevation: 0,
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                destinations: [
                  for (var i = 0; i < _labels.length; i++)
                    NavigationDestination(
                      icon: Icon(_icons[i]),
                      selectedIcon: Icon(_activeIcons[i]),
                      label: _labels[i],
                    ),
                ],
              ),
            );
          }
          // 桌面端：左侧导航栏 + 居中限宽内容列，避免手机布局被拉满整个窗口。
          return Scaffold(
            backgroundColor: t.bg,
            body: Row(
              children: [
                NavigationRail(
                  backgroundColor: t.bg,
                  selectedIndex: _tab,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  labelType: NavigationRailLabelType.all,
                  indicatorColor: t.accentSoft,
                  selectedIconTheme: IconThemeData(color: t.accent),
                  selectedLabelTextStyle: TextStyle(
                    color: t.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                  unselectedIconTheme: IconThemeData(color: t.tx2),
                  unselectedLabelTextStyle: TextStyle(
                    color: t.tx2,
                    fontSize: 12,
                  ),
                  leading: Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 12),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: t.accent,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        Icons.medication_rounded,
                        color: t.onAccent,
                        size: 22,
                      ),
                    ),
                  ),
                  destinations: [
                    for (var i = 0; i < _labels.length; i++)
                      NavigationRailDestination(
                        icon: Icon(_icons[i]),
                        selectedIcon: Icon(_activeIcons[i]),
                        label: Text(_labels[i]),
                      ),
                  ],
                ),
                Container(width: 1, color: t.line),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: stack,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
