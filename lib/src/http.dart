import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'errors.dart';

/// SDK version sent in the `X-ORYKSA-SDK` header.
const String oryksaSdkVersion = '1.1.1';

/// Default API base.
const String oryksaDefaultBase = 'https://api.oryksa.com/v1';

/// Sends one request to the ORYKSA API and decodes the JSON answer.
Future<Map<String, dynamic>> oryksaRequest(
  http.Client client,
  String base,
  String token,
  String method,
  String path, {
  Object? body,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final req = http.Request(method, Uri.parse(base + path))
    ..headers['Authorization'] = 'Bearer $token'
    ..headers['X-ORYKSA-SDK'] = 'flutter/$oryksaSdkVersion'
    ..headers['Accept'] = 'application/json';
  if (body != null) {
    req.headers['Content-Type'] = 'application/json';
    req.body = jsonEncode(body);
  }
  http.Response res;
  try {
    res = await http.Response.fromStream(await client.send(req).timeout(timeout));
  } on TimeoutException {
    throw const OryksaException(0, 'timeout', 'The request took too long.');
  } catch (e) {
    throw OryksaException(0, 'network_error', 'Could not reach ORYKSA: $e');
  }
  Map<String, dynamic> data = const {};
  if (res.body.isNotEmpty) {
    try {
      final d = jsonDecode(utf8.decode(res.bodyBytes));
      if (d is Map<String, dynamic>) data = d;
    } catch (_) {}
  }
  if (res.statusCode >= 400) {
    final e = data['error'] is Map ? Map<String, dynamic>.from(data['error'] as Map) : <String, dynamic>{};
    final code = (e.remove('code') ?? 'http_${res.statusCode}').toString();
    final msg = (e.remove('message') ?? 'Request failed with HTTP ${res.statusCode}').toString();
    throw OryksaException(res.statusCode, code, msg, e);
  }
  return data;
}

/// Throws the ORYKSA error of a failed response.
Never _fail(http.Response res) {
  Map<String, dynamic> data = const {};
  try {
    final d = jsonDecode(utf8.decode(res.bodyBytes));
    if (d is Map<String, dynamic>) data = d;
  } catch (_) {}
  final e = data['error'] is Map ? Map<String, dynamic>.from(data['error'] as Map) : <String, dynamic>{};
  final code = (e.remove('code') ?? 'http_${res.statusCode}').toString();
  final msg = (e.remove('message') ?? 'Request failed with HTTP ${res.statusCode}').toString();
  throw OryksaException(res.statusCode, code, msg, e);
}

Future<http.Response> _run(http.Client client, http.BaseRequest req, Duration timeout) async {
  req.headers['X-ORYKSA-SDK'] = 'flutter/$oryksaSdkVersion';
  try {
    return await http.Response.fromStream(await client.send(req).timeout(timeout));
  } on TimeoutException {
    throw const OryksaException(0, 'timeout', 'The request took too long.');
  } catch (e) {
    throw OryksaException(0, 'network_error', 'Could not reach ORYKSA: $e');
  }
}

/// POSTs JSON and returns the raw bytes of the answer (the agent's voice, audio/mpeg).
Future<Uint8List> oryksaBytes(
  http.Client client,
  String base,
  String token,
  String path,
  Object body, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final req = http.Request('POST', Uri.parse(base + path))
    ..headers['Authorization'] = 'Bearer $token'
    ..headers['Content-Type'] = 'application/json'
    ..body = jsonEncode(body);
  final res = await _run(client, req, timeout);
  if (res.statusCode >= 400) _fail(res);
  return res.bodyBytes;
}

/// POSTs one file as multipart (field `file`) and decodes the JSON answer.
Future<Map<String, dynamic>> oryksaUpload(
  http.Client client,
  String base,
  String token,
  String path,
  Uint8List bytes,
  String filename,
  String contentType, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final parts = contentType.split('/');
  final req = http.MultipartRequest('POST', Uri.parse(base + path))
    ..headers['Authorization'] = 'Bearer $token'
    ..headers['Accept'] = 'application/json'
    ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename,
        contentType: MediaType(parts.first, parts.length > 1 ? parts[1] : 'octet-stream')));
  final res = await _run(client, req, timeout);
  if (res.statusCode >= 400) _fail(res);
  try {
    final d = jsonDecode(utf8.decode(res.bodyBytes));
    if (d is Map<String, dynamic>) return d;
  } catch (_) {}
  return const {};
}
