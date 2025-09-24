import 'dart:io';

import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:path/path.dart';
import 'package:purplestore/purplestore.dart';
import 'package:sembast/sembast_io.dart';

void main() async {
  final ndk = Ndk(
    NdkConfig(
      eventVerifier: Bip340EventVerifier(),
      cache: MemCacheManager(),
      bootstrapRelays: ["ws://localhost:7777"],
    ),
  );

  final keyPair = Bip340.generatePrivateKey();
  ndk.accounts.loginPrivateKey(
    pubkey: keyPair.publicKey,
    privkey: keyPair.privateKey!,
  );

  final dir = Directory("/home/gringo/Desktop/tests/purplestore_test");
  await dir.create(recursive: true);
  final dbPath = join(dir.path, 'my_database.db');
  final db = await databaseFactoryIo.openDatabase(dbPath);

  final purpleStore = PurpleStore(ndk: ndk, db: db);

  final collectionRef = purpleStore.collection("words");

  // Listen to real-time updates
  final subscription = collectionRef.onSnapshot().listen((snapshot) {
    print('Collection has ${snapshot.docs.length} documents');
  });

  // Create or update a document
  final docRef = collectionRef.doc("hello");
  await docRef.set({"word": "world"});

  // Add a new document with auto-generated ID
  final newDoc = await collectionRef.add({"word": "galaxy"});
  print('Created document with ID: ${newDoc.id}');

  // Query all documents
  final snapshot = await collectionRef.get();
  for (var word in snapshot.docs) {
    print('Document ${word.id}: ${word.data()}');
  }

  // Delete a document
  await docRef.delete();

  // Wait a bit for operations to complete
  await Future.delayed(Duration(seconds: 1));

  // Clean up resources properly
  await subscription.cancel();
  await db.close();
  ndk.destroy();

  print('Example completed and all resources cleaned up');
}
