import 'dart:async';

import 'package:flutter/material.dart';

import '../storage/vault_store.dart';
import 'folder_screen.dart';
import 'home_screen.dart';
import 'reader_screen.dart';

/// Gate screen, styled like Whisper's launcher: a single card that looks
/// empty ("There is nothing!"); a 3-second long press pops the password
/// dialog. The password is hard-coded in [VaultStore.kPassword] ('art').
///
/// If the vault was locked less than [gracePeriod] ago (e.g. the user just
/// switched apps and came back), the password is skipped and the last
/// screen (article, folder or home) is restored automatically.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  static const Duration gracePeriod = Duration(minutes: 1);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  Timer? _holdTimer;
  AppLifecycleListener? _lifecycle;
  bool _holding = false;
  bool _busy = false;
  bool _autoUnlocking = false;

  @override
  void initState() {
    super.initState();
    // Try the password-free path when the app comes back to the foreground
    // within the grace period.
    _lifecycle = AppLifecycleListener(onResume: _maybeAutoUnlock);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }

  Future<void> _maybeAutoUnlock() async {
    if (_busy || _autoUnlocking) return;
    final lockedAt = vault.lockedAt;
    if (lockedAt == null) return;
    if (DateTime.now().difference(lockedAt) > LoginScreen.gracePeriod) return;
    setState(() => _autoUnlocking = true);
    final ok = await vault.unlock(VaultStore.kPassword);
    if (!mounted) return;
    if (ok) {
      _goToLastPosition();
    } else {
      setState(() => _autoUnlocking = false);
    }
  }

  void _startHold() {
    if (_busy || _autoUnlocking) return;
    setState(() => _holding = true);
    _holdTimer?.cancel();
    _holdTimer = Timer(const Duration(seconds: 3), () async {
      setState(() => _holding = false);
      _showPasswordDialog();
    });
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    if (_holding) setState(() => _holding = false);
  }

  /// Whisper-style password gate: the password is hard-coded ('art') but
  /// must be typed — no hints on screen.
  Future<void> _showPasswordDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PasswordDialog(
        onSubmit: (password) {
          if (password == VaultStore.kPassword) {
            Navigator.pop(ctx);
            _enter();
            return true;
          }
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Wrong password')));
          return false;
        },
      ),
    );
  }

  Future<void> _enter() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (await vault.hasVault()) {
        final ok = await vault.unlock(VaultStore.kPassword);
        if (!ok) {
          // Data created by the old version used a user-chosen password and
          // cannot be unlocked with the hard-coded one. Offer a fresh start.
          if (!mounted) return;
          final erase = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('Cannot unlock data'),
              content: const Text(
                  'The data on this device was created by an older version '
                  'and cannot be unlocked by this version.\n\n'
                  'Erase it and start fresh?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Erase'),
                ),
              ],
            ),
          );
          if (erase != true || !mounted) return;
          await vault.eraseAll();
          await vault.createVault(VaultStore.kPassword);
        }
      } else {
        await vault.createVault(VaultStore.kPassword);
      }
      if (!mounted) return;
      _goToLastPosition();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Vault error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Restores the screen the user was on before locking (reader, folder or
  /// home) and clears the recorded position.
  void _goToLastPosition() {
    Widget? target;
    final reader = vault.lastReaderEntry;
    if (reader != null) {
      for (final f in vault.manifest.files) {
        if (f.id == reader.id) {
          target = ReaderScreen(entry: f);
          break;
        }
      }
    }
    if (target == null && vault.lastFolderId != null) {
      for (final f in vault.manifest.folders) {
        if (f.id == vault.lastFolderId) {
          target = FolderScreen(folderId: vault.lastFolderId!);
          break;
        }
      }
    }
    target ??= const HomeScreen();
    vault.lastReaderEntry = null;
    vault.lastFolderId = null;
    vault.positionLocked = false;
    final routeTarget = target;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => routeTarget),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Artic')),
      body: Center(
        child: _busy || _autoUnlocking
            ? const CircularProgressIndicator()
            : GestureDetector(
                onLongPressStart: (_) => _startHold(),
                onLongPressEnd: (_) => _cancelHold(),
                onLongPressCancel: _cancelHold,
                child: Opacity(
                  opacity: _holding ? 0.6 : 1.0,
                  child: const _MenuTile(title: 'There is nothing！'),
                ),
              ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final String title;

  const _MenuTile({required this.title});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

/// Password dialog whose TextEditingController lives in the State, so it is
/// disposed only when the dialog's exit animation has finished (disposing
/// it right after showDialog() returns crashes on the still-animating
/// TextField — "used after being disposed").
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.onSubmit});

  /// Returns true when the password was accepted (caller pops the dialog).
  final bool Function(String password) onSubmit;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final ok = widget.onSubmit(_ctrl.text);
    if (!ok) _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Password'),
      content: TextField(
        controller: _ctrl,
        obscureText: true,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Enter password'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('OK')),
      ],
    );
  }
}
