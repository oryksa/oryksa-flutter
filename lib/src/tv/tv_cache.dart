// Where the presenter keeps the lines she already said (MP3 files in the temporary folder),
// so a repeated line plays again with no new voice made. It is still charged each time: the presenter asks the
// server for every line, with `cached: true` and its `voice_rev`, and shows it only once the server has counted it.
// The web has no files: nothing is kept there.
export 'tv_cache_stub.dart' if (dart.library.io) 'tv_cache_io.dart';
