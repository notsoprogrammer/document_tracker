import 'dart:js_interop';

@JS('Notification')
extension type _JSNotification._(JSObject _) implements JSObject {
  external factory _JSNotification(String title, JSObject options);
  external static JSPromise<JSString> requestPermission();
  external static String get permission;
}

Future<void> showBrowserNotification(String title, String body) async {
  String perm = _JSNotification.permission;
  if (perm == 'default') {
    perm = (await _JSNotification.requestPermission().toDart).toDart;
  }
  if (perm == 'granted') {
    _JSNotification(title, {'body': body, 'icon': '/icons/Icon-192.png', 'badge': '/icons/Icon-192.png'}.jsify()! as JSObject);
  }
}
