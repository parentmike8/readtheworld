{{flutter_js}}
{{flutter_build_config}}

(async function loadReadTheWorld() {
  const clearFlag = "rtw_service_worker_cleared";
  try {
    if ("serviceWorker" in navigator) {
      const registrations = await navigator.serviceWorker.getRegistrations();
      if (registrations.length > 0) {
        await Promise.all(registrations.map((registration) => registration.unregister()));
        if (navigator.serviceWorker.controller && sessionStorage.getItem(clearFlag) !== "1") {
          sessionStorage.setItem(clearFlag, "1");
          window.location.reload();
          return;
        }
      }
    }
  } catch (error) {
    console.warn("Unable to clear existing service worker.", error);
  }

  try {
    sessionStorage.removeItem(clearFlag);
  } catch (_) {
    // Ignore unavailable storage and continue loading the app.
  }

  _flutter.loader.load();
})();
