import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../core/i18n.dart';
import '../state/config_provider.dart';
import '../state/connection_provider.dart';
import '../state/settings_provider.dart';
import '../theme.dart';
import 'app_hover_surface.dart';
import 'dialogs.dart';

/// 连接前的电影首页。
///
/// 空闲时直接显示静态场景；只有开始连接后才播放门洞校直与开启动画。
/// Flutter 负责真实控件与业务状态，视频结束后立即进入工作台。
class ConnectionEmptyState extends ConsumerStatefulWidget {
  const ConnectionEmptyState({super.key});

  @override
  ConsumerState<ConnectionEmptyState> createState() =>
      _ConnectionEmptyStateState();
}

class _ConnectionEmptyStateState extends ConsumerState<ConnectionEmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro;
  late final VideoPlayerController _connectingVideo;
  late final VideoPlayerController _enterVideo;

  VideoPlayerController? _activeVideo;
  ConnPhase? _lastPhase;
  bool _ready = false;
  int _sequenceId = 0;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..forward();
    _connectingVideo = VideoPlayerController.asset(
      'assets/cinematic/corridor_connecting.mp4',
    );
    _enterVideo = VideoPlayerController.asset(
      'assets/cinematic/corridor_enter.mp4',
    );
    _initializeVideos();
  }

  Future<void> _initializeVideos() async {
    try {
      await Future.wait([
        _connectingVideo.initialize(),
        _enterVideo.initialize(),
      ]);
      await _connectingVideo.setVolume(0);
      await _enterVideo.setVolume(0);
      if (!mounted) return;
      setState(() {
        _ready = true;
        _activeVideo = null;
      });
      _syncConnection(ref.read(connectionProvider).phase, force: true);
    } catch (_) {
      // 视频解码失败时保留母版定帧，连接功能仍可正常使用。
      if (mounted) setState(() => _ready = false);
    }
  }

  @override
  void dispose() {
    _sequenceId++;
    _intro.dispose();
    _connectingVideo.dispose();
    _enterVideo.dispose();
    super.dispose();
  }

  void _syncConnection(ConnPhase phase, {bool force = false}) {
    if (!_ready || (!force && _lastPhase == phase)) return;
    _lastPhase = phase;
    final sequenceId = ++_sequenceId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || sequenceId != _sequenceId) return;
      switch (phase) {
        case ConnPhase.connecting:
          _playConnectionSequence(sequenceId);
          break;
        case ConnPhase.connected:
          // 连接完成后由 AppShell 淡入工作台，不重复启动连接视频。
          break;
        case ConnPhase.error:
        case ConnPhase.idle:
          _showStaticHome(sequenceId);
          break;
      }
    });
  }

  Future<void> _showStaticHome(int sequenceId) async {
    await _connectingVideo.pause();
    await _enterVideo.pause();
    if (!mounted || sequenceId != _sequenceId) return;
    setState(() => _activeVideo = null);
  }

  Future<void> _playConnectionSequence(int sequenceId) async {
    await _connectingVideo.seekTo(Duration.zero);
    if (!mounted || sequenceId != _sequenceId) return;
    setState(() => _activeVideo = _connectingVideo);
    await _connectingVideo.play();
    await Future<void>.delayed(const Duration(milliseconds: 350));

    if (!mounted || sequenceId != _sequenceId) return;
    await _enterVideo.seekTo(Duration.zero);
    setState(() => _activeVideo = _enterVideo);
    await _enterVideo.play();
  }

  @override
  Widget build(BuildContext context) {
    final conn = ref.watch(connectionProvider);
    final hosts = ref.watch(hostsProvider);
    final zh = ref.watch(settingsProvider).lang == AppLang.zh;
    _syncConnection(conn.phase);

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentLeft = math.max(278.0, constraints.maxWidth * .18);
        final contentBottom = math.max(88.0, constraints.maxHeight * .09);
        final connecting = conn.phase == ConnPhase.connecting;

        return Stack(
          fit: StackFit.expand,
          children: [
            _CinematicVideo(controller: _activeVideo, ready: _ready),
            Positioned(
              left: contentLeft,
              bottom: contentBottom,
              child: AnimatedBuilder(
                animation: _intro,
                builder: (context, child) {
                  final reveal = AppMotion.standard.transform(_intro.value);
                  return AnimatedOpacity(
                    opacity: connecting ? 0 : reveal,
                    duration: AppMotion.quick,
                    curve: AppMotion.standard,
                    child: Transform.translate(
                      offset: Offset(0, 12 * (1 - reveal)),
                      child: child,
                    ),
                  );
                },
                child: _HeroCopy(
                  zh: zh,
                  connecting: connecting,
                  error: conn.phase == ConnPhase.error,
                  errorText: conn.error,
                  hasRecentHost: hosts.isNotEmpty,
                  onPrimary: () {
                    if (hosts.isEmpty) {
                      showAddHostDialog(context, ref);
                    } else {
                      ref
                          .read(connectionProvider.notifier)
                          .connect(hosts.first);
                    }
                  },
                  onNewConnection: () => showAddHostDialog(context, ref),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CinematicVideo extends StatelessWidget {
  const _CinematicVideo({required this.controller, required this.ready});

  final VideoPlayerController? controller;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final video = controller;
    if (!ready || video == null || !video.value.isInitialized) {
      return Image.asset(
        'assets/cinematic/breathing_corridor_master.png',
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      );
    }

    final size = video.value.size;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: VideoPlayer(video),
        ),
      ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({
    required this.zh,
    required this.connecting,
    required this.error,
    required this.errorText,
    required this.hasRecentHost,
    required this.onPrimary,
    required this.onNewConnection,
  });

  final bool zh;
  final bool connecting;
  final bool error;
  final String? errorText;
  final bool hasRecentHost;
  final VoidCallback onPrimary;
  final VoidCallback onNewConnection;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 480),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          zh ? '抵达远端。' : 'Reach the remote.',
          style: const TextStyle(
            color: Color(0xFF1B1D20),
            fontSize: 42,
            height: 1.05,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.6,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          zh
              ? '从一条可观察、可控制的 SSH 通道开始。'
              : 'Begin with an observable, controlled SSH passage.',
          style: TextStyle(color: AppColors.subtext, fontSize: 15, height: 1.5),
        ),
        const SizedBox(height: 26),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PrimaryAction(
              label: connecting
                  ? (zh ? '正在建立通道…' : 'Opening passage…')
                  : hasRecentHost
                  ? (zh ? '连接最近主机' : 'Connect recent host')
                  : (zh ? '连接主机' : 'Connect host'),
              busy: connecting,
              onTap: connecting ? null : onPrimary,
            ),
            if (hasRecentHost) ...[
              const SizedBox(width: 14),
              _TextAction(
                label: zh ? '新建连接' : 'New connection',
                onTap: onNewConnection,
              ),
            ],
          ],
        ),
        if (error) ...[
          const SizedBox(height: 13),
          Text(
            errorText ?? (zh ? '连接失败' : 'Connection failed'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.red, fontSize: 11.5),
          ),
        ],
      ],
    ),
  );
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AppHoverSurface(
    onTap: onTap,
    enabled: !busy,
    color: const Color(0xFF1B1D20),
    hoverColor: Colors.white.withValues(alpha: .11),
    pressedColor: Colors.white.withValues(alpha: .17),
    borderRadius: BorderRadius.circular(24),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy) ...[
          const SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 9),
        ],
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppHoverSurface(
    onTap: onTap,
    hoverColor: AppColors.text.withValues(alpha: .07),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    child: Text(
      label,
      style: TextStyle(
        color: AppColors.subtext,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}
