// ORYKSA chat + voice in a Flutter app.
//
// Your server creates a session token for the signed-in user with the secret key
// (POST https://api.oryksa.com/v1/sessions) and returns only `client_token`.
// The app never contains the secret key.
//
// Voice: add the microphone permission to your app
//   Android  android/app/src/main/AndroidManifest.xml
//            <uses-permission android:name="android.permission.RECORD_AUDIO"/>
//   iOS      ios/Runner/Info.plist
//            <key>NSMicrophoneUsageDescription</key><string>To talk to our assistant.</string>
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:oryksa/oryksa.dart';

/// Your backend endpoint that returns {"token": "oryk_cs_..."} for the signed-in user.
const tokenEndpoint = String.fromEnvironment('ORYKSA_TOKEN_URL', defaultValue: 'https://your-server.example/oryksa-token');

/// Only for local tests: a session token passed with --dart-define (never the secret key).
const testToken = String.fromEnvironment('ORYKSA_TEST_TOKEN');

Future<String> fetchSessionToken() async {
  if (testToken.isNotEmpty) return testToken;
  final r = await http.get(Uri.parse(tokenEndpoint));
  return (jsonDecode(r.body) as Map<String, dynamic>)['token'] as String;
}

void main() => runApp(const DemoApp());

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(title: 'ORYKSA SDK demo', debugShowCheckedModeBanner: false, home: ProductScreen());
}

/// A product page of your app. The chat knows the customer is looking at it.
class ProductScreen extends StatefulWidget {
  const ProductScreen({super.key});

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  final client = OryksaClient(getToken: fetchSessionToken);
  static const lang = String.fromEnvironment('ORYKSA_LANG', defaultValue: 'en');

  OryksaAppContext appContext() => const OryksaAppContext(
        screen: 'product',
        title: 'Sky Beginner Snowboard, 489.95',
        items: ['Sky Beginner Snowboard', 'Pro Glide Snowboard Wax'],
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('My store')),
        body: ListView(padding: const EdgeInsets.all(20), children: const [
          AspectRatio(aspectRatio: 1.6, child: ColoredBox(color: Color(0xFFEFF3F8), child: Icon(Icons.snowboarding, size: 96))),
          SizedBox(height: 16),
          Text('Sky Beginner Snowboard', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          SizedBox(height: 6),
          Text('489.95', style: TextStyle(fontSize: 18)),
        ]),
        floatingActionButton: OryksaChatButton(client: client, lang: lang, appContext: appContext),
      );
}
