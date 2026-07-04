import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';

class ChatScreen extends StatefulWidget {
  final String receiverId;
  final String receiverEmail;

  const ChatScreen({
    super.key,
    required this.receiverId,
    required this.receiverEmail,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final currentUser = FirebaseAuth.instance.currentUser!;

  bool selectionMode = false;
  Set<String> selectedMessages = {};

  String get chatId {
    List<String> ids = [currentUser.uid, widget.receiverId];
    ids.sort();
    return ids.join("_");
  }

  // আপডেট করা sendMessage ফাংশন
  Future<void> sendMessage() async {
    if (_controller.text.trim().isEmpty) {
      return;
    }

    String messageText = _controller.text.trim();
    _controller.clear();

    // ১. মেসেজ ডাটাবেসে পাঠানো হচ্ছে
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add({
      'text': messageText,
      'senderId': currentUser.uid,
      'timestamp': FieldValue.serverTimestamp(),
      'delivered': false,
      'seen': false,
    });

    // ২. রিসিভারের কন্ট্যাক্ট লিস্টে অটোমেটিক সেন্ডারকে অ্যাড করা (যদি আগে থেকে না থাকে)
    final receiverContactRef = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.receiverId)
        .collection('contacts')
        .doc(currentUser.uid);

    final doc = await receiverContactRef.get();

    if (!doc.exists) {
      // সেন্ডারের প্রোফাইল ছবি ডাটাবেস থেকে নিয়ে আসা হচ্ছে
      final senderDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
          
      String? senderPhoto;
      if (senderDoc.exists) {
        senderPhoto = senderDoc.data()?['photoUrl'];
      }

      // রিসিভারের কন্ট্যাক্ট লিস্টে সেন্ডারকে অ্যাড করে দেওয়া হলো
      await receiverContactRef.set({
        'uid': currentUser.uid,
        'email': currentUser.email ?? 'Unknown',
        'savedName': currentUser.email, // রিসিভারের কাছে বাই ডিফল্ট ইমেইলটাই নাম হিসেবে দেখাবে
        'photoUrl': senderPhoto,
        'addedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  void scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> showMultiDeleteDialog() async {
    bool canDeleteForEveryone = true;
    List<DocumentSnapshot> docsToDelete = [];

    for (String id in selectedMessages) {
      final doc = await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(id)
          .get();

      docsToDelete.add(doc);

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        bool isMyMessage = data['senderId'] == currentUser.uid;
        Timestamp? timestamp = data['timestamp'] as Timestamp?;

        if (!isMyMessage) {
          canDeleteForEveryone = false;
        } else if (timestamp != null) {
          final diff = DateTime.now().difference(timestamp.toDate());
          if (diff.inMinutes >= 10) {
            canDeleteForEveryone = false;
          }
        } else {
          canDeleteForEveryone = false;
        }
      }
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text("Delete for Me"),
                onTap: () async {
                  Navigator.pop(context);
                  for (var doc in docsToDelete) {
                    await doc.reference.update({
                      'deletedFor': FieldValue.arrayUnion([currentUser.uid]),
                    });
                  }
                  setState(() {
                    selectionMode = false;
                    selectedMessages.clear();
                  });
                },
              ),
              if (canDeleteForEveryone)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text("Delete for Everyone"),
                  onTap: () async {
                    Navigator.pop(context);
                    for (var doc in docsToDelete) {
                      await doc.reference.update({
                        'deleted': true,
                        'text': 'This message was deleted',
                      });
                    }
                    setState(() {
                      selectionMode = false;
                      selectedMessages.clear();
                    });
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget messageBubble(
    String text,
    bool myMessage,
    Timestamp? timestamp,
    bool delivered,
    bool seen,
  ) {
    String time = '';

    if (timestamp != null) {
      time = DateFormat('hh:mm a').format(timestamp.toDate());
    }

    return Align(
      alignment: myMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: myMessage ? const Color(0xFFDCF8C6) : Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              text,
              style: TextStyle(
                fontSize: 16,
                fontStyle: text == "This message was deleted"
                    ? FontStyle.italic
                    : FontStyle.normal,
                color: text == "This message was deleted"
                    ? Colors.grey
                    : Colors.black,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  time,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
                if (myMessage)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      seen
                          ? Icons.done_all
                          : delivered
                              ? Icons.done_all
                              : Icons.done,
                      size: 16,
                      color: seen ? Colors.blue : Colors.grey,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECE5DD),
      appBar: selectionMode
          ? AppBar(
              backgroundColor: Colors.green,
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    selectionMode = false;
                    selectedMessages.clear();
                  });
                },
              ),
              title: Text("${selectedMessages.length} selected"),
              actions: [
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: showMultiDeleteDialog,
                ),
              ],
            )
          : AppBar(
              backgroundColor: Colors.green,
              titleSpacing: 0,
              title: Row(
                children: [
                  CircleAvatar(
                    child: Text(widget.receiverEmail[0].toUpperCase()),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.receiverEmail,
                        style: const TextStyle(fontSize: 18),
                      ),
                      StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(widget.receiverId)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const SizedBox();
                          }

                          final data =
                              snapshot.data!.data() as Map<String, dynamic>?;

                          if (data == null) {
                            return const SizedBox();
                          }

                          final online = data['online'] ?? false;

                          if (online) {
                            return const Text(
                              "online",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            );
                          }

                          final Timestamp? lastSeen = data['lastSeen'];
                          String status = "last seen recently";

                          if (lastSeen != null) {
                            final date = lastSeen.toDate();
                            final now = DateTime.now();

                            if (date.year == now.year &&
                                date.month == now.month &&
                                date.day == now.day) {
                              status =
                                  "last seen today at ${DateFormat('hh:mm a').format(date)}";
                            } else {
                              status =
                                  "last seen on ${DateFormat('dd MMM, hh:mm a').format(date)}";
                            }
                          }

                          return Text(
                            status,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.call),
                  onPressed: () async {
                    try {
                      final result =
                          await ZegoUIKitPrebuiltCallInvitationService().send(
                        invitees: [
                          ZegoCallUser(
                            widget.receiverId,
                            widget.receiverEmail,
                          ),
                        ],
                        isVideoCall: false,
                      );
                      debugPrint("VOICE RESULT: $result");
                    } catch (e) {
                      debugPrint("VOICE ERROR: $e");
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.videocam),
                  onPressed: () async {
                    try {
                      final result =
                          await ZegoUIKitPrebuiltCallInvitationService().send(
                        invitees: [
                          ZegoCallUser(
                            widget.receiverId,
                            widget.receiverEmail,
                          ),
                        ],
                        isVideoCall: true,
                      );
                      debugPrint("VIDEO RESULT: $result");
                    } catch (e) {
                      debugPrint("VIDEO ERROR: $e");
                    }
                  },
                ),
              ],
            ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(chatId)
                  .collection('messages')
                  .orderBy('timestamp')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data!.docs;

                for (var doc in messages) {
                  final data = doc.data() as Map<String, dynamic>;

                  if (data['senderId'] != currentUser.uid &&
                      data['seen'] != true) {
                    doc.reference.update({'seen': true, 'delivered': true});
                  }
                }

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  scrollToBottom();
                });

                if (messages.isEmpty) {
                  return const Center(child: Text("Say hello 👋"));
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(10),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message =
                        messages[index].data() as Map<String, dynamic>;

                    final deletedFor = List<String>.from(
                      message['deletedFor'] ?? [],
                    );

                    if (deletedFor.contains(currentUser.uid)) {
                      return const SizedBox();
                    }

                    final myMessage = message['senderId'] == currentUser.uid;

                    return GestureDetector(
                      onLongPress: () {
                        if (!selectionMode) {
                          setState(() {
                            selectionMode = true;
                            selectedMessages.add(messages[index].id);
                          });
                        }
                      },
                      onTap: () {
                        if (selectionMode) {
                          setState(() {
                            if (selectedMessages
                                .contains(messages[index].id)) {
                              selectedMessages.remove(messages[index].id);
                            } else {
                              selectedMessages.add(messages[index].id);
                            }

                            if (selectedMessages.isEmpty) {
                              selectionMode = false;
                            }
                          });
                        }
                      },
                      child: Container(
                        color: selectedMessages.contains(messages[index].id)
                            ? Colors.green.withOpacity(0.30)
                            : Colors.transparent,
                        child: messageBubble(
                          message['text'] ?? '',
                          myMessage,
                          message['timestamp'] as Timestamp?,
                          message['delivered'] ?? false,
                          message['seen'] ?? false,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.grey.shade200,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: "Type a message",
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Colors.green,
                  child: IconButton(
                    onPressed: sendMessage,
                    icon: const Icon(Icons.send, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}