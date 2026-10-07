import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/user.dart';
import '../models/focus_session.dart';

import '../services/auth_service.dart';
import '../services/focus_session_service.dart';

import '../widgets/pulsating_button.dart';
import '../widgets/setting_row.dart';
import '../widgets/breathing_character.dart';

import 'pomodoro_screen.dart';
import 'account_settings_screen.dart';
import 'statistics_screen.dart';
import 'whitelisted_apps_screen.dart';

class HomeScreen extends StatefulWidget {
  final Stream<Map<String, dynamic>> webSocketEvents;

  const HomeScreen({super.key, required this.webSocketEvents});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int studyMinutes = 25;
  int shortBreakMinutes = 5;
  int longBreakMinutes = 15;
  int sessionsUntilLongBreak = 4;

  final _authService = AuthService();
  final _focusSessionService = FocusSessionService();

  StreamSubscription<Map<String, dynamic>>? _webSocketSubscription;

  User? _user;
  bool _isLoadingUser = true;
  bool _isShowingFocusSettings = false;

  bool infiniteFocus = false;

  @override
  void initState() {
    super.initState();

    _loadUser();

    _webSocketSubscription = widget.webSocketEvents.listen(
      _handleWebSocketEvent,
    );
  }

  void _handleWebSocketEvent(Map<String, dynamic> event) {
    if (event['type'] != 'focus_session_started') {
      return;
    }

    if (_isShowingFocusSettings) {
      debugPrint('Ignoring focus session event while settings are open.');
      return;
    }

    if (ModalRoute.of(context)?.isCurrent != true) {
      debugPrint(
        'Ignoring focus session event because Pomodoro is already open.',
      );
      return;
    }

    final sessionJson = event['session'];

    if (sessionJson == null) {
      debugPrint('WebSocket event has no session.');
      return;
    }

    try {
      final focusSession = FocusSession.fromJson(
        sessionJson as Map<String, dynamic>,
      );

      debugPrint('HomeScreen received focus session: ${focusSession.id}');

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PomodoroScreen(
              focusSession: focusSession,
              studyMinutes: focusSession.studyDurationSeconds ~/ 60,
              shortBreakMinutes: focusSession.shortBreakDurationSeconds ~/ 60,
              longBreakMinutes: focusSession.longBreakDurationSeconds ~/ 60,
              sessionsUntilLongBreak: focusSession.sessionsUntilLongBreak,
              webSocketEvents: widget.webSocketEvents,
            ),
          ),
        );

