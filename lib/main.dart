import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ১. নেভিগেটর কি সেট করা
  ZegoUIKitPrebuiltCallInvitationService().setNavigatorKey(navigatorKey);

  // ২. সিগন্যালিং প্লাগইন ব্যবহার করা (অফলাইন কলিংয়ের জন্য এটি ম্যান্ডেটরি)
  ZegoUIKitPrebuiltCallInvitationService().useSystemCallingUI(
    [ZegoUIKitSignalingPlugin()],
  );

  // ৩. ইনিশিয়ালাইজেশন লজিক
  final user = FirebaseAuth.instance.currentUser;

  if (user != null) {
    await ZegoUIKitPrebuiltCallInvitationService().init(
      appID: 1665946902,
      appSign: 'ed865a1284c3a60230c5c35351b306d41232f389d97fc0ec7f4a055bf8953e32',
      userID: user.uid,
      userName: user.email ?? user.uid,
      plugins: [ZegoUIKitSignalingPlugin()],
      
      // অফলাইন পুশ নোটিফিকেশনের কনফিগারেশন
      notificationConfig: ZegoCallInvitationNotificationConfig(
        androidNotificationConfig: ZegoCallAndroidNotificationConfig(
          channelID: "Call_Channel",
          channelName: "Call Channel",
          sound: "call", // raw ফোল্ডারে তোমার রিংটোন ফাইলটি থাকতে হবে
          icon: "drawable/ic_launcher", // অ্যাপ আইকন
        ),
      ),

      requireConfig: (ZegoCallInvitationData data) {
        var config = data.type == ZegoCallType.videoCall
            ? ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall()
            : ZegoUIKitPrebuiltCallConfig.oneOnOneVoiceCall();
        
        config.useSpeakerWhenJoining = true;
        return config;
      },
    );
  }

  runApp(const CircleTalkApp());
}

class CircleTalkApp extends StatelessWidget {
  const CircleTalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Circle Talk',
      theme: ThemeData(
        primarySwatch: Colors.green,
      ),
      home: FirebaseAuth.instance.currentUser == null
          ? const LoginScreen()
          : const HomeScreen(),
    );
  }
}