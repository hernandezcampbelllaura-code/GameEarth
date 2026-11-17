import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../firebase_options.dart';

typedef Json = Map<String, dynamic>;

FirebaseFirestore get fs => FirebaseFirestore.instance;

/// UID del usuario con sesión iniciada.
String get myUid => FirebaseAuth.instance.currentUser!.uid;

/// Acceso a Firestore y todas las acciones de la app.
class Db {
  Db._();

  static CollectionReference<Json> get users => fs.collection('users');
  static CollectionReference<Json> get posts => fs.collection('posts');
  static CollectionReference<Json> get reports => fs.collection('reports');
  static CollectionReference<Json> get usernames => fs.collection('usernames');
  static CollectionReference<Json> get groups => fs.collection('groups');

  // ---------- Publicaciones ----------

  static Future<void> createPost(
    String text,
    String imageUrl, {
    String videoUrl = '',
    String linkUrl = '',
    String groupId = '',
    String description = '',
    List<String> pollOptions = const [],
  }) {
    return posts.add({
      'authorId': myUid,
      'authorName': Session.i.username,
      'text': text,
      'imageUrl': imageUrl,
      'videoUrl': videoUrl,
      'linkUrl': linkUrl,
      'groupId': groupId,
      'description': description,
      'pollOptions': pollOptions,
      'pollCounts': {for (var i = 0; i < pollOptions.length; i++) '$i': 0},
      'views': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'likesCount': 0,
      'commentsCount': 0,
    });
  }

  static Future<void> setLike(String postId, bool like) {
    final p = posts.doc(postId);
    final l = p.collection('likes').doc(myUid);
    final b = fs.batch();
    if (like) {
      b.set(l, {'createdAt': FieldValue.serverTimestamp()});
      b.update(p, {'likesCount': FieldValue.increment(1)});
    } else {
      b.delete(l);
      b.update(p, {'likesCount': FieldValue.increment(-1)});
    }
    return b.commit();
  }

  /// Reacciona a una publicación. Si ya tenías esa misma reacción, la quita;
  /// si tenías otra, la cambia (el contador total no cambia).
  static Future<void> react(String postId, String type) async {
    final p = posts.doc(postId);
    final l = p.collection('likes').doc(myUid);
    final snap = await l.get();
    final cur = snap.exists ? ((snap.data()?['type'] ?? 'love') as String) : null;
    if (cur == null) {
      final b = fs.batch();
      b.set(l, {'createdAt': FieldValue.serverTimestamp(), 'type': type});
      b.update(p, {'likesCount': FieldValue.increment(1)});
      await b.commit();
    } else if (cur == type) {
      final b = fs.batch();
      b.delete(l);
      b.update(p, {'likesCount': FieldValue.increment(-1)});
      await b.commit();
    } else {
      await l.update({'type': type});
    }
  }

  /// Cuenta cuántas reacciones hay de cada tipo.
  static Future<Map<String, int>> reactionCounts(String postId) async {
    final q = await posts.doc(postId).collection('likes').limit(1000).get();
    final out = <String, int>{};
    for (final d in q.docs) {
      final t = (d.data()['type'] ?? 'love') as String;
      out[t] = (out[t] ?? 0) + 1;
    }
    return out;
  }

  /// Vota en la encuesta de una publicación (un voto por persona).
  static Future<void> vote(String postId, int option) {
    final p = posts.doc(postId);
    final b = fs.batch();
    b.set(p.collection('votes').doc(myUid), {
      'option': option,
      'createdAt': FieldValue.serverTimestamp(),
    });
    b.update(p, {'pollCounts.$option': FieldValue.increment(1)});
    return b.commit();
  }

  static final Set<String> _seenViews = {};

  /// Suma una visita (una sola por persona). No cuenta las del propio autor.
  static Future<void> registerView(String postId, String authorId) async {
    if (authorId == myUid || !_seenViews.add(postId)) return;
    try {
      final p = posts.doc(postId);
      final v = p.collection('views').doc(myUid);
      if ((await v.get()).exists) return;
      final b = fs.batch();
      b.set(v, {'createdAt': FieldValue.serverTimestamp()});
      b.update(p, {'views': FieldValue.increment(1)});
      await b.commit();
    } catch (_) {
      // Una visita que falla no debe molestar a nadie.
    }
  }

