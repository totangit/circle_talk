import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'call_page.dart';

class IncomingCallScreen extends StatelessWidget {
  final QueryDocumentSnapshot callDoc;

  const IncomingCallScreen({
    super.key,
    required this.callDoc,
  });

  @override
  Widget build(BuildContext context) {
    final data = callDoc.data() as Map<String, dynamic>;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Incoming Call'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${data['callerName'] ?? 'Someone'} is calling...',
              style: const TextStyle(fontSize: 22),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CallPage(
                      callID: data['callId'],
                      userID: data['receiverId'],
                      userName: data['receiverName'],
                      isVideo: data['isVideo'] ?? false,
                    ),
                  ),
                );
              },
              child: const Text('Accept'),
            ),
          ],
        ),
      ),
    );
  }
}