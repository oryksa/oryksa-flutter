import 'dart:typed_data';

/// Public look of the AI employee (the same data the ORYKSA website chat shows).
class OryksaAgent {
  /// Creates an agent description.
  const OryksaAgent({
    required this.name,
    required this.avatar,
    this.business,
    this.greeting = const {},
    this.subtitle = const {},
    this.suggestions = const {},
    this.voiceReplies = false,
    this.conversationId,
    this.voice,
    this.language,
    this.launcherIcon = 'ai',
    this.launcherImage,
    this.launcherLabel,
    this.openMode = 'voice',
  });

  /// Reads the `GET /v1/client/agent` response.
  factory OryksaAgent.fromJson(Map<String, dynamic> j) {
    Map<String, String> str(dynamic v) =>
        v is Map ? v.map((k, x) => MapEntry('$k', '$x')) : const <String, String>{};
    Map<String, List<String>> list(dynamic v) => v is Map
        ? v.map((k, x) => MapEntry('$k', x is List ? x.map((e) => '$e').toList() : <String>[]))
        : const <String, List<String>>{};
    String? text(dynamic v) {
      if (v is! String) return null;
      final s = v.trim();
      return s.isEmpty ? null : s;
    }
    final launcher = j['launcher'] is Map ? j['launcher'] as Map : const {};
    return OryksaAgent(
      name: (j['name'] ?? 'ORYKSA').toString(),
      avatar: (j['avatar'] ?? 'https://oryksa.com/assets/img/avatar_official_oryksa.png').toString(),
      business: j['business']?.toString(),
      greeting: str(j['greeting']),
      subtitle: str(j['subtitle']),
      suggestions: list(j['suggestions']),
      voiceReplies: j['voice_replies'] == true,
      conversationId: j['conversation_id']?.toString(),
      voice: j['voice']?.toString(),
      language: j['language']?.toString(),
      launcherIcon: text(launcher['icon'])?.toLowerCase() == 'logo' ? 'logo' : 'ai',
      launcherImage: text(launcher['image']),
      launcherLabel: text(launcher['label']),
      openMode: text(j['open_mode'])?.toLowerCase() == 'chat' ? 'chat' : 'voice',
    );
  }

  /// Name of the AI employee (from "Your AI" in ORYKSA).
  final String name;

  /// Photo of the AI employee (from "Your AI" in ORYKSA, never the owner's photo).
  final String avatar;

  /// Same as [avatar].
  String get photo => avatar;

  /// The ORYKSA voice chosen for the AI in ORYKSA (the server speaks with it).
  final String? voice;

  /// Main language of the AI (`pt`, `en`, `es`...), from ORYKSA.
  final String? language;

  /// Business name.
  final String? business;

  /// Greeting per language (`en`, `pt`, `br`, `es`).
  final Map<String, String> greeting;

  /// Subtitle per language.
  final Map<String, String> subtitle;

  /// Suggested questions per language.
  final Map<String, List<String>> suggestions;

  /// The plan allows voice replies.
  final bool voiceReplies;

  /// Conversation of this session.
  final String? conversationId;

  /// What the business chose for the tab bar bubble in the ORYKSA panel
  /// (Connectors > Website chat): `ai` (the photo of the AI, the default) or
  /// `logo` (the company logo). Only the bubble changes: the chat that opens
  /// always shows the photo and name of the AI.
  final String launcherIcon;

  /// Image for the tab bar bubble: the photo of the AI when [launcherIcon] is
  /// `ai`, the company logo (a square PNG, maybe with transparency) when it is
  /// `logo`. Null when the server does not send it (older servers).
  final String? launcherImage;

  /// Text under the tab bar bubble: the name of the AI when [launcherIcon] is
  /// `ai`, the business name when it is `logo`. Null when the server does not
  /// send it (older servers).
  final String? launcherLabel;

  /// What the bubble opens by default, chosen by the business in the ORYKSA panel
  /// (Connectors > Website chat > Open in): `voice` (the voice screen, the default) or
  /// `chat` (the text chat). The customer can always switch inside.
  final String openMode;

  /// Picks the text for [lang] with fallbacks (br uses pt, then en).
  static T? pick<T>(Map<String, T> m, String lang) =>
      m[lang] ?? (lang == 'br' ? m['pt'] : null) ?? m['en'] ?? (m.isEmpty ? null : m.values.first);
}

/// One message of the conversation.
class OryksaMessage {
  /// Creates a message.
  const OryksaMessage({required this.role, required this.content});

  /// Reads one entry of `GET /v1/client/messages`.
  factory OryksaMessage.fromJson(Map<String, dynamic> j) =>
      OryksaMessage(role: (j['role'] ?? 'assistant').toString(), content: (j['content'] ?? '').toString());

  /// `user` or `assistant`.
  final String role;

  /// Text of the message.
  final String content;
}

/// Answer of `send`: `replied` with the text, or `pending` while the AI is still writing.
class OryksaReply {
  /// Creates a reply.
  const OryksaReply({required this.status, this.reply, this.conversationId, this.speech, this.whisper = false, this.collecting});

