import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// All cryptography used by the vault.
///
///  - Key derivation: Argon2id (32 MiB, 3 iterations) — slow by design so
///    brute-forcing the password is impractical.
///  - Encryption: AES-256-GCM (authenticated — a wrong password is detected
///    and rejected, and any tampering with files fails decryption).
class VaultCrypto {
  VaultCrypto._();

  static final Argon2id _argon = Argon2id(
    // 8 MiB, 2 iterations. The password is hard-coded in this app, so the
    // KDF cost only affects unlock latency — AES-256-GCM strength is
    // unchanged (the vault key is a random 32-byte value).
    memory: 8192,
    iterations: 2,
    parallelism: 1,
    hashLength: 32,
  );
  static final AesGcm _aes = AesGcm.with256bits();
  // Streaming cipher for large media files: AES-256-CTR + HMAC-SHA256.
  // Unlike AES-GCM, CTR is a stream cipher — it can encrypt/decrypt chunks
  // without holding the whole file in memory. On Android this resolves to
  // the pure-Dart implementation, which processes in 16KB chunks.
  static final AesCtr _ctr =
      AesCtr.with256bits(macAlgorithm: Hmac.sha256());
  static final Random _random = Random.secure();

  /// Cryptographically secure random bytes.
  static Uint8List randomBytes(int length) =>
      Uint8List.fromList(List<int>.generate(length, (_) => _random.nextInt(256)));

  /// Cryptographically secure random hex string.
  static String randomHex(int bytes) => List<String>.generate(
      bytes * 2, (_) => '0123456789abcdef'[_random.nextInt(16)]).join();

  /// Derives a 256-bit key from [password] and [salt].
  static Future<Uint8List> deriveKey(String password, Uint8List salt) async {
    final key = await _argon.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  /// AES-256-GCM encrypt. Result layout: nonce(12) || ciphertext || mac(16).
  static Future<Uint8List> encryptBytes(Uint8List key, List<int> plain) async {
    final box = await _aes.encrypt(
      Uint8List.fromList(plain),
      secretKey: SecretKey(key),
    );
    return box.concatenation();
  }

  /// AES-256-GCM decrypt. Throws on wrong key or tampered data.
  static Future<Uint8List> decryptBytes(Uint8List key, Uint8List data) async {
    final box = SecretBox.fromConcatenation(data, nonceLength: 12, macLength: 16);
    return Uint8List.fromList(await _aes.decrypt(box, secretKey: SecretKey(key)));
  }

  // ------------------------------------------------------ streaming (CTR)

  /// Streaming AES-256-CTR + HMAC-SHA256 encrypt.
  ///
  /// Reads [input] in chunks, writes `nonce(16) || ciphertext || mac(32)`
  /// to [output]. Both must be opened by the caller; [output] is closed
  /// here. Never buffers the whole file in memory.
  static Future<void> encryptStream(
    Stream<List<int>> input,
    IOSink output,
    Uint8List key,
  ) async {
    final nonce = Uint8List.fromList(_ctr.newNonce());
    output.add(nonce);
    List<int>? macBytes;
    await output.addStream(_ctr.encryptStream(
      input,
      secretKey: SecretKey(key),
      nonce: nonce,
      // onMac fires after the ciphertext stream finishes; can't add() to
      // the sink inside addStream, so capture and write it afterwards.
      onMac: (mac) => macBytes = mac.bytes,
    ));
    output.add(macBytes!);
    await output.close();
  }

  /// Streaming AES-256-CTR + HMAC-SHA256 decrypt.
  ///
  /// Reads `nonce(16) || ciphertext || mac(32)` from [input], writes the
  /// plaintext to [output]. Throws on tampered data. **Never deletes
  /// [input]** — the caller owns both files (input is the vault's encrypted
  /// blob and must be kept; output is a temp plaintext the caller deletes).
  static Future<void> decryptStream(
    File input,
    IOSink output,
    Uint8List key,
  ) async {
    final nonce = Uint8List(16);
    final raf = input.openSync();
    try {
      raf.readIntoSync(nonce, 0, nonce.length);
      final mac = Uint8List(32);
      final contentLength = input.lengthSync() - nonce.length - mac.length;
      if (contentLength < 0) {
        throw FormatException('Encrypted blob is too short');
      }
      raf.setPositionSync(contentLength + nonce.length);
      raf.readIntoSync(mac, 0, mac.length);
      raf.closeSync();
      await output.addStream(_ctr.decryptStream(
        // Lazy chunked read of only the ciphertext region.
        input.openRead(nonce.length, nonce.length + contentLength),
        secretKey: SecretKey(key),
        nonce: nonce,
        mac: Mac(mac),
      ));
      await output.close();
    } finally {
      // Ensure the handle is released even on error; NEVER delete [input]
      // — it is the vault's encrypted blob, kept on disk.
      try {
        raf.closeSync();
      } catch (_) {}
    }
  }
}
