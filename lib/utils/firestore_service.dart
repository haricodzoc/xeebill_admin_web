import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Create operation
  Future<DocumentReference> addDocument(
    String collection,
    Map<String, dynamic> data,
  ) async {
    data['userId'] = _auth.currentUser?.uid;
    data['createdAt'] = DateTime.now();
    data['updatedAt'] = DateTime.now();

    return await _db.collection(collection).add(data);
  }

  // Read operations
  Future<List<DocumentSnapshot>> getDocuments(String collection) async {
    String? userId = _auth.currentUser?.uid;
    QuerySnapshot snapshot = await _db
        .collection(collection)
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .get();
    return snapshot.docs;
  }

  Future<DocumentSnapshot?> getDocument(String collection, String docId) async {
    String? userId = _auth.currentUser?.uid;
    DocumentSnapshot doc = await _db.collection(collection).doc(docId).get();
    if (doc.exists && doc.get('userId') == userId) {
      return doc;
    }
    return null;
  }

  // Update operation
  Future<void> updateDocument(
    String collection,
    String docId,
    Map<String, dynamic> data,
  ) async {
    data['updatedAt'] = DateTime.now();
    await _db.collection(collection).doc(docId).update(data);
  }

  // Delete operation
  Future<void> deleteDocument(String collection, String docId) async {
    await _db.collection(collection).doc(docId).delete();
  }

  // Stream operations for real-time updates
  Stream<QuerySnapshot> streamDocuments(String collection) {
    String? userId = _auth.currentUser?.uid;
    return _db
        .collection(collection)
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }
}
