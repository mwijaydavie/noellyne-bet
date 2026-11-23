import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../design/noellyne_ui.dart';
import '../services/noellyne_ai_service.dart';
import '../services/noellyne_auth_service.dart';
import 'daily_picks_page.dart';
import 'home_page.dart';

/// Noellyne AI — a real chat view over the n8n betting brain, with an offline
/// fallback so it never looks broken when the webhook isn't wired yet.
class AiChatPage extends StatefulWidget {
  const AiChatPage({
    super.key,
    this.onOpenPicks,
    this.initialPrompt,
    this.matchContext,
  });

  final VoidCallback? onOpenPicks;
  final String? initialPrompt;
  final Map<String, dynamic>? matchContext;

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _service = const NoellyneAiService();
  final _messages = <AiMessage>[];
  bool _sending = false;

  // Typewriter: AI replies stream in character-by-character.
  Timer? _typer;
  int _typingIndex = -1;
  int _typingChars = 0;

  @override
  void initState() {
    super.initState();
    _messages.add(
      AiMessage(
        'Karibu! Mimi ni Noellyne AI.\n'
        'Niulize kuhusu picks za football, NBA, matokeo, au mgao wa mtaji — '
        'mfano "Nina 20,000 leo".',
        fromUser: false,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final preset = widget.initialPrompt?.trim() ?? '';
      if (preset.isNotEmpty) {
        _send(preset);
      } else {
        _startTyping(_messages.length - 1);
      }
    });
  }

