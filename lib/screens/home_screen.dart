import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart'; 

import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';

import 'login_screen.dart';
import 'chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  
  bool selectionMode = false;
  Set<String> selectedContacts = {};

  // সার্চ ফিচারের জন্য ভ্যারিয়েবলসমূহ
  bool isSearching = false;
  String searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  static const Color appGreen = Colors.green;

  void initZegoCloud() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      ZegoUIKitPrebuiltCallInvitationService().init(
        appID: 1665946902, 
        appSign: 'ed865a1284c3a60230c5c35351b306d41232f389d97fc0ec7f4a055bf8953e32', 
        userID: currentUser.uid,
        userName: currentUser.email ?? "User",
        plugins: [ZegoUIKitSignalingPlugin()],
        
        notificationConfig: ZegoCallInvitationNotificationConfig(
          androidNotificationConfig: ZegoCallAndroidNotificationConfig(
            channelID: "Call_Channel",
            channelName: "Call Channel",
          ),
        ),

        requireConfig: (ZegoCallInvitationData data) {
          if (data.type == ZegoCallType.videoCall) {
            return ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall();
          } else {
            var config = ZegoUIKitPrebuiltCallConfig.oneOnOneVoiceCall();
            config.useSpeakerWhenJoining = true; 
            return config;
          }
        },
      );
    }
  }

  Future<void> setOnline(bool online) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'online': online,
      'lastSeen': FieldValue.serverTimestamp(),
    });
  }

  Future<void> pickAndUploadImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );

      if (pickedFile == null) return;
      final file = File(pickedFile.path);
      
      final user = FirebaseAuth.instance.currentUser!;
      final ref = FirebaseStorage.instance.ref().child(
        'profile_pictures/${user.uid}.jpg',
      );

      await ref.putFile(file);
      final url = await ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {'photoUrl': url},
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profile photo updated")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("$e")));
    }
  }

  Future<void> showSaveNameDialog(Map<String, dynamic> user) async {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Save Contact As"),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(
              hintText: "Enter name (e.g. Totan)",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final savedName = nameController.text.trim().isEmpty 
                    ? user['email'] 
                    : nameController.text.trim();

                Navigator.pop(context);

                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(FirebaseAuth.instance.currentUser!.uid)
                    .collection('contacts')
                    .doc(user['uid'])
                    .set({
                  'uid': user['uid'],
                  'email': user['email'],
                  'savedName': savedName,
                  'photoUrl': user['photoUrl'],
                  'addedAt': FieldValue.serverTimestamp(),
                  'lastMessageTime': FieldValue.serverTimestamp(), // ইনিশিয়াল পজিশনের জন্য যুক্ত করা হলো
                });

                if (!mounted) return;
                
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      receiverId: user['uid'],
                      receiverEmail: savedName, 
                    ),
                  ),
                );
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  Future<void> showAddUserDialog(BuildContext context) async {
    final emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Find User"),
          content: TextField(
            controller: emailController,
            decoration: const InputDecoration(hintText: "Enter email"),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final email = emailController.text.trim();
                final result = await FirebaseFirestore.instance
                    .collection('users')
                    .where('email', isEqualTo: email)
                    .get();

                if (!mounted) return;
                
                Navigator.pop(context);

                if (result.docs.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("User not found")),
                  );
                  return;
                }

                final user = result.docs.first.data();
                if (user['uid'] == FirebaseAuth.instance.currentUser!.uid) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("You cannot add yourself")),
                  );
                  return;
                }

                showSaveNameDialog(user);
              },
              child: const Text("Search"),
            ),
          ],
        );
      },
    );
  }

  Future<void> deleteSelectedContacts() async {
    final currentUser = FirebaseAuth.instance.currentUser!;
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Delete Contacts"),
          content: Text("Are you sure you want to delete ${selectedContacts.length} selected contact(s)?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                Navigator.pop(context);
                for (String uid in selectedContacts) {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(currentUser.uid)
                      .collection('contacts')
                      .doc(uid)
                      .delete();
                }
                setState(() {
                  selectionMode = false;
                  selectedContacts.clear();
                });
              },
              child: const Text("Delete", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<void> editSelectedContact() async {
    if (selectedContacts.isEmpty) return;
    
    final currentUser = FirebaseAuth.instance.currentUser!;
    final uid = selectedContacts.first; 

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .collection('contacts')
        .doc(uid)
        .get();

    if (!doc.exists) return;
    
    final data = doc.data() as Map<String, dynamic>;
    final currentName = data['savedName'] ?? data['email'];
    
    final nameController = TextEditingController(text: currentName);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Edit Contact Name"),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(
              hintText: "Enter a new name",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final newName = nameController.text.trim().isEmpty 
                    ? data['email'] 
                    : nameController.text.trim();

                Navigator.pop(context); 

                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(currentUser.uid)
                    .collection('contacts')
                    .doc(uid)
                    .update({
                  'savedName': newName,
                });

                setState(() {
                  selectionMode = false;
                  selectedContacts.clear();
                });
              },
              child: const Text("Update"),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    setOnline(true);
    initZegoCloud(); 
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    setOnline(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setOnline(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      setOnline(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.white, 
      appBar: selectionMode 
        ? AppBar(
            backgroundColor: appGreen, 
            elevation: 1,
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () {
                setState(() {
                  selectionMode = false;
                  selectedContacts.clear();
                });
              },
            ),
            title: Text("${selectedContacts.length} selected", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
            actions: selectedContacts.length == 1
                ? [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.white),
                      onPressed: editSelectedContact,
                      tooltip: "Edit Name",
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.white),
                      onPressed: deleteSelectedContacts,
                      tooltip: "Delete Contact",
                    ),
                  ]
                : [
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.white),
                      onPressed: deleteSelectedContacts,
                      tooltip: "Delete Contact",
                    ),
                  ],
          )
        : AppBar(
            backgroundColor: appGreen, 
            elevation: 1,
            title: isSearching
                ? TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                    cursorColor: Colors.white,
                    decoration: const InputDecoration(
                      hintText: "Search chat name...",
                      hintStyle: TextStyle(color: Colors.white60),
                      border: InputBorder.none,
                    ),
                    onChanged: (value) {
                      setState(() {
                        searchQuery = value.trim().toLowerCase();
                      });
                    },
                  )
                : const Text("Circle Talk", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22)),
            actions: [
              IconButton(
                icon: Icon(isSearching ? Icons.close : Icons.search, color: Colors.white),
                onPressed: () {
                  setState(() {
                    if (isSearching) {
                      isSearching = false;
                      searchQuery = "";
                      _searchController.clear();
                    } else {
                      isSearching = true;
                    }
                  });
                },
              ),
              if (!isSearching) ...[
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  onSelected: (value) async {
                    if (value == 'logout') {
                      await setOnline(false);
                      await ZegoUIKitPrebuiltCallInvitationService().uninit();
                      await FirebaseAuth.instance.signOut();

                      if (context.mounted) {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                          (route) => false,
                        );
                      }
                    }
                  },
                  itemBuilder: (BuildContext context) {
                    return [
                      const PopupMenuItem<String>(
                        value: 'logout',
                        child: Text('Log out'),
                      ),
                    ];
                  },
                ),
              ]
            ],
          ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser!.uid)
            .collection('contacts')
            .orderBy('lastMessageTime', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: appGreen));
          }

          final allContacts = snapshot.data!.docs;
          final contacts = allContacts.where((doc) {
            final user = doc.data() as Map<String, dynamic>;
            final displayName = (user['savedName'] ?? user['email'] ?? 'Unknown').toString().toLowerCase();
            return displayName.contains(searchQuery);
          }).toList();

          if (contacts.isEmpty) {
            return Center(
              child: Text(
                isSearching ? "No matching contacts found" : "No contacts yet.\nTap + to add someone.",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 16),
              ),
            );
          }

          return ListView.builder(
            itemCount: contacts.length,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemBuilder: (context, index) {
              final user = contacts[index].data() as Map<String, dynamic>;
              
              final displayName = user['savedName'] ?? user['email'] ?? 'Unknown';
              final chatId = ([currentUser.uid, user['uid']]..sort()).join("_");
              final isSelected = selectedContacts.contains(user['uid']);

              return Container(
                color: isSelected ? Colors.grey.withOpacity(0.15) : Colors.transparent,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  leading: Stack(
                    children: [
                      CircleAvatar(
                        radius: 26, 
                        backgroundColor: Colors.grey.shade300,
                        backgroundImage: user['photoUrl'] != null
                            ? NetworkImage(user['photoUrl'])
                            : null,
                        child: user['photoUrl'] == null
                            ? Text(
                                displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white),
                              )
                            : null,
                      ),
                      if (isSelected)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: CircleAvatar(
                            radius: 10,
                            backgroundColor: appGreen,
                            child: const Icon(Icons.check, size: 14, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                  title: Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  
                  // --- সাবটাইটেল সেকশনে ফটো/ফাইল হ্যান্ডলিং ফিক্স করা হলো ---
                  subtitle: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('chats')
                        .doc(chatId)
                        .collection('messages')
                        .orderBy('timestamp', descending: true)
                        .limit(30)
                        .snapshots(),
                    builder: (context, chatSnapshot) {
                      if (!chatSnapshot.hasData ||
                          chatSnapshot.data!.docs.isEmpty) {
                        return const Text("No messages yet", style: TextStyle(fontSize: 14));
                      }

                      String lastMessageText = "No messages yet";
                      bool isMyLastMessage = false;
                      bool lastMessageSeen = false;
                      bool lastMessageDelivered = false;

                      for (var doc in chatSnapshot.data!.docs) {
                        final messageData = doc.data() as Map<String, dynamic>;
                        
                        final deletedFor = List<String>.from(
                          messageData['deletedFor'] ?? [],
                        );

                        if (!deletedFor.contains(currentUser.uid)) {
                          // --- এখানে নতুন কন্ডিশন যোগ করা হলো মিডিয়া ফাইল চেনার জন্য ---
                          if (messageData['deleted'] == true) {
                            lastMessageText = "This message was deleted";
                          } else if (messageData['type'] == 'image') {
                            lastMessageText = "📷 Photo";
                          } else if (messageData['type'] == 'file') {
                            lastMessageText = "📄 ${messageData['fileName'] ?? 'Document'}";
                          } else {
                            lastMessageText = messageData['text'] ?? '';
                          }
                          
                          isMyLastMessage = messageData['senderId'] == currentUser.uid;
                          lastMessageSeen = messageData['seen'] ?? false;
                          lastMessageDelivered = messageData['delivered'] ?? false;
                          break;
                        }
                      }

                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isMyLastMessage && lastMessageText != "No messages yet") ...[
                            Icon(
                              lastMessageSeen
                                  ? Icons.done_all
                                  : lastMessageDelivered
                                      ? Icons.done_all
                                      : Icons.done,
                              size: 16,
                              color: lastMessageSeen ? Colors.blue : Colors.grey,
                            ),
                            const SizedBox(width: 4), 
                          ],
                          Expanded(
                            child: Text(
                              lastMessageText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontStyle: lastMessageText == "This message was deleted"
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                                color: lastMessageText == "This message was deleted"
                                    ? Colors.grey
                                    : Colors.black54,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  trailing: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('chats')
                        .doc(chatId)
                        .collection('messages')
                        .orderBy('timestamp', descending: true)
                        .snapshots(),
                    builder: (context, msgSnapshot) {
                      if (!msgSnapshot.hasData || msgSnapshot.data!.docs.isEmpty) {
                        return const SizedBox();
                      }

                      final allMessages = msgSnapshot.data!.docs;
                      
                      final unreadDocs = allMessages.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        return data['senderId'] == user['uid'] && data['seen'] == false;
                      }).toList();

                      final unread = unreadDocs.length;

                      String timeText = "";
                      final lastMsgData = allMessages.first.data() as Map<String, dynamic>;
                      final Timestamp? timestamp = lastMsgData['timestamp'] as Timestamp?;
                      if (timestamp != null) {
                        timeText = DateFormat('hh:mm a').format(timestamp.toDate());
                      }

                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            timeText,
                            style: TextStyle(
                              fontSize: 12,
                              color: unread > 0 ? appGreen : Colors.grey,
                              fontWeight: unread > 0 ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          const SizedBox(height: 6),
                          unread > 0
                              ? CircleAvatar(
                                  radius: 10,
                                  backgroundColor: appGreen,
                                  child: Text(
                                    unread.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              : const SizedBox(width: 20, height: 20),
                        ],
                      );
                    },
                  ),
                  onLongPress: () {
                    if (!selectionMode) {
                      setState(() {
                        selectionMode = true;
                        selectedContacts.add(user['uid']);
                      });
                    }
                  },
                  onTap: () {
                    if (selectionMode) {
                      setState(() {
                        if (isSelected) {
                          selectedContacts.remove(user['uid']);
                        } else {
                          selectedContacts.add(user['uid']);
                        }
                        if (selectedContacts.isEmpty) {
                          selectionMode = false;
                        }
                      });
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            receiverId: user['uid'],
                            receiverEmail: displayName,
                          ),
                        ),
                      );
                    }
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: selectionMode 
          ? null 
          : FloatingActionButton(
              onPressed: () {
                showAddUserDialog(context);
              },
              backgroundColor: appGreen,
              child: const Icon(Icons.person_add, color: Colors.white),
            ),
    );
  }
}