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
  });

  /// Reads the `GET /v1/client/agent` response.
  factory OryksaAgent.fromJson(Map<String, dynamic> j) {
    Map<String, String> str(dynamic v) =>
        v is Map ? v.map((k, x) => MapEntry('$k', '$x')) : const <String, String>{};
    Map<String, List<String>> list(dynamic v) => v is Map
        ? v.map((k, x) => MapEntry('$k', x is List ? x.map((e) => '$e').toList() : <String>[]))
        : const <String, List<String>>{};
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
    );
  }

  /// Name of the AI employee (from "Your AI" in ORYKSA).
  final String name;

  /// Photo of the AI employee (from "Your AI" in ORYKSA, never the owner's photo).
  final String avatar;

  /// Same as [avatar].
  String get photo => avatar;

  /// ElevenLabs voice chosen for the AI in ORYKSA (the server speaks with it).
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
  const OryksaReply({required this.status, this.reply, this.conversationId, this.speech, this.whisper = false});

  /// Reads a `chat_reply` object.
  factory OryksaReply.fromJson(Map<String, dynamic> j) => OryksaReply(
        status: (j['status'] ?? 'replied').toString(),
        reply: j['reply']?.toString(),
        conversationId: j['conversation_id']?.toString(),
        speech: j['speech']?.toString(),
        whisper: j['whisper'] == true,
      );

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
