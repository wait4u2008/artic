import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:notes/src/crypto/vault_crypto.dart';

void main() {
  test('AES-GCM roundtrip with Argon2id-derived key', () async {
    final key =
        await VaultCrypto.deriveKey('test password', VaultCrypto.randomBytes(16));
    final plain = VaultCrypto.randomBytes(500);
    final enc = await VaultCrypto.encryptBytes(key, plain);
    final dec = await VaultCrypto.decryptBytes(key, enc);
    expect(dec, plain);
  });

  test('wrong key is rejected (tamper detection)', () async {
    final k1 = await VaultCrypto.deriveKey('one', VaultCrypto.randomBytes(16));
    final k2 = await VaultCrypto.deriveKey('two', VaultCrypto.randomBytes(16));
    final enc = await VaultCrypto.encryptBytes(k1, [1, 2, 3, 4]);
    await expectLater(VaultCrypto.decryptBytes(k2, enc), throwsA(anything));
  });

  test('AES-CTR streaming roundtrip (large file)', () async {
    final dir = Directory.systemTemp.createTempSync('artic_ctr_test');
    try {
      final key =
          await VaultCrypto.deriveKey('test', VaultCrypto.randomBytes(16));
      // ~3 MB of pseudo-random data so it spans many 16KB cipher chunks.
      final plain = Uint8List(3 * 1024 * 1024);
      for (var i = 0; i < plain.length; i++) {
        plain[i] = (i * 31 + 7) & 0xFF;
      }
      final plainFile = File('${dir.path}/plain.bin')..writeAsBytesSync(plain);
      final encFile = File('${dir.path}/enc.bin');
      await VaultCrypto.encryptStream(
        plainFile.openRead(),
        encFile.openWrite(),
        key,
      );
      final decFile = File('${dir.path}/dec.bin');
      await VaultCrypto.decryptStream(
        encFile,
        decFile.openWrite(),
        key,
      );
      expect(decFile.readAsBytesSync(), plain);
      // decryptStream must NOT delete its input (the vault's encrypted
      // blob); the caller owns both files.
      expect(encFile.existsSync(), true);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('AES-CTR tamper detection', () async {
    final dir = Directory.systemTemp.createTempSync('artic_ctr_test2');
    try {
      final key =
          await VaultCrypto.deriveKey('test', VaultCrypto.randomBytes(16));
      final plainFile = File('${dir.path}/plain.bin')
        ..writeAsBytesSync(List.generate(4096, (i) => i & 0xFF));
      final encFile = File('${dir.path}/enc.bin');
      await VaultCrypto.encryptStream(
        plainFile.openRead(),
        encFile.openWrite(),
        key,
      );
      // Flip one byte inside the ciphertext.
      final bytes = encFile.readAsBytesSync();
      bytes[100] ^= 0xFF;
      encFile.writeAsBytesSync(bytes);
      await expectLater(
        VaultCrypto.decryptStream(
          encFile,
          File('${dir.path}/dec.bin').openWrite(),
          key,
        ),
        throwsA(anything),
      );
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
