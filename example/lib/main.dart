// Minimal ORYKSA chat in a Flutter app.
//
// Your server creates a session token for the signed-in user with the secret key
// (POST https://api.oryksa.com/v1/sessions) and returns only `client_token`.
// The app never contains the secret key.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:oryksa/oryksa.dart';

/// Your backend endpoint that returns {"token": "oryk_cs_..."} for the signed-in user.
const tokenEndpoint = String.fromEnvironment('ORYKSA_TOKEN_URL', defaultValue: 'https://your-server.example/oryksa-token');

Future<String> fetchSessionToken() async {
  final r = await http.get(Uri.parse(tokenEndpoint));
  return (jsonDecode(r.body) as Map<String, dynamic>)['token'] as String;
}

void main() => runApp(const DemoApp());

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final client = OryksaClient(getToken: fetchSessionToken);
    return MaterialApp(
      title: 'ORYKSA SDK demo',
      home: Scaffold(
        appBar: AppBar(title: const Text('My app')),
        body: const Center(child: Text('Your app content')),
        floatingActionButton: OryksaChatButton(client: client, lang: 'en'),
      ),
    );
  }
}
