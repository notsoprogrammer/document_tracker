// Use compat versions for service worker
importScripts("https://www.gstatic.com/firebasejs/9.0.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/9.0.0/firebase-messaging-compat.js");

// Initialize Firebase
firebase.initializeApp({
  apiKey: "AIzaSyDnOhyoSRkGrDslhubtOp3RqQ437W2XMvA",
  authDomain: "docu-tracker-ac4ea.firebaseapp.com",
  projectId: "docu-tracker-ac4ea",
  storageBucket: "docu-tracker-ac4ea.appspot.com",
  messagingSenderId: "269775325253",
  appId: "1:269775325253:web:17eab4c40d7eae6ddd7b2c"
});

// Retrieve messaging instance
const messaging = firebase.messaging();

// Handle background messages
messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);
  const notificationTitle = payload.notification?.title || "Background Message Title";
  const notificationOptions = {
    body: payload.notification?.body || "Background Message body.",
    icon: "/icons/ic_launcher.png"
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});