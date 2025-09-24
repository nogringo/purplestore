import 'dart:io';

import 'package:ndk/ndk.dart';
import 'package:purplestore/src/purplestore.dart';
import 'package:test/test.dart';
import 'package:path/path.dart';
import 'package:sembast/sembast_io.dart';

void main() {
  group('PurpleStore Tests', () {
    late Ndk ndk;
    late PurpleStore store;
    late Database db;

    setUpAll(() async {
      ndk = Ndk(
        NdkConfig(
          eventVerifier: Bip340EventVerifier(),
          cache: MemCacheManager(),
          bootstrapRelays: ["ws://localhost:7777"],
        ),
      );

      ndk.accounts.loginPrivateKey(
        pubkey:
            "7a87f71033740a9baa1e451bb119abc41579de3ab3fabf56e23a527804cdb29f",
        privkey:
            "8a1898ac965479822f89b1ba3a3c716c7c394bafb41cc916cf9bccb7bd642129",
      );

      final dir = Directory("/home/gringo/Desktop/tests/purplestore_test");
      await dir.create(recursive: true);
      final dbPath = join(dir.path, 'my_database.db');
      db = await databaseFactoryIo.openDatabase(dbPath);

      store = PurpleStore(ndk: ndk, db: db);
    });

    tearDownAll(() async {
      await db.close();
      ndk.destroy();
    });

    test('should create a new document with auto-generated ID', () async {
      final newDoc = await store.collection("words").add({"word": "hello"});
      print('Created document with ID: ${newDoc.id}');
    });

    test('query collection', () async {
      await store.collection("fruits").doc("apple").set({"word": "apple"});
      await store.collection("fruits").doc("banana").set({"word": "banana"});

      final snapshot = await store.collection("fruits").get();
      for (var fruit in snapshot.docs) {
        print(fruit.data());
      }
    });
  });
}