  /// Reveals [index] character by character, then settles on the full text.
  void _startTyping(int index) {
    _typer?.cancel();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      setState(() {
        _typingIndex = -1;
        _typingChars = 0;
      });
      return;
    }
    final full = _messages[index].text;
    setState(() {
      _typingIndex = index;
      _typingChars = 0;
    });
    _typer = Timer.periodic(const Duration(milliseconds: 12), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        // ~4 chars per tick reads like a fast model stream.
        _typingChars = (_typingChars + 4).clamp(0, full.length).toInt();
      });
      if (_typingChars >= full.length) {
        timer.cancel();
        setState(() => _typingIndex = -1);
        _scrollToEnd();
      } else if (_typingChars % 48 == 0) {
        _scrollToEnd();
      }
    });
  }

  /// Tapping a message while it streams finishes it immediately.
  void _finishTyping() {
    if (_typingIndex < 0) return;
    _typer?.cancel();
    setState(() {
      _typingIndex = -1;
      _typingChars = 0;
    });
  }

  @override
  void dispose() {
    _typer?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: NoellyneMotion.revealCurve,
      );
    });
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty || _sending) return;
    HapticFeedback.lightImpact();
    setState(() {
      _messages.add(AiMessage(text, fromUser: true));
      _messages.add(AiMessage('', fromUser: false, pending: true));
      _sending = true;
      _controller.clear();
    });
    _scrollToEnd();

    final reply = await _service.sendStructured(
      _messages,
      matchContext: widget.matchContext,
    );

    if (!mounted) return;
    setState(() {
      _messages.removeWhere((m) => m.pending);
      _messages.add(
        AiMessage(
          reply.text,
          fromUser: false,
          actions: reply.actions,
        ),
      );
      _sending = false;
    });
    _scrollToEnd();
    _startTyping(_messages.length - 1);
  }

  Future<void> _handleAction(AiAction action) async {
    HapticFeedback.lightImpact();
    switch (action.type) {
      case 'sign_in':
        await NoellyneAuthService.instance.signInWithGoogle();
      case 'open_picks':
      case 'open_results':
        if (widget.onOpenPicks != null) {
          widget.onOpenPicks!.call();
        } else if (mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const DailyPicksPage()),
          );
        }
      case 'open_watch':
        final sid = action.streamId?.trim() ?? '';
        if (mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => HomePage(initialMatchId: sid.isEmpty ? null : sid),
            ),
          );
        }
      case 'copy_text':
        final txt = action.text?.trim() ?? '';
        if (txt.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: txt));
          if (!mounted) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(content: Text('Copied to clipboard')),
            );
        }
      case 'open_url':
        final raw = action.url?.trim() ?? '';
        final uri = Uri.tryParse(raw);
        if (uri != null &&
            (uri.scheme == 'https' || uri.scheme == 'http')) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        toolbarHeight: 64,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [NoellyneColors.glowSoft, NoellyneColors.glowDeep],
                ),
                boxShadow: [
                  BoxShadow(
                    color: NoellyneColors.glowDeep.withValues(alpha: .45),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  size: 18, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Noellyne AI',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.3,
                    color: scheme.onSurface,
                  ),
                ),
                ValueListenableBuilder<NoellyneUser?>(
                  valueListenable: NoellyneAuthService.instance.user,
                  builder: (context, account, _) {
                    return ValueListenableBuilder<AiQuota?>(
                      valueListenable: NoellyneAiService.quota,
                      builder: (context, quota, _) {
                        String statusLabel;
                        if (!_service.isConfigured) {
                          statusLabel = 'offline brain · add webhook';
                        } else if (account?.isVipOwner == true ||
                            quota?.unlimited == true) {
                          statusLabel = 'VIP Unlimited · Noellyne AI';
                        } else if (quota != null && quota.limit > 0) {
                          statusLabel = account == null
                              ? 'Guest · ${quota.remaining}/${quota.limit} free left today'
                              : 'Member · ${quota.remaining}/${quota.limit} left today';
                        } else {
                          statusLabel = account == null
                              ? 'Guest · 3 free chats/day'
                              : 'Member · 10 chats/day';
                        }
                        return Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _service.isConfigured
                                    ? NoellyneColors.winDark
                                    : NoellyneColors.glowDeep,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              statusLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: account?.isVipOwner == true
                                    ? NoellyneColors.winDark
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          ValueListenableBuilder<NoellyneUser?>(
            valueListenable: NoellyneAuthService.instance.user,
            builder: (context, account, _) {
              if (account != null) return const SizedBox.shrink();
              return IconButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  NoellyneAuthService.instance.signInWithGoogle();
                },
                icon: const Icon(Icons.login_rounded, size: 19),
                tooltip: 'Sign in with Google',
              );
            },
          ),
          if (widget.onOpenPicks != null)
            TextButton.icon(
              onPressed: widget.onOpenPicks,
              icon: const Icon(Icons.receipt_long_rounded, size: 16),
              label: const Text('Picks'),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: NoellyneBackground(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                itemCount: _messages.length,
                itemBuilder: (context, i) {
                  final m = _messages[i];
                  return _Bubble(
                    message: m,
                    typing: i == _typingIndex,
                    visibleChars: i == _typingIndex ? _typingChars : null,
                    onTapWhileTyping: _finishTyping,
                    onAction: _handleAction,
                  );
                },
              ),
            ),
            _QuickPrompts(
              enabled: !_sending,
              onPick: (p) => _send(p),
            ),
            _Composer(
              controller: _controller,
              sending: _sending,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    this.typing = false,
    this.visibleChars,
    this.onTapWhileTyping,
    this.onAction,
  });

  final AiMessage message;
  final bool typing;
  final int? visibleChars;
  final VoidCallback? onTapWhileTyping;
  final ValueChanged<AiAction>? onAction;

  IconData _iconFor(String type) => switch (type) {
        'sign_in' => Icons.login_rounded,
        'open_picks' => Icons.receipt_long_rounded,
        'open_results' => Icons.analytics_outlined,
        'open_watch' => Icons.play_arrow_rounded,
        'copy_text' => Icons.copy_all_rounded,
        _ => Icons.open_in_new_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final mine = message.fromUser;

    if (message.pending) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            const _TypingDots(),
            const SizedBox(width: 8),
            Text(
              'Noellyne AI anaandika…',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: 10,
        left: mine ? 46 : 0,
        right: mine ? 0 : 34,
      ),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: typing ? onTapWhileTyping : null,
              onLongPress: () async {
                await Clipboard.setData(ClipboardData(text: message.text));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    const SnackBar(content: Text('Message copied')),
                  );
              },
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
                decoration: BoxDecoration(
                  color: mine
                      ? (dark ? NoellyneColors.glowDark : NoellyneColors.ink)
                      : (dark
                          ? NoellyneColors.innerDark
                          : NoellyneColors.innerLight),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: Radius.circular(mine ? 20 : 6),
                    bottomRight: Radius.circular(mine ? 6 : 20),
                  ),
                  border: Border.all(
                    color: dark
                        ? NoellyneColors.glassBorderDark
                        : const Color(0x88FFFFFF),
                  ),
                ),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: visibleChars == null
                            ? message.text
                            : message.text.substring(
                                0,
                                visibleChars!
                                    .clamp(0, message.text.length)
                                    .toInt(),
                              ),
                      ),
                      if (typing)
                        TextSpan(
                          text: '▍',
                          style: TextStyle(
                            color: NoellyneColors.glowDeep,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.42,
                    fontWeight: FontWeight.w500,
                    color: mine
                        ? (dark ? NoellyneColors.ink : Colors.white)
                        : scheme.onSurface,
                  ),
                ),
              ),
            ),
            if (!mine && !typing && message.actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final act in message.actions)
                    ActionChip(
                      avatar: Icon(
                        _iconFor(act.type),
                        size: 15,
                        color: act.type == 'sign_in'
                            ? Colors.white
                            : NoellyneColors.glowDeep,
                      ),
                      label: Text(
                        act.label,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: act.type == 'sign_in'
                              ? Colors.white
                              : scheme.onSurface,
                        ),
                      ),
                      backgroundColor: act.type == 'sign_in'
                          ? NoellyneColors.glowDeep
                          : (dark
                              ? NoellyneColors.innerDark
                              : NoellyneColors.innerLight),
                      side: BorderSide(
                        color: NoellyneColors.glowDeep.withValues(alpha: .35),
                      ),
                      onPressed: onAction == null ? null : () => onAction!(act),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 30,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) {
              final t = ((_c.value + i * .2) % 1);
              final scale = .7 + (.35 * (1 - (t - .5).abs() * 2).clamp(0, 1));
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.5),
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: NoellyneColors.glowDeep.withValues(alpha: .85),
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