        debugPrint('Opened Pomodoro from WebSocket: ${focusSession.id}');
      });
    } catch (error) {
      debugPrint('Failed to handle WebSocket event: $error');
    }
  }

  @override
  void dispose() {
    _webSocketSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadUser() async {
    try {
      final user = await _authService.getMe();
      final activeSession = await _focusSessionService.getActiveFocusSession();

      if (!mounted) return;

      setState(() {
        _user = user;
        _isLoadingUser = false;
      });

      debugPrint('Active session: ${activeSession?.id}');

      if (activeSession != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PomodoroScreen(
              focusSession: activeSession,
              studyMinutes: activeSession.studyDurationSeconds ~/ 60,
              shortBreakMinutes: activeSession.shortBreakDurationSeconds ~/ 60,
              longBreakMinutes: activeSession.longBreakDurationSeconds ~/ 60,
              sessionsUntilLongBreak: activeSession.sessionsUntilLongBreak,
              webSocketEvents: widget.webSocketEvents,
            ),
          ),
        );
      }
    } catch (error) {
      debugPrint('Failed to load home data: $error');

      if (!mounted) return;

      setState(() {
        _isLoadingUser = false;
      });
    }
  }

  // ----------------------------------------------------------
  // GREETING
  // ----------------------------------------------------------

  String get greeting {
    final hour = DateTime.now().hour;

    if (hour < 5) {
      return 'Good night';
    } else if (hour < 12) {
      return 'Good morning';
    } else if (hour < 18) {
      return 'Good afternoon';
    } else if (hour < 22) {
      return 'Good evening';
    } else {
      return 'Good night';
    }
  }

  String get focusMessage {
    final hour = DateTime.now().hour;

    if (hour < 5) {
      return 'Still up? Ready to focus?';
    } else if (hour < 12) {
      return 'Ready to make a little progress?';
    } else if (hour < 18) {
      return 'Ready to get some work done?';
    } else if (hour < 22) {
      return 'Ready to focus for a while?';
    } else {
      return 'One last productive push?';
    }
  }

  // ----------------------------------------------------------
  // SETTINGS
  // ----------------------------------------------------------

  Future<void> showFocusSettings() async {
    setState(() {
      _isShowingFocusSettings = true;
    });

    final activeSession = await showModalBottomSheet<FocusSession>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF151D2F)
          : const Color(0xFFE8F1F7),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;

            final textColor = isDark ? Colors.white : const Color(0xFF263746);

            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.9,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 25, 24, 35),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'FOCUS SETTINGS',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2,
                        ),
                      ),

                      const SizedBox(height: 20),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Infinite Focus',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white70
                                  : const Color(0xAA34495E),
                              fontSize: 16,
                            ),
                          ),
                          Switch(
                            value: infiniteFocus,
                            onChanged: (value) {
                              setModalState(() {
                                infiniteFocus = value;
                              });
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),
                      if (!infiniteFocus) ...[
                        SettingRow(
                          title: 'Focus',
                          value: studyMinutes,
                          min: 1,
                          max: 120,
                          presets: const [15, 25, 30, 45, 60],
                          unit: 'min',
                          onValueChanged: (newValue) {
                            setModalState(() {
                              studyMinutes = newValue;
                            });
                          },
                        ),

                        SettingRow(
                          title: 'Short Break',
                          value: shortBreakMinutes,
                          min: 1,
                          max: 30,
                          presets: const [5, 10, 15, 20, 30],
                          unit: 'min',
                          onValueChanged: (newValue) {
                            setModalState(() {
                              shortBreakMinutes = newValue;
                            });
                          },
                        ),

                        SettingRow(
                          title: 'Long Break',
                          value: longBreakMinutes,
                          min: 1,
                          max: 60,
                          presets: const [10, 15, 20, 30, 45],
                          unit: 'min',
                          onValueChanged: (newValue) {
                            setModalState(() {
                              longBreakMinutes = newValue;
                            });
                          },
                        ),

                        SettingRow(
                          title: 'Sessions Until A Long Break',
                          value: sessionsUntilLongBreak,
                          min: 1,
                          max: 12,
                          presets: const [2, 3, 4, 6, 8],
                          unit: 'sessions',
                          onValueChanged: (newValue) {
                            setModalState(() {
                              sessionsUntilLongBreak = newValue;
                            });
                          },
                        ),
                      ],
                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () async {
                            try {
                              final focusSession = await _focusSessionService
                                  .createFocusSession(
                                    studyDurationSeconds: studyMinutes * 60,
                                    shortBreakDurationSeconds:
                                        shortBreakMinutes * 60,
                                    longBreakDurationSeconds:
                                        longBreakMinutes * 60,
                                    sessionsUntilLongBreak:
                                        sessionsUntilLongBreak,
                                    isInfinite: infiniteFocus,
                                  );

                              if (!context.mounted) return;

                              debugPrint(
                                'Created focus session: ${focusSession.id}',
                              );

                              Navigator.pop(context, focusSession);
                            } catch (error) {
                              if (!context.mounted) return;

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    error.toString().replaceFirst(
                                      'Exception: ',
                                      '',
                                    ),
                                  ),
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark
                                ? Colors.white
                                : const Color(0xFF34495E),
                            foregroundColor: isDark
                                ? Colors.black
                                : Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(26),
                            ),
                          ),
                          child: const Text(
                            'START FOCUSING',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (mounted) {
      setState(() {
        _isShowingFocusSettings = false;
      });
    }

    if (!mounted || activeSession == null) {
      return;
    }

    debugPrint('Opening Pomodoro locally: ${activeSession.id}');

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PomodoroScreen(
          focusSession: activeSession,
          studyMinutes: activeSession.studyDurationSeconds ~/ 60,
          shortBreakMinutes: activeSession.shortBreakDurationSeconds ~/ 60,
          longBreakMinutes: activeSession.longBreakDurationSeconds ~/ 60,
          sessionsUntilLongBreak: activeSession.sessionsUntilLongBreak,
          webSocketEvents: widget.webSocketEvents,
        ),
      ),
    );

    await _loadUser();
  }

  // ----------------------------------------------------------
  // BUILD
  // ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final backgroundColors = isDark
        ? const [
            Color(0xFF0B1020),
            Color(0xFF14253A),
            Color(0xFF394052),
            Color(0xFF6B493F),
            Color(0xFF9A5A3A),
          ]
        : const [
            Color(0xFFBFDDF2),
            Color(0xFFA9CDE8),
            Color(0xFFC5C9C5),
            Color(0xFFE0B49A),
            Color(0xFFD58B62),
          ];

    final primaryTextColor = isDark ? Colors.white : const Color(0xFF263746);

    final secondaryTextColor = isDark
        ? Colors.white60
        : const Color(0x8834495E);

    return Scaffold(
      body: Stack(
        children: [
          // --------------------------------------------------
          // GRADIENT
          // --------------------------------------------------

          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: backgroundColors,
              ),
            ),
          ),

          // --------------------------------------------------
          // 3D IMAGE
          // --------------------------------------------------
          IgnorePointer(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 90),
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    Image.asset('assets/images/test.webp'),
                    BreathingCharacter(
                      imagePath: 'assets/images/lil_guy_waitin.webp',
                    ),
                  ],
                ),
              ),
            ),
          ),

          // --------------------------------------------------
          // CONTENT
          // --------------------------------------------------
          SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: MediaQuery.of(context).size.height * 0.30,
                  left: 0,
                  right: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isLoadingUser
                            ? greeting
                            : '$greeting, ${_user?.username ?? 'User'}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: primaryTextColor,
                          fontSize: 32,
                          fontWeight: FontWeight.w400,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        focusMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: secondaryTextColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w300,
                        ),
                      ),

                      const SizedBox(height: 35),

                      PulsatingButton(
                        text: 'START FOCUS SESSION',
                        onPressed: showFocusSettings,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 100),
                    color: Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: 0.35),
                  ),

                  const SizedBox(height: 8),

                  Row(
                    children: [
                      _BottomNavButton(
                        icon: Icon(
                          LucideIcons.circleUserRound300,
                          color: Theme.of(context).colorScheme.onSurface,
                          size: 30,
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AccountSettingsScreen(),
                            ),
                          );
                        },
                      ),

                      _BottomNavButton(
                        icon: Icon(
                          LucideIcons.calendar300,
                          color: Theme.of(context).colorScheme.onSurface,
                          size: 30,
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const StatisticsScreen(),
                            ),
                          );
                        },
                      ),

                      _BottomNavButton(
                        icon: Icon(
                          LucideIcons.circleDashedCheck300,
                          color: Theme.of(context).colorScheme.onSurface,
                          size: 30,
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const WhitelistedAppsScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomNavButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback onTap;

  const _BottomNavButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: IconButton(
        onPressed: onTap,
        icon: icon,
        iconSize: 30,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      ),
    );
  }
}
