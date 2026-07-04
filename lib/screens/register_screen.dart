import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() =>
      _RegisterScreenState();
}

class _RegisterScreenState
    extends State<RegisterScreen> {
  final emailController =
      TextEditingController();

  final passwordController =
      TextEditingController();

  Future<void> register() async {
    try {
      final credential =
          await FirebaseAuth.instance
              .createUserWithEmailAndPassword(
        email:
            emailController.text.trim(),
        password:
            passwordController.text.trim(),
      );

      final user = credential.user!;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'uid': user.uid,
        'email':
            emailController.text.trim(),
        'online': false,
        'createdAt':
            FieldValue.serverTimestamp(),
        'lastSeen':
            FieldValue.serverTimestamp(),
      });

      await user.sendEmailVerification();

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            "Verification email sent. Check your Inbox or Spam folder.",
          ),
        ),
      );

      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      String message =
          "Registration failed";

      if (e.code ==
          'email-already-in-use') {
        message =
            "Email already in use";
      } else if (e.code ==
          'weak-password') {
        message =
            "Password is too weak";
      } else if (e.code ==
          'invalid-email') {
        message =
            "Invalid email";
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text("Create Account"),
        backgroundColor: Colors.green,
      ),
      body: Padding(
        padding:
            const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            TextField(
              controller:
                  emailController,
              keyboardType:
                  TextInputType.emailAddress,
              decoration:
                  const InputDecoration(
                labelText: "Email",
                border:
                    OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),

            TextField(
              controller:
                  passwordController,
              obscureText: true,
              decoration:
                  const InputDecoration(
                labelText: "Password",
                border:
                    OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: register,
                style:
                    ElevatedButton.styleFrom(
                  backgroundColor:
                      Colors.green,
                ),
                child: const Text(
                  "Create Account",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}