import 'package:flutter/material.dart' hide Text;
import '../l10n.dart';

import '../net.dart';
import '../safety.dart';
import '../services/db.dart';
import '../util.dart';
import '../widgets/user_avatar.dart';
import 'search_screen.dart';

/// Pestaña "Chats": tus conversaciones privadas.
class ChatsTab extends StatefulWidget {
  const ChatsTab({super.key});

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  late final Stream<Snap> _stream = Db.watchChats();

  Future<void> _newChat() async {
    final r = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(builder: (_) => const SearchScreen(pick: true)),
    );
    if (r == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(otherUid: r[0], otherName: r[1]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newChat,
        icon: const Icon(Icons.edit),
        label: const Text('Nuevo chat'),
      ),
      body: StreamBuilder<Snap>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ValueListenableBuilder<Set<String>>(
            valueListenable: Session.i.blocked,
            builder: (context, blocked, _) {
              final docs = snap.data!.docs.where((d) {
                final other = _other(d.data());
                return other.isNotEmpty && !blocked.contains(other);
              }).toList()
                ..sort((a, b) {
                  final x = a.data()['lastAt'];
                  final y = b.data()['lastAt'];
                  final tx = x is DateTime ? x.millisecondsSinceEpoch : 0;
                  final ty = y is DateTime ? y.millisecondsSinceEpoch : 0;
                  return ty.compareTo(tx);
                });
              if (docs.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Aún no tienes conversaciones.\nToca "Nuevo chat" para hablar en privado con alguien.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 90),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final c = docs[i].data();
                  final other = _other(c);
                  final names = (c['names'] ?? {}) as Map;
                  final name = (names[other] ?? 'usuario').toString();
                  final last = (c['lastMessage'] ?? '').toString();
                  return ListTile(
                    leading: UserAvatar(uid: other),
                    title: Text('@$name'),
                    subtitle: Text(
                      last.isEmpty ? 'Sin mensajes' : last,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      formatDate(c['lastAt']),
                      style: const TextStyle(fontSize: 11, color: Colors.white54),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ChatScreen(otherUid: other, otherName: name),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  String _other(Json c) {
    final m = (c['members'] ?? []) as List;
    for (final x in m) {
      if (x != myUid) return x.toString();
    }
    return '';
  }
}

/// Conversación privada con una persona.
class ChatScreen extends StatefulWidget {
  final String otherUid;
  final String otherName;
  const ChatScreen({super.key, required this.otherUid, required this.otherName});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  bool _sending = false;

  late final Stream<Snap> _stream =
      Db.watchMessages(Db.chatId(myUid, widget.otherUid));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    if (!await requireOnline(context, 'enviar mensajes')) return;
    if (!mounted || !Safety.check(context, [t])) return;
    final w = RateLimit.wait('chat', 2);
    if (w > 0) return;
    setState(() => _sending = true);
    try {
      await Db.sendMessage(widget.otherUid, widget.otherName, t);
      _ctrl.clear();
    } catch (e) {
      if (mounted) toast(context, 'No se pudo enviar: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            UserAvatar(uid: widget.otherUid, radius: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '@${widget.otherName}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<Snap>(
              stream: _stream,
              builder: (context, snap) {
                if (snap.hasError) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Aún no hay mensajes. Escribe el primero.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Center(
                    child: Text('Aún no hay mensajes. Escribe el primero.'),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final m = docs[i].data();
                    final mine = m['senderId'] == myUid;
                    return Align(
                      alignment:
                          mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                        ),
                        decoration: BoxDecoration(
                          color: mine
                              ? Theme.of(context).colorScheme.primary
                              : const Color(0xFF1B2236),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          (m['text'] ?? '').toString(),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          ValueListenableBuilder<Set<String>>(
            valueListenable: Session.i.blocked,
            builder: (context, blocked, _) {
              if (blocked.contains(widget.otherUid)) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Bloqueaste a esta persona.'),
                );
              }
              return SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          maxLength: 500,
                          maxLines: 1,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            hintText: tr('Escribe un mensaje…'),
                            counterText: '',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _sending ? null : _send,
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
