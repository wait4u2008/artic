import 'package:flutter/material.dart';

import '../screens/login_screen.dart';
import '../storage/vault_store.dart';

/// Locks the vault and returns to the login screen whenever the app goes
/// to the background (unless the system file picker is open).
///
/// Subclasses can override [onBeforeLock] to save state (e.g. the reader's
/// scroll position) before the manifest is dropped from memory.
mixin AutoLockMixin<T extends StatefulWidget> on State<T> {
  AppLifecycleListener? _listener;

  /// Called right before [VaultStore.lock] clears the in-memory manifest.
  void onBeforeLock() {}

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(onStateChange: (state) {
      if (state == AppLifecycleState.paused && !vault.pickerActive) {
        onBeforeLock();
        vault.lock();
        vault.positionLocked = true;
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _listener?.dispose();
    super.dispose();
  }
}
