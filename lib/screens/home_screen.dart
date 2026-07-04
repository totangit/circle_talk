import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

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
              hintText: "Enter a name (e.g. Rahul)",
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
      appBar: selectionMode 
        ? AppBar(
            backgroundColor: Colors.green,
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () {
                setState(() {
                  selectionMode = false;
                  selectedContacts.clear();
                });
              },
            ),
            title: Text("${selectedContacts.length} selected", style: const TextStyle(color: Colors.white)),
            // এখানে লিস্টের লজিকটা একদম ক্লিয়ার করে দেওয়া হলো
            actions: selectedContacts.length == 1
                ? [
                    // ১টা সিলেক্ট থাকলে Edit আইকন দেখাবে
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
                    // একের বেশি সিলেক্ট থাকলে শুধু Delete আইকন দেখাবে
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.white),
                      onPressed: deleteSelectedContacts,
                      tooltip: "Delete Contact",
                    ),
                  ],
          )
        : AppBar(
            title: const Text("Circle Talk", style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.green,
            actions: [
              IconButton(
                icon: const Icon(Icons.photo_camera, color: Colors.white),
                onPressed: pickAndUploadImage,
              ),
              IconButton(
                icon: const Icon(Icons.person_add, color: Colors.white),
                onPressed: () {
                  showAddUserDialog(context);
                },
              ),
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.white),
                onPressed: () async {
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
                },
              ),
            ],
          ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser!.uid)
            .collection('contacts')
            .orderBy('addedAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final contacts = snapshot.data!.docs;

          if (contacts.isEmpty) {
            return const Center(
              child: Text(
                "No contacts yet.\nTap + to add someone.",
                textAlign: TextAlign.center,
              ),
            );
          }

          return ListView.builder(
            itemCount: contacts.length,
            itemBuilder: (context, index) {
              final user = contacts[index].data() as Map<String, dynamic>;
              
              final displayName = user['savedName'] ?? user['email'] ?? 'Unknown';
              final chatId = ([currentUser.uid, user['uid']]..sort()).join("_");
              final isSelected = selectedContacts.contains(user['uid']);

              return Container(
                color: isSelected ? Colors.green.withOpacity(0.3) : Colors.transparent,
                child: ListTile(
                  leading: Stack(
                    children: [
                      CircleAvatar(
                        backgroundImage: user['photoUrl'] != null
                            ? NetworkImage(user['photoUrl'])
                            : null,
                        child: user['photoUrl'] == null
                            ? Text(displayName.isNotEmpty ? displayName[0].toUpperCase() : '?')
                            : null,
                      ),
                      if (isSelected)
                        const Positioned(
                          bottom: 0,
                          right: 0,
                          child: CircleAvatar(
                            radius: 10,
                            backgroundColor: Colors.green,
                            child: Icon(Icons.check, size: 14, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                  title: Text(displayName),
                  
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
                        return const Text("No messages yet");
                      }

                      String lastMessageText = "No messages yet";

                      for (var doc in chatSnapshot.data!.docs) {
                        final messageData = doc.data() as Map<String, dynamic>;
                        
                        final deletedFor = List<String>.from(
                          messageData['deletedFor'] ?? [],
                        );

                        if (!deletedFor.contains(currentUser.uid)) {
                          lastMessageText = messageData['text'] ?? '';
                          break;
                        }
                      }

                      return Text(
                        lastMessageText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontStyle: lastMessageText == "This message was deleted"
                              ? FontStyle.italic
                              : FontStyle.normal,
                          color: lastMessageText == "This message was deleted"
                              ? Colors.grey
                              : Colors.black54,
                        ),
                      );
                    },
                  ),

                  trailing: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('chats')
                        .doc(chatId)
                        .collection('messages')
                        .where('senderId', isEqualTo: user['uid'])
                        .where('seen', isEqualTo: false)
                        .snapshots(),
                    builder: (context, unreadSnapshot) {
                      if (!unreadSnapshot.hasData ||
                          unreadSnapshot.data!.docs.isEmpty) {
                        return const SizedBox();
                      }

                      final unread = unreadSnapshot.data!.docs.length;

                      return CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.green,
                        child: Text(
                          unread.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
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
    );
  }
}