  /// Reads a `chat_reply` object.
  factory OryksaReply.fromJson(Map<String, dynamic> j) => OryksaReply(
        status: (j['status'] ?? 'replied').toString(),
        reply: j['reply']?.toString(),
        conversationId: j['conversation_id']?.toString(),
        speech: j['speech']?.toString(),
        whisper: j['whisper'] == true,
        collecting: (j['collecting'] is String && (j['collecting'] as String).trim().isNotEmpty) ? (j['collecting'] as String).trim() : null,
      );

  /// The AI is asking the customer for a contact detail before answering (`email`, `phone`,
  /// `name` or `details`, as set in Connectors > Website chat). Null otherwise. The voice
  /// screen shows a text box so the customer can type it.
  final String? collecting;

  /// `replied` or `pending`.
  final String status;

  /// Text of the reply when [status] is `replied`.
  final String? reply;

  /// Conversation id.
  final String? conversationId;

  /// With `voice: true`: the short spoken version of [reply] (1-2 sentences, no markdown).
  /// The whole [reply] stays in the chat.
  final String? speech;

  /// The customer whispered: speak [speech] whispered.
  final bool whisper;
}

/// Where the customer is inside your app. Sent with each message so the AI knows
/// the current screen (for example a product page) and answers about it.
class OryksaAppContext {
  /// Creates an app context.
  const OryksaAppContext({this.screen, this.title, this.items = const []});

  /// Screen id, for example `product`, `cart`, `booking`.
  final String? screen;

  /// Title shown on the screen, for example the product name and price.
  final String? title;

  /// What is listed on the screen (product names, services, times). Up to 20.
  final List<String> items;

  /// JSON sent to the API.
  Map<String, dynamic> toJson() => {
        if (screen != null) 'screen': screen,
        if (title != null) 'title': title,
        if (items.isNotEmpty) 'items': items.take(20).toList(),
      };
}


/// A photo the customer picked in your app (for example with the `image_picker` package).
/// The AI looks at it and answers about it, as in the ORYKSA website chat.
class OryksaImage {
  /// Creates a photo from its bytes (JPEG, PNG or WebP, up to about 2 MB).
  const OryksaImage(this.bytes, {this.mime = 'image/jpeg'});

  /// The image bytes.
  final Uint8List bytes;

  /// `image/jpeg`, `image/png` or `image/webp`.
  final String mime;
}

/// A document from the customer (PDF, Word, text or CSV, up to about 8 MB). The AI reads it.
class OryksaFile {
  /// Creates a document from its bytes.
  const OryksaFile(this.bytes, {required this.name, this.mime = 'application/octet-stream'});

  /// The file bytes.
  final Uint8List bytes;

  /// The file name, for example `orcamento.pdf`.
  final String name;

  /// The type, for example `application/pdf`.
  final String mime;
}

/// Title and picture of a link of the business's own site ([OryksaClient.linkPreview]).
class OryksaLinkPreview {
  /// Creates a preview.
  const OryksaLinkPreview({required this.url, this.title = '', this.image = '', this.site = '', this.price = ''});

  /// Reads a `link_preview` object.
  factory OryksaLinkPreview.fromJson(Map<String, dynamic> j) => OryksaLinkPreview(
        url: (j['url'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        image: (j['image'] ?? '').toString(),
        site: (j['site'] ?? '').toString(),
        price: (j['price'] ?? '').toString(),
      );

  /// The link.
  final String url;

  /// Title of the page (empty for other sites).
  final String title;

  /// Picture of the page (empty when it has none).
  final String image;

  /// Name of the site.
  final String site;

  /// Price, when the page says it (shops).
  final String price;
}

/// Audio returned by an ORYKSA endpoint ([OryksaClient.requestAudio]): the bytes and the
/// response headers.
class OryksaAudio {
  /// Creates an audio answer.
  const OryksaAudio(this.bytes, {this.headers = const {}});

  /// The audio bytes (MP3 for the AI's voice).
  final Uint8List bytes;

  /// Response headers, with lower-case names.
  final Map<String, String> headers;

  /// One header by name (any case), or null.
  String? header(String name) => headers[name.toLowerCase()];
}

/// The answer of [OryksaClient.ai]: an AI task of your own app (read a photo, extract data,
/// classify, write), counted as ORYKSA interactions.
class OryksaAiResult {
  /// Creates a result.
  const OryksaAiResult({required this.text, this.json, this.interactionsSpent = 0, this.interactionsRemaining});

  /// Reads an `ai_result` object.
  factory OryksaAiResult.fromJson(Map<String, dynamic> j) {
    final u = j['oryksa'] is Map ? Map<String, dynamic>.from(j['oryksa'] as Map) : const <String, dynamic>{};
    return OryksaAiResult(
      text: (j['text'] ?? '').toString(),
      json: j['json'] is Map ? Map<String, dynamic>.from(j['json'] as Map) : null,
      interactionsSpent: (u['interactions_spent'] as num?)?.toInt() ?? 0,
      interactionsRemaining: (u['interactions_remaining'] as num?)?.toInt(),
    );
  }

  /// The AI's answer as text (with a [schema], the JSON text).
  final String text;

  /// The answer as an object, when you passed a JSON Schema and the answer follows it.
  final Map<String, dynamic>? json;

  /// ORYKSA interactions this answer used (1 per answer).
  final int interactionsSpent;

  /// ORYKSA interactions left in this period, when known.
  final int? interactionsRemaining;
}
