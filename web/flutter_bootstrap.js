{{flutter_js}}
{{flutter_build_config}}

// The app registers its own service worker (app_service_worker.js, registered
// from index.html), so Flutter's deprecated one is not loaded here. It used to
// be loaded through `serviceWorkerSettings`; leaving that out skips it.
_flutter.loader.load({});
