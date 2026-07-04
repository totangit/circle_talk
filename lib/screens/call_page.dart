import 'package:flutter/material.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';

class CallPage extends StatelessWidget {
  final String callID;
  final String userID;
  final String userName;
  final bool isVideo;

  const CallPage({
    super.key,
    required this.callID,
    required this.userID,
    required this.userName,
    required this.isVideo,
  });

  @override
  Widget build(BuildContext context) {
    return ZegoUIKitPrebuiltCall(
      appID: 1665946902,
      appSign:
          'ed865a1284c3a60230c5c35351b306d41232f389d97fc0ec7f4a055bf8953e32',
      userID: userID,
      userName: userName,
      callID: callID,
      config: isVideo
          ? ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall()
          : ZegoUIKitPrebuiltCallConfig.oneOnOneVoiceCall(),
    );
  }
}