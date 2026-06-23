importScripts("https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyDnOhyoSRkGrDslhubtOp3RqQ437W2XMvA",
  authDomain: "docu-tracker-ac4ea.firebaseapp.com",
  projectId: "docu-tracker-ac4ea",
  storageBucket: "docu-tracker-ac4ea.firebasestorage.app",
  messagingSenderId: "269775325253",
  appId: "1:269775325253:web:17eab4c40d7eae6ddd7b2c"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Background message:', payload);
  const title = payload.notification?.title || 'FileTrack Hub';
  const options = {
    body: payload.notification?.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
  };
  self.registration.showNotification(title, options);
});
