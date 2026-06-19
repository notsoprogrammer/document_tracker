import 'dart:js_interop';
import 'dart:typed_data';

@JS('Blob')
extension type _JSBlob._(JSObject _) implements JSObject {
  external factory _JSBlob(JSArray<JSAny> parts, JSObject options);
}

extension type _JSAnchor(JSObject _) implements JSObject {
  external set href(String v);
  external set download(String v);
  external void click();
  external void remove();
}

@JS('URL.createObjectURL')
external String _createObjectURL(_JSBlob blob);

@JS('URL.revokeObjectURL')
external void _revokeObjectURL(String url);

@JS('document.createElement')
external JSObject _createElement(String tag);

@JS('document.body.appendChild')
external void _appendChild(JSObject el);

Future<void> triggerPdfDownload(Uint8List bytes, String fileName) async {
  final blob = _JSBlob(
    [bytes.toJS as JSAny].toJS,
    {'type': 'application/pdf'}.jsify()! as JSObject,
  );
  final url = _createObjectURL(blob);
  final anchor = _JSAnchor(_createElement('a'));
  anchor.href = url;
  anchor.download = fileName;
  _appendChild(anchor);
  anchor.click();
  anchor.remove();
  _revokeObjectURL(url);
}
