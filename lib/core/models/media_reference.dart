// Desktop's MEDIA parser at upstream 0caf219aafdf40522f7bfc3ce8756e4eae463a04.
// An extension anchors unquoted paths containing spaces; quoted targets can
// have any extension. Never interpret a server path as a device-local file.
const _extensions =
    'markdown|png|jpg|jpeg|gif|webp|bmp|tiff|svg|mp4|mov|avi|mkv|webm|3gp|'
    'mp3|m2a|wav|ogg|opus|m4a|flac|pdf|docx|doc|odt|rtf|txt|md|epub|'
    'xlsx|xls|ods|csv|tsv|json|xml|yaml|yml|kmz|kml|geojson|gpx|'
    'pptx|ppt|odp|key|zip|tar|gz|tgz|bz2|xz|7z|rar|apk|ipa|html|htm';
final _anchoredPath =
    r'(?:~/|/|[A-Za-z]:[/\\])\S+?(?:[^\S\n]+\S+?)*?\.(?:' +
    _extensions +
    r''')(?=[\s`"'*_,;:)\]}]|MEDIA:|$)''';
final mediaReferencePattern =
    r'''[`"']?MEDIA:\s*(`[^`\n]+`|"[^"\n]+"|'[^'\n]+'|''' +
    _anchoredPath +
    r'''|\S+)[`"']?''';

String mediaReferenceTarget(String value) {
  var target = value.trim();
  if (target.length > 1 &&
      {'`', '"', "'"}.contains(target[0]) &&
      target[0] == target[target.length - 1]) {
    target = target.substring(1, target.length - 1);
  }
  return target.replaceFirst(RegExp(r'''[`"'*_]{1,3}$'''), '');
}
