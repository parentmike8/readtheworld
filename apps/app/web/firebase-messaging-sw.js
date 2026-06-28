/* global firebase, importScripts */

// Firebase Hosting serves these reserved URLs from the active project attached
// to app.readtheworld.today, keeping public app config out of source control.
importScripts('/__/firebase/12.15.0/firebase-app-compat.js');
importScripts('/__/firebase/12.15.0/firebase-messaging-compat.js');
importScripts('/__/firebase/init.js');

try {
  firebase.messaging();
} catch (error) {
  console.warn('Read the World messaging service worker skipped setup.', error);
}
