import 'package:ndk/ndk.dart';
import 'package:sembast/sembast.dart';
import 'collection.dart';

class PurpleStore {
  static const int documentKind = 33102;

  final Ndk ndk;
  final Database db;

  PurpleStore({required this.ndk, required this.db});

  /// Returns a reference to a collection
  CollectionReference collection(String path) {
    return CollectionReference(path: path, store: this);
  }
}
