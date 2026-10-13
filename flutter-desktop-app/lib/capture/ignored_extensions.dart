/*
 * Project : Firefox Network Log Recorder
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

/// Extensions that are skipped, grouped by the checkbox that controls them.
///
/// Matching rules:
///  - Only the URL path is inspected (query, fragment and `;jsessionid=...`
///    path parameters are dropped); the last path segment is used, compared
///    case-insensitively.
///  - The last extension after the final dot wins (`app.min.js` -> `js`,
///    `app.js.map` -> `map`).
///  - The recorded resource type and the response `Content-Type` always win
///    over the extension: an XHR/fetch or a JSON/XML/HTML response is never
///    skipped just because its URL ends in a skipped extension.
/// Special case: `.ts` is skipped only when the content type is `video/mp2t`.
const Set<String> skippedImageExtensions = {
  'png', 'jpg', 'jpeg', 'jpe', 'jfif', 'pjpeg', 'pjp', 'gif', 'webp', 'avif',
  'apng', 'bmp', 'ico', 'cur', 'tif', 'tiff', 'heic', 'heif', 'jxl', 'svg',
  'svgz', 'psd', 'raw', 'cr2', 'nef', 'dng',
};

const Set<String> skippedScriptExtensions = {
  'js', 'mjs', 'cjs', 'jsx', 'map', 'wasm',
};

const Set<String> skippedFontExtensions = {
  'woff', 'woff2', 'ttf', 'otf', 'eot', 'ttc', 'fon', 'fnt',
};

const Set<String> skippedVideoExtensions = {
  'mp4', 'm4v', 'webm', 'mkv', 'mov', 'avi', 'wmv', 'flv', 'f4v', '3gp',
  '3g2', 'ogv', 'mpg', 'mpeg', 'm3u8', 'mpd', 'm4s',
  // 'ts' only together with the content type video/mp2t (handled in code).
};

const Set<String> skippedAudioExtensions = {
  'mp3', 'm4a', 'aac', 'ogg', 'oga', 'opus', 'wav', 'flac', 'weba', 'wma',
  'mid', 'midi', 'aif', 'aiff',
};

/// Optional group, off by default.
const Set<String> skippedDownloadExtensions = {
  'pdf', 'zip', 'gz', 'tgz', 'bz2', 'xz', 'rar', '7z', 'tar', 'exe', 'msi',
  'dmg', 'pkg', 'deb', 'rpm', 'apk', 'iso', 'bin', 'swf',
};

/// Returns the lower-case last extension of the URL path, or null.
String? urlExtension(String url) {
  final uri = Uri.tryParse(url);
  var path = uri?.path ?? url.split('?').first.split('#').first;
  final semi = path.indexOf(';');
  if (semi != -1) path = path.substring(0, semi); // ;jsessionid=...
  final segment = path.split('/').last;
  final dot = segment.lastIndexOf('.');
  if (dot <= 0 || dot == segment.length - 1) return null;
  return segment.substring(dot + 1).toLowerCase();
}
