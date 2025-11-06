import 'package:flutter/material.dart';
import 'package:nylo_framework/nylo_framework.dart';
import '/app/services/call_overlay_service.dart';
import '/resources/widgets/call_overlay_banner.dart';

/// Main entry point for the application
class Main extends StatelessWidget {
  final String? initialRoute;
  final ThemeMode themeMode;
  final List<NavigatorObserver> navigatorObservers;
  final GlobalKey<NavigatorState>? navigatorKey;
  final Route<dynamic>? Function(RouteSettings settings) onGenerateRoute;
  final Route<dynamic>? Function(RouteSettings settings) onUnknownRoute;

  Main(
    Nylo nylo, {
    super.key,
  })  : onGenerateRoute = nylo.router!.generator(),
        onUnknownRoute = nylo.router!.unknownRoute(),
        navigatorKey = NyNavigator.instance.router.navigatorKey,
        initialRoute = nylo.getInitialRoute(),
        navigatorObservers = nylo.getNavigatorObservers(),
        themeMode = ThemeMode.system;

  @override
  Widget build(BuildContext context) {
    List<AppTheme> appThemes = Nylo.getAppThemes();
    return Container(
      color: Color(0xFFE8E7EA),
      child: LocalizedApp(
        child: ThemeProvider(
          themes: appThemes,
          child: ThemeConsumer(
            child: ValueListenableBuilder(
              valueListenable: ValueNotifier(NyLocalization.instance.locale),
              builder: (context, Locale locale, _) => MaterialApp(
                navigatorKey: navigatorKey,
                themeMode: themeMode,
                navigatorObservers: navigatorObservers,
                debugShowMaterialGrid: false,
                showPerformanceOverlay: false,
                checkerboardRasterCacheImages: false,
                checkerboardOffscreenLayers: false,
                showSemanticsDebugger: false,
                debugShowCheckedModeBanner: false,
                darkTheme: appThemes.darkTheme,
                initialRoute: initialRoute,
                onGenerateRoute: onGenerateRoute,
                onUnknownRoute: onUnknownRoute,
                theme: ThemeProvider.themeOf(context).data,
                localeResolutionCallback:
                    (Locale? locale, Iterable<Locale> supportedLocales) {
                  return locale;
                },
                localizationsDelegates: NyLocalization.instance.delegates,
                locale: locale,
                supportedLocales: [Locale('en', 'US')],
                builder: (context, child) {
                  // Wrap the entire app with the call overlay banner
                  return StreamBuilder<CallOverlayState?>(
                    stream: CallOverlayService().overlayStream,
                    builder: (context, snapshot) {
                      final callState = snapshot.data;
                      final hasBanner = callState != null;
                      
                      // Calculate banner height (SafeArea top + padding + content)
                      final topPadding = MediaQuery.of(context).padding.top;
                      final bannerHeight = hasBanner ? topPadding + 38.0 : 0.0;
                      
                      return Stack(
                        children: [
                          // The main app content with top padding when banner is showing
                          Positioned.fill(
                            top: bannerHeight,
                            child: child ?? const SizedBox.shrink(),
                          ),
                          
                          // Global call overlay banner (appears on ALL pages)
                          if (hasBanner)
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: CallOverlayBanner(callState: callState),
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