class _QuickPrompts extends StatelessWidget {
  const _QuickPrompts({required this.enabled, required this.onPick});

  final bool enabled;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: NoellyneAiService.quickPrompts.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final p = NoellyneAiService.quickPrompts[i];
          return FilterPill(
            label: p,
            onTap: enabled ? () => onPick(p) : null,
          );
        },
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final Future<void> Function([String? preset]) onSend;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: dark
                      ? NoellyneColors.innerDark
                      : NoellyneColors.innerLight,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: dark
                        ? NoellyneColors.glassBorderDark
                        : const Color(0x99FFFFFF),
                  ),
                ),
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  style: TextStyle(fontSize: 13.5, color: scheme.onSurface),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Uliza kuhusu mechi, picks, au mtaji…',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            PressableScale(
              onTap: sending ? null : () => onSend(),
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: sending
                        ? [
                            NoellyneColors.glowSoft.withValues(alpha: .5),
                            NoellyneColors.glowDeep.withValues(alpha: .5),
                          ]
                        : const [
                            NoellyneColors.glowSoft,
                            NoellyneColors.glowDeep,
                          ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: NoellyneColors.glowDeep.withValues(alpha: .4),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.arrow_upward_rounded,
                  color: dark ? NoellyneColors.ink : Colors.white,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
