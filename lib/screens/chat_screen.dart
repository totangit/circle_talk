import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async'; // StreamSubscription ব্যবহারের জন্য
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:marquee/marquee.dart';
import 'full_image_screen.dart'; 

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

// 1. Class declaration change with WidgetsBindingObserver
class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
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

  // --- FILE UPLOAD PROGRESS STATE VARIABLES ADDED ---
  bool _isUploading = false;
  double _uploadProgress = 0.0;

  // --- FILE DOWNLOAD PROGRESS STATE VARIABLES ADDED ---
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  // স্ক্রল লাফানো বন্ধ করার জন্য স্টেট লেভেলে স্ট্রিম ডিক্লেয়ার করা হলো
  late Stream<QuerySnapshot> _messagesStream;
  late Stream<DocumentSnapshot> _userStatusStream;

  // ব্যাকগ্রাউন্ড সিন স্ট্যাটাস লকিংয়ের জন্য সাবস্ক্রিপশন ভ্যারিয়েবল
  StreamSubscription<QuerySnapshot>? _seenMessagesSubscription;

  // 3. initState() replaced here
  @override
  void initState() {
    super.initState();

    _retrieveLostData();

    WidgetsBinding.instance
        .addObserver(this);

    _updateUserStatus(true);

    markMessagesAsSeen();

    // initState-এ স্ট্রিমগুলোকে লক করা হলো যেন setState-এ রিস্টার্ট না হয়
    // শেষ মেসেজটি আগে লোড করার জন্য descending: true করা হলো
    _messagesStream = FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();

    _userStatusStream = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.receiverId)
        .snapshots();
  }

  // 5. dispose() add/replace here
  @override
  void dispose() {
    _updateUserStatus(false);

    WidgetsBinding.instance
        .removeObserver(this);

    // চ্যাট স্ক্রিন থেকে বের হওয়ার সাথে সাথে সিন লিসেনার ক্যানসেল করা হলো
    _seenMessagesSubscription?.cancel();

    _controller.dispose();
    _scrollController.dispose();

    super.dispose();
  }

  // 4. didChangeAppLifecycleState added here
  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    if (state ==
        AppLifecycleState.resumed) {
      _updateUserStatus(true);
    } else if (state ==
            AppLifecycleState.paused ||
        state ==
            AppLifecycleState.inactive ||
        state ==
            AppLifecycleState.detached) {
      _updateUserStatus(false);
    }
  }

  Future<void> _retrieveLostData() async {
    final picker = ImagePicker();
    final LostDataResponse response =
        await picker.retrieveLostData();

    if (response.isEmpty) return;

    if (response.files != null &&
        response.files!.isNotEmpty) {
      await _uploadCameraImage(
        response.files!.first,
      );
    }
  }

  // 2. _updateUserStatus function added here
  Future<void> _updateUserStatus(
    bool online,
  ) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .set({
      'isOnline': online,
      'lastSeen':
          FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String get chatId {
    List<String> ids = [
      currentUser.uid,
      widget.receiverId,
    ];

    ids.sort();
    return ids.join("_");
  }

  // Seen Status ফিক্স করার ফাংশন
  void markMessagesAsSeen() {
    _seenMessagesSubscription = FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('senderId', isEqualTo: widget.receiverId)
        .where('seen', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docs) {
        doc.reference.update({
          'seen': true,
          'delivered': true,
        });
      }
    });
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

    String messageText = _controller.text.trim();
    _controller.clear();

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
      'replyMessage': replyMessage,
      'replySender': replySender,
      'replyMessageId': replyMessageId,
    });

    cancelReply();

    // নিজের কন্ট্যাক্ট লিস্টে এই চ্যাটের জন্য lastMessageTime আপডেট (যাতে নিজের স্ক্রিনে চ্যাট ওপরে আসে)
    await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .collection('contacts')
        .doc(widget.receiverId)
        .update({
      'lastMessageTime': FieldValue.serverTimestamp(),
    }).catchError((_) {});

    final receiverContactRef =
        FirebaseFirestore.instance
            .collection('users')
            .doc(widget.receiverId)
            .collection('contacts')
            .doc(currentUser.uid);

    final doc = await receiverContactRef.get();

    if (!doc.exists) {
      final senderDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      String? senderPhoto;

      if (senderDoc.exists) {
        senderPhoto = senderDoc.data()?['photoUrl'];
      }

      await receiverContactRef.set({
        'uid': currentUser.uid,
        'email': currentUser.email ?? 'Unknown',
        'savedName': currentUser.email,
        'photoUrl': senderPhoto,
        'addedAt': FieldValue.serverTimestamp(),
        'lastMessageTime': FieldValue.serverTimestamp(), // এখানে যুক্ত করা হলো
      });
    } else {
      // যদি কন্ট্যাক্ট অলরেডি থাকে, তবে শুধু টাইমস্ট্যাম্প আপডেট হবে (যাতে অপরের স্ক্রিনেও চ্যাট ওপরে যায়)
      await receiverContactRef.update({
        'lastMessageTime': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> sendImage() async {
    final picker = ImagePicker();

    final XFile? image =
        await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );

    if (image == null) return;

    // --- আপলোড স্টেট সেট করা হলো ---
    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    try {
      debugPrint("Upload started");

      final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/ey4f6h1y/image/upload',
      );

      // --- প্রোগ্রেস ট্র্যাকিং করার জন্য কাস্টম ক্লাসে রিপ্লেস করা হলো ---
      var request = TrackingMultipartRequest(
        'POST',
        uri,
        onProgress: (bytes, totalBytes) {
          setState(() {
            _uploadProgress = bytes / totalBytes;
          });
        },
      );

      request.fields['upload_preset'] =
          'circle_talk_upload';

      request.files.add(
        await http.MultipartFile
            .fromPath(
          'file',
          image.path,
        ),
      );

      var response =
          await request.send();

      var responseData =
          await response.stream
              .bytesToString();

      var data =
          jsonDecode(responseData);

      String imageUrl =
          data['secure_url'];

      debugPrint("Cloudinary response: $data");
      debugPrint("Image URL: $imageUrl");

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
        'type': 'image',
        'imageUrl': imageUrl,
        'senderId': currentUser.uid,
        'timestamp':
            FieldValue.serverTimestamp(),
        'delivered': false,
        'seen': false,
      });

      // মিডিয়া ফাইল পাঠানোর পরও টাইমস্ট্যাম্প ওপরে যাওয়ার লজিক
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('contacts')
          .doc(widget.receiverId)
          .update({'lastMessageTime': FieldValue.serverTimestamp()}).catchError((_) {});

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.receiverId)
          .collection('contacts')
          .doc(currentUser.uid)
          .update({'lastMessageTime': FieldValue.serverTimestamp()}).catchError((_) {});

      debugPrint("Saved to Firestore");
    } catch (e) {
      debugPrint("Image Error: $e");
    } finally {
      // --- আপলোড স্টেট রিলিজ করা হলো ---
      setState(() {
        _isUploading = false;
      });
    }
  }

  Future<void> _uploadCameraImage(
    XFile image,
  ) async {
    // --- আপলোড স্টেট সেট করা হলো ---
    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    try {
      final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/ey4f6h1y/image/upload',
      );

      // --- প্রোগ্রেস ট্র্যাকিং করার জন্য কাস্টম ক্লাসে রিপ্লেস করা হলো ---
      var request = TrackingMultipartRequest(
        'POST',
        uri,
        onProgress: (bytes, totalBytes) {
          setState(() {
            _uploadProgress = bytes / totalBytes;
          });
        },
      );

      request.fields['upload_preset'] =
          'circle_talk_upload';

      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          image.path,
        ),
      );

      final response =
          await request.send();

      final responseData =
          await response.stream.bytesToString();

      final data =
          jsonDecode(responseData);

      final imageUrl =
          data['secure_url'];

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
        'type': 'image',
        'imageUrl': imageUrl,
        'senderId': currentUser.uid,
        'timestamp':
            FieldValue.serverTimestamp(),
        'delivered': false,
        'seen': false,
      });

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('contacts')
          .doc(widget.receiverId)
          .update({'lastMessageTime': FieldValue.serverTimestamp()}).catchError((_) {});

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.receiverId)
          .collection('contacts')
          .doc(currentUser.uid)
          .update({'lastMessageTime': FieldValue.serverTimestamp()}).catchError((_) {});

    } catch (e) {
      debugPrint(
        'Camera upload error: $e',
      );
    } finally {
      // --- আপলোড স্টেট রিলিজ করা হলো ---
      setState(() {
        _isUploading = false;
      });
    }
  }

  Future<void> captureAndSendImage() async {
    final picker = ImagePicker();

    final XFile? image =
        await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 50,
      maxWidth: 1280,
      maxHeight: 1280,
    );

    if (image == null) return;

    await _uploadCameraImage(
      image,
    );
  }

  Future<void> sendDocument() async {
    FilePickerResult? result =
        await FilePicker.platform.pickFiles();

    if (result == null) return;

    File file =
        File(result.files.single.path!);

    String fileName =
        result.files.single.name;

    // --- আপলোড স্টেট সেট করা হলো ---
    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    try {
      debugPrint("Upload started");

      final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/ey4f6h1y/raw/upload',
      );

      debugPrint("UPLOAD URI: $uri");

      // --- প্রোগ্রেস ট্র্যাকিং করার জন্য কাস্টম ক্লাসে রিপ্লেস করা হলো ---
      var request = TrackingMultipartRequest(
        'POST',
        uri,
        onProgress: (bytes, totalBytes) {
          setState(() {
            _uploadProgress = bytes / totalBytes;
          });
        },
      );

      request.fields['upload_preset'] =
          'circle_talk_upload';

      request.files.add(
        await http.MultipartFile
            .fromPath(
          'file',
          file.path,
        ),
      );

      var response =
          await request.send();

      var responseData =
          await response.stream
              .bytesToString();

      var data =
          jsonDecode(responseData);

      String fileUrl =
          data['secure_url'];

      debugPrint("Cloudinary response: $data");
      debugPrint("File Name: $fileName");
      debugPrint("File URL: $fileUrl");

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
        'type': 'file',
        'fileName': fileName,
        'fileUrl': fileUrl,
        'senderId': currentUser.uid,
        'timestamp':
            FieldValue.serverTimestamp(),
        'delivered': false,
        'seen': false,
      });

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('contacts')
          .doc(widget.receiverId)
          .update({'lastMessageTime': FieldValue.serverTimestamp()}).catchError((_) {});

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.receiverId)
          .collection('contacts')
          .doc(currentUser.uid)
          .update({'lastMessageTime': FieldValue.serverTimestamp()}).catchError((_) {});

      debugPrint("Saved file to Firestore");
    } catch (e) {
      debugPrint("Document Error: $e");
    } finally {
      // --- আপলোড স্টেট রিলিজ করা হলো ---
      setState(() {
        _isUploading = false;
      });
    }
  }

  // --- কাস্টম বাইট ট্র্যাকিং সহ ফাইল ডাউনলোড লজিক আপডেট করা হলো ---
  Future<void> openDocument(
    String url,
    String fileName,
  ) async {
    if (_isDownloading) return; // ইতিমধ্যে একটি ডাউনলোড চললে রি-ট্রিগার বন্ধ করবে[cite: 5]

    try {
      final dir = await getTemporaryDirectory(); // টেম্পোরারি ডিরেক্টরি পাথ[cite: 5]
      final file = File('${dir.path}/$fileName'); // লোকাল ফাইল অবজেক্ট[cite: 5]

      // --- ফাইলটি লোকাল স্টোরেজে অলরেডি আছে কি না চেক করা হচ্ছে ---
      if (await file.exists()) {
        debugPrint("File already exists locally. Opening directly: ${file.path}");
        final result = await OpenFilex.open(file.path); // সরাসরি ফাইল ওপেন[cite: 5]
        debugPrint("Open result: ${result.message}"); // ওপেন রেজাল্ট[cite: 5]
        return; // ডাউনলোড প্রসেসে যাবে না
      }

      // ফাইল লোকাল স্টোরেজে না থাকলে ডাউনলোডের প্রসেস শুরু হবে
      setState(() {
        _isDownloading = true;
        _downloadProgress = 0.0;
      });

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url)); // GET রিকোয়েস্ট[cite: 5]
      final response = await client.send(request); // রেসপন্স সেন্ড[cite: 5]

      debugPrint("URL: $url"); // URL প্রিন্ট[cite: 5]
      debugPrint("Status: ${response.statusCode}"); // স্ট্যাটাস কোড[cite: 5]
      debugPrint("Content-Type: ${response.headers['content-type']}"); // কন্টেন্ট টাইপ[cite: 5]

      final totalBytes = response.contentLength ?? 0; // টোটাল সাইজ[cite: 5]
      int receivedBytes = 0;
      List<int> bytesList = [];

      // স্ট্রিম রিড করে বাইট বাই বাইট প্রোগ্রেস ক্যালকুলেট করা[cite: 5]
      await for (var chunk in response.stream) {
        bytesList.addAll(chunk); // চ্যাংক অ্যাড করা[cite: 5]
        receivedBytes += chunk.length; // রিসিভড বাইট ট্র্যাকিং[cite: 5]
        
        if (totalBytes > 0) {
          setState(() {
            _downloadProgress = receivedBytes / totalBytes; // লাইভ প্রোগ্রেস আপডেট[cite: 5]
          });
        }
      }

      await file.writeAsBytes(bytesList, flush: true); // ফাইলে বাইট রাইট করা[cite: 5]

      debugPrint(file.path); // পাথ প্রিন্ট[cite: 5]
      debugPrint("Saved size: ${await file.length()}"); // ফাইল সাইজ প্রিন্ট[cite: 5]

      final result = await OpenFilex.open(file.path); // ডাউনলোড শেষ হলে ফাইল ওপেন[cite: 5]
      debugPrint("Open result: ${result.message}"); // ওপেন রেজাল্ট[cite: 5]
      
      client.close(); // ক্লায়েন্ট ক্লোজ[cite: 5]
    } catch (e) {
      debugPrint('Open/Download file error: $e'); // এরর হ্যান্ডলিং[cite: 5]
    } finally {
      setState(() {
        _isDownloading = false; // ডাউনলোড স্টেট রিলিজ[cite: 5]
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

        bool alreadyDeleted = 
            data['deleted'] == true;

        Timestamp? timestamp =
            data['timestamp']
                as Timestamp?;

        if (alreadyDeleted || !isMyMessage) {
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

            if (message['type'] == 'image')
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (_) =>
                              FullImageScreen(
                        imageUrl:
                            message[
                                'imageUrl'],
                      ),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius:
                      BorderRadius.circular(
                          12),
                  child: Image.network(
                    message['imageUrl'] ?? '',
                    width: 220,
                    height: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(Icons.broken_image, size: 50);
                    },
                  ),
                ),
              )
            else if (message['type'] == 'file')
              GestureDetector(
                onTap: () {
                  openDocument(
                    message['fileUrl'] ?? '',
                    message['fileName'] ?? 'Document',
                  );
                },
                child: Container(
                  padding:
                      const EdgeInsets.all(10),
                  child: Row(
                    mainAxisSize:
                        MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.insert_drive_file,
                        color: Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          message['fileName'] ??
                              'Document',
                          maxLines: 1, // --- ফাইলের নাম সর্বোচ্চ এক লাইনে দেখাবে ---[cite: 5]
                          overflow: TextOverflow.ellipsis, // --- নাম বড় হলে হোয়াটসঅ্যাপের মতো ট্রিম করে ... দেখাবে ---[cite: 5]
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
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
              title: StreamBuilder<DocumentSnapshot>(
                stream: _userStatusStream, 
                builder: (context, snapshot) {
                  String status = "Offline";
                  String photoUrl = "";

                  if (snapshot.hasData &&
                      snapshot.data!.exists) {
                    final data =
                        snapshot.data!.data()
                            as Map<String, dynamic>;

                    photoUrl =
                        data['photoUrl'] ?? "";

                    bool isOnline =
                        data['online'] ??
                            data['isOnline'] ??
                            false;

                    if (isOnline) {
                      status = "Online";
                    } else {
                      Timestamp? lastSeen =
                          data['lastSeen'];

                      if (lastSeen != null) {
                        final lastSeenDate = lastSeen.toDate();
                        final now = DateTime.now();

                        final today = DateTime(
                          now.year,
                          now.month,
                          now.day,
                        );

                        final yesterday = today.subtract(
                          const Duration(days: 1),
                        );

                        final lastDate = DateTime(
                          lastSeenDate.year,
                          lastSeenDate.month,
                          lastSeenDate.day,
                        );

                        if (lastDate == today) {
                          status =
                              "last seen today at ${DateFormat('hh:mm a').format(lastSeenDate)}";
                        } else if (lastDate == yesterday) {
                          status =
                              "last seen yesterday at ${DateFormat('hh:mm a').format(lastSeenDate)}";
                        } else {
                          status =
                              "last seen ${DateFormat('dd MMM yyyy, hh:mm a').format(lastSeenDate)}";
                        }
                      }
                    }
                  }

                  return Transform.translate(
                    offset: const Offset(-25, 0),
                    child: Row(
                      children: [
                        // কন্ট্যাক্টের ফটো না থাকলে প্রথম অক্ষর বড় হাতের দেখানোর লজিক
                        CircleAvatar(
                          radius: 17,
                          backgroundColor: Colors.grey.shade300,
                          backgroundImage: photoUrl.isNotEmpty
                              ? NetworkImage(photoUrl)
                              : null,
                          child: photoUrl.isEmpty
                              ? Text(
                                  widget.receiverEmail.isNotEmpty
                                      ? widget.receiverEmail[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                )
                              : null,
                        ),

                        const SizedBox(width: 8),

                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Column(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.receiverEmail,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight:
                                        FontWeight.w500,
                                  ),
                                  overflow:
                                      TextOverflow.ellipsis,
                                ),
                                AutoScrollStatusText(
                                  text: status,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
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
              stream: _messagesStream, 
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
                  reverse: true, 
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

                    final List<dynamic> deletedFor = message['deletedFor'] ?? [];
                    if (deletedFor.contains(currentUser.uid)) {
                      return const SizedBox.shrink();
                    }

                    return GestureDetector(
                      onLongPress: () {
                        setState(() {
                          selectionMode = true;
                          selectedMessages.add(messages[index].id);
                        });
                      },
                      onTap: () {
                        if (selectionMode) {
                          setState(() {
                            if (selectedMessages.contains(messages[index].id)) {
                              selectedMessages.remove(messages[index].id);
                              if (selectedMessages.isEmpty) {
                                selectionMode = false;
                              }
                            } else {
                              selectedMessages.add(messages[index].id);
                            }
                          });
                        }
                      },
                      child: Container(
                        color: selectedMessages.contains(messages[index].id)
                            ? Colors.green.withOpacity(0.2)
                            : Colors.transparent,
                        child: Dismissible(
                          key: Key(
                            messages[index].id,
                          ),
                          direction: DismissDirection.startToEnd,
                          confirmDismiss:
                              (_) async {
                            startReply(
                              messages[index].id,
                              message['type'] == 'image'
                                  ? '📷 Photo'
                                  : message['type'] == 'file'
                                      ? '📄 ${message['fileName']}'
                                      : message['text'] ?? '',
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
                        ),
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

          // --- UPLOADING PROGRESS INDICATOR WIDGET INTEGRATED ---
          if (_isUploading)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00A884)),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Sending file...",
                          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                        ),
                        const SizedBox(height: 3),
                        LinearProgressIndicator(
                          value: _uploadProgress,
                          backgroundColor: Colors.grey[200],
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00A884)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    "${(_uploadProgress * 100).toStringAsFixed(0)}%",
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                ],
              ),
            ),

          // --- DOWNLOADING PROGRESS INDICATOR WIDGET INTEGRATED ---
          if (_isDownloading)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Downloading file...",
                          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                        ),
                        const SizedBox(height: 3),
                        LinearProgressIndicator(
                          value: _downloadProgress,
                          backgroundColor: Colors.grey[200],
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    "${(_downloadProgress * 100).toStringAsFixed(0)}%",
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                ],
              ),
            ),

          // Message Input Box
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
                          icon: const Icon(
                            Icons.image,
                            color: Colors.green,
                          ),
                          onPressed: (_isUploading || _isDownloading) ? null : sendImage, // প্রসেস চলাকালীন ডিজেবল থাকবে[cite: 5]
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.attach_file,
                            color: Colors.green,
                          ),
                          onPressed: (_isUploading || _isDownloading) ? null : sendDocument, // প্রসেস চলাকালীন ডিজেবল থাকবে[cite: 5]
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.camera_alt,
                            color: Colors.grey[600],
                          ),
                          onPressed: (_isUploading || _isDownloading) ? null : captureAndSendImage, // প্রসেস চলাকালীন ডিজেবল থাকবে[cite: 5]
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
                    backgroundColor: Colors.green, // --- এখানে কালারটি পরিবর্তন করে সবুজ (Colors.green) করা হলো ---
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

// --- CUSTOM TRACKING MULTIPART REQUEST CLASS INTEGRATED ---
class TrackingMultipartRequest extends http.MultipartRequest {
  final Function(int bytes, int totalBytes) onProgress;

  TrackingMultipartRequest(String method, Uri url, {required this.onProgress})
      : super(method, url);

  @override
  http.ByteStream finalize() {
    final byteStream = super.finalize();
    final total = contentLength;
    int bytesUploaded = 0;

    final transformer = StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (data, sink) {
        bytesUploaded += data.length;
        onProgress(bytesUploaded, total);
        sink.add(data);
      },
    );

    return http.ByteStream(byteStream.transform(transformer));
  }
}

class AutoScrollStatusText extends StatefulWidget {
  final String text;

  const AutoScrollStatusText({
    super.key,
    required this.text,
  });

  @override
  State<AutoScrollStatusText> createState() =>
      _AutoScrollStatusTextState();
}

class _AutoScrollStatusTextState
    extends State<AutoScrollStatusText> {
  final ScrollController _controller =
      ScrollController();
  
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance
        .addPostFrameCallback((_) async {
      await Future.delayed(
        const Duration(seconds: 1),
      );

      if (!_controller.hasClients) return;

      final maxScroll =
          _controller.position.maxScrollExtent;

      if (maxScroll > 0) {
        await _controller.animateTo(
          maxScroll,
          duration:
              const Duration(seconds: 3),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 16,
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        physics:
            const NeverScrollableScrollPhysics(),
        child: Text(
          widget.text,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white70,
          ),
        ),
      ),
    );
  }
}