  static Future<void> addComment(String postId, String text) {
    final p = posts.doc(postId);
    final c = p.collection('comments').doc();
    final b = fs.batch();
    b.set(c, {
      'authorId': myUid,
      'authorName': Session.i.username,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
    b.update(p, {'commentsCount': FieldValue.increment(1)});
    return b.commit();
  }

  static Future<void> deleteComment(String postId, String commentId) {
    final p = posts.doc(postId);
    final b = fs.batch();
    b.delete(p.collection('comments').doc(commentId));
    b.update(p, {'commentsCount': FieldValue.increment(-1)});
    return b.commit();
  }

  // ---------- Grupos ----------

  static Future<void> createGroup(String name, String description) {
    final g = groups.doc();
    final b = fs.batch();
    b.set(g, {
      'name': name,
      'description': description,
      'ownerId': myUid,
      'ownerName': Session.i.username,
      'membersCount': 1,
      'createdAt': FieldValue.serverTimestamp(),
    });
    b.set(g.collection('members').doc(myUid),
        {'createdAt': FieldValue.serverTimestamp()});
    return b.commit();
  }

  static Future<void> joinGroup(String groupId) {
    final g = groups.doc(groupId);
    final b = fs.batch();
    b.set(g.collection('members').doc(myUid),
        {'createdAt': FieldValue.serverTimestamp()});
    b.update(g, {'membersCount': FieldValue.increment(1)});
    return b.commit();
  }

  static Future<void> leaveGroup(String groupId) {
    final g = groups.doc(groupId);
    final b = fs.batch();
    b.delete(g.collection('members').doc(myUid));
    b.update(g, {'membersCount': FieldValue.increment(-1)});
    return b.commit();
  }

  /// Borra el grupo y sus publicaciones (dueño o admin).
  static Future<void> deleteGroup(String groupId) async {
    final mine = await posts.where('groupId', isEqualTo: groupId).get();
    final docs = mine.docs;
    for (var i = 0; i < docs.length; i += 400) {
      final b = fs.batch();
      for (final d in docs.skip(i).take(400)) {
        b.delete(d.reference);
      }
      await b.commit();
    }
    await groups.doc(groupId).delete();
  }

  // ---------- Seguir / bloquear ----------

  static Future<void> follow(String other) {
    final b = fs.batch();
    b.set(users.doc(myUid).collection('following').doc(other),
        {'createdAt': FieldValue.serverTimestamp()});
    b.set(users.doc(other).collection('followers').doc(myUid),
        {'createdAt': FieldValue.serverTimestamp()});
    return b.commit();
  }

  static Future<void> unfollow(String other) {
    final b = fs.batch();
    b.delete(users.doc(myUid).collection('following').doc(other));
    b.delete(users.doc(other).collection('followers').doc(myUid));
    return b.commit();
  }

  static Future<void> block(String other, String name) {
    final b = fs.batch();
    b.set(users.doc(myUid).collection('blocked').doc(other), {
      'username': name,
      'createdAt': FieldValue.serverTimestamp(),
    });
    b.delete(users.doc(myUid).collection('following').doc(other));
    b.delete(users.doc(other).collection('followers').doc(myUid));
    return b.commit();
  }

  static Future<void> unblock(String other) {
    return users.doc(myUid).collection('blocked').doc(other).delete();
  }

  // ---------- Perfil ----------

  static Future<void> updateProfile({
    required String bio,
    required String photoUrl,
    required List<String> favoriteGames,
  }) {
    return users.doc(myUid).update({
      'bio': bio,
      'photoUrl': photoUrl,
      'favoriteGames': favoriteGames,
    });
  }

  // ---------- Reportes ----------

  static Future<void> report({
    required String type, // post | comment | user
    required String targetId,
    required String ownerId,
    required String reason,
    String? postId,
    String preview = '',
  }) {
    return reports.add({
      'type': type,
      'targetId': targetId,
      'postId': postId ?? '',
      'ownerId': ownerId,
      'reason': reason,
      'reporterId': myUid,
      'reporterName': Session.i.username,
      'preview': preview.length > 140 ? preview.substring(0, 140) : preview,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ---------- Solo administrador ----------

  static Future<void> setBanned(String userId, bool banned) {
    return users.doc(userId).update({'banned': banned});
  }

  /// Borra las publicaciones del usuario, libera su nombre de usuario y
  /// deja la cuenta bloqueada y marcada como eliminada.
  static Future<void> adminDeleteUser(
    String userId,
    String usernameLower,
  ) async {
    final mine = await posts.where('authorId', isEqualTo: userId).get();
    final docs = mine.docs;
    for (var i = 0; i < docs.length; i += 400) {
      final b = fs.batch();
      for (final d in docs.skip(i).take(400)) {
        b.delete(d.reference);
      }
      await b.commit();
    }
    final b = fs.batch();
    b.update(users.doc(userId), {
      'banned': true,
      'deleted': true,
      'username': '[eliminado]',
      'usernameLower': '[eliminado]',
      'bio': '',
      'photoUrl': '',
    });
    if (usernameLower.isNotEmpty && usernameLower != '[eliminado]') {
      b.delete(usernames.doc(usernameLower));
    }
    await b.commit();
  }

  static Future<void> adminDeletePost(String postId) {
    return posts.doc(postId).delete();
  }

  static Future<void> dismissReport(String reportId) {
    return reports.doc(reportId).delete();
  }
}

/// Datos de la sesión actual (bloqueados, seguidos, si es admin).
class Session {
  Session._();
  static final Session i = Session._();

  final ValueNotifier<Set<String>> blocked = ValueNotifier<Set<String>>({});
  final ValueNotifier<Set<String>> following = ValueNotifier<Set<String>>({});
  final ValueNotifier<bool> isAdmin = ValueNotifier<bool>(false);
  String username = '';

  final List<StreamSubscription<dynamic>> _subs = [];

  void start(String uid) {
    stop();
    final me = Db.users.doc(uid);
    _subs.add(me.snapshots().listen(
          (s) => username = (s.data()?['username'] as String?) ?? username,
          onError: (_) {},
        ));
    _subs.add(me.collection('blocked').snapshots().listen(
          (s) => blocked.value = s.docs.map((d) => d.id).toSet(),
          onError: (_) {},
        ));
    _subs.add(me.collection('following').snapshots().listen(
          (s) => following.value = s.docs.map((d) => d.id).toSet(),
          onError: (_) {},
        ));
    _subs.add(fs.collection('admins').doc(uid).snapshots().listen(
          (s) => isAdmin.value = s.exists,
          onError: (_) => isAdmin.value = false,
        ));
  }

  void stop() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    blocked.value = {};
    following.value = {};
    isAdmin.value = false;
  }
}

class MediaException implements Exception {
  final String message;
  const MediaException(this.message);
  @override
  String toString() => message;
}

/// Un archivo elegido de la galería, todavía sin subir.
class PickedMedia {
  final XFile file;
  final bool isVideo;
  PickedMedia(this.file, this.isVideo);

  String get path => file.path;

  /// Bytes del archivo (sirve en Android, iPhone y web). Se leen una sola vez.
  late final Future<Uint8List> bytes = file.readAsBytes();
}

/// Elegir fotos y videos de la galería del teléfono y subirlos a Cloudinary.
/// El selector del sistema se abre solo y no pide permisos peligrosos: la app
/// únicamente recibe el archivo que la persona elige.
class Media {
  Media._();
  static final ImagePicker _picker = ImagePicker();

  static const int _maxVideoBytes = 90 * 1024 * 1024;

  static Future<PickedMedia?> pickImage({double maxWidth = 1600}) async {
    final f = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: maxWidth,
      imageQuality: 80,
    );
    return f == null ? null : PickedMedia(f, false);
  }

  static Future<PickedMedia?> pickVideo() async {
    final f = await _picker.pickVideo(source: ImageSource.gallery);
    if (f == null) return null;
    final size = await f.length();
    if (size > _maxVideoBytes) {
      throw const MediaException(
        'El video pesa más de 90 MB. Elige uno más corto.',
      );
    }
    return PickedMedia(f, true);
  }

  /// Sube el archivo y devuelve su dirección https.
  static Future<String> upload(PickedMedia m) async {
    if (!MediaConfig.ready) {
      throw const MediaException(
        'Falta configurar Cloudinary en firebase_options.dart',
      );
    }
    final type = m.isVideo ? 'video' : 'image';
    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/${MediaConfig.cloudName}/$type/upload',
    );
    final req = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = MediaConfig.uploadPreset
      ..files.add(
        http.MultipartFile(
          'file',
          m.file.openRead(),
          await m.file.length(),
          filename: m.file.name,
        ),
      );

    final streamed = await req.send().timeout(const Duration(minutes: 6));
    final res = await http.Response.fromStream(streamed);

    Map<String, dynamic> body = {};
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}

    if (res.statusCode != 200) {
      final err = body['error'];
      final msg = err is Map ? err['message'] : null;
      throw MediaException(
        'No se pudo subir el archivo: ${msg ?? 'código ${res.statusCode}'}',
      );
    }
    final url = body['secure_url'];
    if (url is! String || url.isEmpty) {
      throw const MediaException('Respuesta inesperada al subir el archivo.');
    }
    return url;
  }
}
