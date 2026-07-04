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
  final TextEditingController _controller =
      TextEditingController();

  final ScrollController _scrollController =
      ScrollController();

  final currentUser =
      FirebaseAuth.instance.currentUser!;

  bool selectionMode = false;
  Set<String> selectedMessages = {};

  // Reply feature
  String? replyMessage;
  String? replySender;
  String? replyMessageId;

  String get chatId {
    List<String> ids = [
      currentUser.uid,
      widget.receiverId,
    ];

    ids.sort();
    return ids.join("_");
  }

  void startReply(
    String messageId,
    String message,
    String sender,
  ) {
    setState(() {
      replyMessageId = messageId;
      replyMessage = message;
      replySender = sender;
    });
  }

  void cancelReply() {
    setState(() {
      replyMessage = null;
      replySender = null;
      replyMessageId = null;
    });
  }

  Future<void> sendMessage() async {
    if (_controller.text.trim().isEmpty) {
      return;
    }

    String messageText =
        _controller.text.trim();

    _controller.clear();

    await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add({
      'text': messageText,
      'senderId': currentUser.uid,
      'timestamp':
          FieldValue.serverTimestamp(),
      'delivered': false,
      'seen': false,
      'replyMessage': replyMessage,
      'replySender': replySender,
      'replyMessageId': replyMessageId,
    });

    cancelReply();

    final receiverContactRef =
        FirebaseFirestore.instance
            .collection('users')
            .doc(widget.receiverId)
            .collection('contacts')
            .doc(currentUser.uid);

    final doc =
        await receiverContactRef.get();

    if (!doc.exists) {
      final senderDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .get();

      String? senderPhoto;

      if (senderDoc.exists) {
        senderPhoto =
            senderDoc.data()?['photoUrl'];
      }

      await receiverContactRef.set({
        'uid': currentUser.uid,
        'email':
            currentUser.email ??
                'Unknown',
        'savedName':
            currentUser.email,
        'photoUrl': senderPhoto,
        'addedAt':
            FieldValue.serverTimestamp(),
      });
    }
  }
  
  void scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration:
            const Duration(milliseconds: 300),
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
      final doc =
          await FirebaseFirestore.instance
              .collection('chats')
              .doc(chatId)
              .collection('messages')
              .doc(id)
              .get();

      docsToDelete.add(doc);

      if (doc.exists) {
        final data =
            doc.data()
                as Map<String, dynamic>;

        bool isMyMessage =
            data['senderId'] ==
                currentUser.uid;

        Timestamp? timestamp =
            data['timestamp']
                as Timestamp?;

        if (!isMyMessage) {
          canDeleteForEveryone =
              false;
        } else if (timestamp != null) {
          final diff = DateTime.now()
              .difference(
            timestamp.toDate(),
          );

          if (diff.inMinutes >= 10) {
            canDeleteForEveryone =
                false;
          }
        } else {
          canDeleteForEveryone =
              false;
        }
      }
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              ListTile(
                leading:
                    const Icon(
                  Icons.delete_outline,
                ),
                title:
                    const Text(
                  "Delete for Me",
                ),
                onTap: () async {
                  Navigator.pop(
                    context,
                  );

                  for (var doc
                      in docsToDelete) {
                    await doc.reference
                        .update({
                      'deletedFor':
                          FieldValue
                              .arrayUnion(
                        [
                          currentUser.uid,
                        ],
                      ),
                    });
                  }

                  setState(() {
                    selectionMode =
                        false;
                    selectedMessages
                        .clear();
                  });
                },
              ),
              if (canDeleteForEveryone)
                ListTile(
                  leading:
                      const Icon(
                    Icons.delete,
                    color:
                        Colors.red,
                  ),
                  title:
                      const Text(
                    "Delete for Everyone",
                  ),
                  onTap:
                      () async {
                    Navigator.pop(
                      context,
                    );

                    for (var doc
                        in docsToDelete) {
                      await doc.reference
                          .update({
                        'deleted':
                            true,
                        'text':
                            'This message was deleted',
                      });
                    }

                    setState(() {
                      selectionMode =
                          false;
                      selectedMessages
                          .clear();
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
    Map<String, dynamic> message,
    bool myMessage,
  ) {
    String time = '';

    final Timestamp? timestamp =
        message['timestamp']
            as Timestamp?;

    if (timestamp != null) {
      time = DateFormat(
        'hh:mm a',
      ).format(
        timestamp.toDate(),
      );
    }

    final bool delivered =
        message['delivered'] ??
            false;

    final bool seen =
        message['seen'] ?? false;

    return Align(
      alignment:
          myMessage
              ? Alignment
                  .centerRight
              : Alignment
                  .centerLeft,
      child: Container(
        margin:
            const EdgeInsets.symmetric(
          vertical: 5,
        ),
        padding:
            const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:
              myMessage
                  ? const Color(
                      0xFFDCF8C6,
                    )
                  : Colors.white,
          borderRadius:
              BorderRadius.circular(
            18,
          ),
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.end,
          mainAxisSize:
              MainAxisSize.min,
          children: [
            if (message['replyMessage'] !=
                null)
              Container(
                margin:
                    const EdgeInsets.only(
                  bottom: 6,
                ),
                padding:
                    const EdgeInsets.all(
                  8,
                ),
                decoration:
                    BoxDecoration(
                  color:
                      Colors.black12,
                  borderRadius:
                      BorderRadius.circular(
                    8,
                  ),
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Text(
                      message['replySender'] ??
                          '',
                      style:
                          const TextStyle(
                        fontWeight:
                            FontWeight
                                .bold,
                      ),
                    ),
                    Text(
                      message['replyMessage'] ??
                          '',
                    ),
                  ],
                ),
              ),

            Text(
              message['text'] ?? '',
              style: TextStyle(
                fontSize: 16,
                fontStyle:
                    message['text'] ==
                            "This message was deleted"
                        ? FontStyle
                            .italic
                        : FontStyle
                            .normal,
                color:
                    message['text'] ==
                            "This message was deleted"
                        ? Colors.grey
                        : Colors.black,
              ),
            ),

            const SizedBox(
              height: 4,
            ),

            Row(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                Text(
                  time,
                  style:
                      const TextStyle(
                    fontSize: 10,
                    color:
                        Colors.grey,
                  ),
                ),
                if (myMessage)
                  Padding(
                    padding:
                        const EdgeInsets.only(
                      left: 4,
                    ),
                    child: Icon(
                      seen
                          ? Icons
                              .done_all
                          : delivered
                              ? Icons
                                  .done_all
                              : Icons.done,
                      size: 16,
                      color:
                          seen
                              ? Colors
                                  .blue
                              : Colors
                                  .grey,
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
              title: Text(
                "${selectedMessages.length} selected",
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: showMultiDeleteDialog,
                ),
              ],
            )
          : AppBar(
              backgroundColor: Colors.green,
              title: Text(widget.receiverEmail),
              actions: [
                IconButton(
                  icon: const Icon(Icons.call),
                  onPressed: () async {
                    await ZegoUIKitPrebuiltCallInvitationService()
                        .send(
                      invitees: [
                        ZegoCallUser(
                          widget.receiverId,
                          widget.receiverEmail,
                        ),
                      ],
                      isVideoCall: false,
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.videocam),
                  onPressed: () async {
                    await ZegoUIKitPrebuiltCallInvitationService()
                        .send(
                      invitees: [
                        ZegoCallUser(
                          widget.receiverId,
                          widget.receiverEmail,
                        ),
                      ],
                      isVideoCall: true,
                    );
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
                  return const Center(
                    child:
                        CircularProgressIndicator(),
                  );
                }

                final messages =
                    snapshot.data!.docs;
                return ListView.builder(
                  controller:
                      _scrollController,
                  itemCount:
                      messages.length,
                  itemBuilder:
                      (context, index) {
                    final message =
                        messages[index]
                                .data()
                            as Map<String,
                                dynamic>;

                    final myMessage =
                        message['senderId'] ==
                            currentUser.uid;

                    return Dismissible(
                      key: Key(
                        messages[index].id,
                      ),
                      direction:
                          DismissDirection
                              .startToEnd,
                      confirmDismiss:
                          (_) async {
                        startReply(
                          messages[index].id,
                          message['text'] ??
                              '',
                          myMessage
                              ? 'You'
                              : widget
                                  .receiverEmail,
                        );

                        return false;
                      },
                      child:
                          messageBubble(
                        message,
                        myMessage,
                      ),
                    );
                  },
                );
              },
            ),
          ),

          if (replyMessage != null)
            Container(
              width: double.infinity,
              color:
                  Colors.grey.shade300,
              padding:
                  const EdgeInsets.all(
                      10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        Text(
                          replySender ??
                              '',
                          style:
                              const TextStyle(
                            fontWeight:
                                FontWeight
                                    .bold,
                          ),
                        ),
                        Text(
                          replyMessage ??
                              '',
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon:
                        const Icon(
                      Icons.close,
                    ),
                    onPressed:
                        cancelReply,
                  ),
                ],
              ),
            ),

          // WhatsApp Style Message Input Box
          Padding(
            padding: const EdgeInsets.only(
              left: 8.0,
              right: 8.0,
              bottom: 12.0,
              top: 4.0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          spreadRadius: 1,
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.sentiment_satisfied_alt_outlined,
                            color: Colors.grey[600],
                          ),
                          onPressed: () {},
                        ),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            decoration: const InputDecoration(
                              hintText: "Message",
                              hintStyle: TextStyle(color: Colors.grey),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 10,
                              ),
                            ),
                            onSubmitted: (_) => sendMessage(),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.attach_file,
                            color: Colors.grey[600],
                          ),
                          onPressed: () {},
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.camera_alt,
                            color: Colors.grey[600],
                          ),
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                GestureDetector(
                  onTap: sendMessage,
                  child: const CircleAvatar(
                    radius: 24,
                    backgroundColor: Color(0xFF00A884), // WhatsApp Green
                    child: Icon(
                      Icons.send,
                      color: Colors.white,
                      size: 22,
                    ),
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