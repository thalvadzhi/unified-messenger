import Foundation

/// JavaScript injected at document start into every service page.
///
/// It replaces `window.Notification` (and `ServiceWorkerRegistration.prototype.showNotification`)
/// so page notifications are forwarded to the app, reports `document.title` changes, and fakes
/// page visibility so a service that is not on screen behaves like a background browser tab.
///
/// Messages posted to `window.webkit.messageHandlers.um`:
/// - `{type: "title", service, title}`
/// - `{type: "notify", service, id, title, body, tag}`
///
/// Functions the app calls via `evaluateJavaScript`:
/// - `window.__umSetVisible(bool)`
/// - `window.__umNotificationClicked(id)`
enum BridgeScript {
    static let handlerName = "um"

    static func source(for service: ServiceID) -> String {
        #"""
        (function () {
          "use strict";
          if (window.__umInstalled) { return; }
          window.__umInstalled = true;

          var SERVICE = "\#(service.rawValue)";
          var HANDLER = "\#(handlerName)";

          function post(msg) {
            try {
              msg.service = SERVICE;
              window.webkit.messageHandlers[HANDLER].postMessage(msg);
            } catch (e) {}
          }

          function makeEvent(type, target) {
            var ev = null;
            try { if (typeof Event === "function") { ev = new Event(type); } } catch (e) { ev = null; }
            if (!ev) {
              ev = { type: type, target: target, currentTarget: target,
                     preventDefault: function () {}, stopPropagation: function () {} };
            }
            return ev;
          }

          function str(v) { return v === undefined || v === null ? "" : String(v); }

          // ---- Notifications ----
          var nextID = 0;
          var live = {};
          var liveOrder = [];
          var MAX_LIVE = 200;

          function remember(id, n) {
            live[id] = n;
            liveOrder.push(id);
            while (liveOrder.length > MAX_LIVE) { delete live[liveOrder.shift()]; }
          }

          function forget(id) {
            delete live[id];
            var i = liveOrder.indexOf(id);
            if (i >= 0) { liveOrder.splice(i, 1); }
          }

          function fire(n, type) {
            var ev = makeEvent(type, n);
            try { var h = n["on" + type]; if (typeof h === "function") { h.call(n, ev); } } catch (e) {}
            var list = (n.__umListeners[type] || []).slice();
            for (var i = 0; i < list.length; i++) {
              try {
                var l = list[i];
                if (typeof l === "function") { l.call(n, ev); }
                else if (l && typeof l.handleEvent === "function") { l.handleEvent(ev); }
              } catch (e) {}
            }
          }

          function notify(title, options) {
            var o = options || {};
            nextID += 1;
            var id = String(nextID);
            post({ type: "notify", id: id, title: str(title), body: str(o.body), tag: str(o.tag) });
            return id;
          }

          function UMNotification(title, options) {
            if (!(this instanceof UMNotification)) {
              throw new TypeError("Failed to construct 'Notification': Please use the 'new' operator.");
            }
            var o = options || {};
            var self = this;
            Object.defineProperty(this, "__umListeners", { value: {}, enumerable: false });
            this.title = str(title);
            this.body = str(o.body);
            this.tag = str(o.tag);
            this.icon = str(o.icon);
            this.image = str(o.image);
            this.badge = str(o.badge);
            this.lang = str(o.lang);
            this.dir = o.dir || "auto";
            this.data = o.data === undefined ? null : o.data;
            this.silent = !!o.silent;
            this.renotify = !!o.renotify;
            this.requireInteraction = !!o.requireInteraction;
            this.timestamp = o.timestamp || Date.now();
            this.actions = [];
            this.onclick = null;
            this.onclose = null;
            this.onshow = null;
            this.onerror = null;
            try {
              this.__umID = notify(title, o);
              remember(this.__umID, this);
              Promise.resolve().then(function () { fire(self, "show"); });
            } catch (e) {}
          }

          UMNotification.prototype.addEventListener = function (type, fn) {
            if (!fn) { return; }
            var list = this.__umListeners[type] || (this.__umListeners[type] = []);
            if (list.indexOf(fn) < 0) { list.push(fn); }
          };
          UMNotification.prototype.removeEventListener = function (type, fn) {
            var list = this.__umListeners[type];
            if (!list) { return; }
            var i = list.indexOf(fn);
            if (i >= 0) { list.splice(i, 1); }
          };
          UMNotification.prototype.dispatchEvent = function (ev) {
            if (ev && ev.type) { fire(this, ev.type); }
            return true;
          };
          UMNotification.prototype.close = function () {
            if (!this.__umID || !live[this.__umID]) { return; }
            forget(this.__umID);
            fire(this, "close");
          };

          try {
            Object.defineProperty(UMNotification, "permission", {
              configurable: true, enumerable: true, get: function () { return "granted"; }
            });
            Object.defineProperty(UMNotification, "maxActions", {
              configurable: true, enumerable: true, get: function () { return 0; }
            });
            UMNotification.requestPermission = function (callback) {
              if (typeof callback === "function") {
                try { callback("granted"); } catch (e) {}
              }
              return Promise.resolve("granted");
            };
          } catch (e) {}

          try {
            Object.defineProperty(window, "Notification", {
              configurable: true, writable: true, enumerable: false, value: UMNotification
            });
          } catch (e) {
            try { window.Notification = UMNotification; } catch (e2) {}
          }

          window.__umNotificationClicked = function (id) {
            try {
              var n = live[String(id)];
              if (n) { fire(n, "click"); }
            } catch (e) {}
            try { window.focus(); } catch (e) {}
          };

          try {
            if (typeof ServiceWorkerRegistration !== "undefined" &&
                ServiceWorkerRegistration.prototype &&
                typeof ServiceWorkerRegistration.prototype.showNotification === "function") {
              ServiceWorkerRegistration.prototype.showNotification = function (title, options) {
                try { notify(title, options); } catch (e) {}
                return Promise.resolve();
              };
            }
          } catch (e) {}

          try {
            var perms = typeof navigator !== "undefined" ? navigator.permissions : null;
            if (perms && typeof perms.query === "function") {
              var originalQuery = perms.query.bind(perms);
              perms.query = function (desc) {
                if (desc && desc.name === "notifications") {
                  return Promise.resolve({
                    name: "notifications", state: "granted", status: "granted", onchange: null,
                    addEventListener: function () {}, removeEventListener: function () {},
                    dispatchEvent: function () { return true; }
                  });
                }
                return originalQuery(desc);
              };
            }
          } catch (e) {}

          // ---- Title ----
          var lastTitle = null;
          function reportTitle() {
            try {
              var t = str(document.title);
              if (t !== lastTitle) {
                lastTitle = t;
                post({ type: "title", title: t });
              }
            } catch (e) {}
          }

          var observing = false;
          function observeTitle() {
            try {
              if (observing || !document.head || typeof MutationObserver === "undefined") { return; }
              new MutationObserver(reportTitle).observe(document.head, {
                subtree: true, childList: true, characterData: true
              });
              observing = true;
            } catch (e) {}
          }

          reportTitle();
          observeTitle();
          try {
            document.addEventListener("DOMContentLoaded", function () { observeTitle(); reportTitle(); });
          } catch (e) {}
          try {
            if (typeof setInterval === "function") { setInterval(reportTitle, 2000); }
          } catch (e) {}

          // ---- Visibility ----
          var visible = false;
          try {
            Object.defineProperty(document, "visibilityState", {
              configurable: true, get: function () { return visible ? "visible" : "hidden"; }
            });
            Object.defineProperty(document, "hidden", {
              configurable: true, get: function () { return !visible; }
            });
            Object.defineProperty(document, "webkitVisibilityState", {
              configurable: true, get: function () { return visible ? "visible" : "hidden"; }
            });
            Object.defineProperty(document, "webkitHidden", {
              configurable: true, get: function () { return !visible; }
            });
          } catch (e) {}
          try { document.hasFocus = function () { return visible; }; } catch (e) {}

          window.__umSetVisible = function (v) {
            var next = !!v;
            if (next === visible) { return; }
            visible = next;
            try { document.dispatchEvent(makeEvent("visibilitychange", document)); } catch (e) {}
            try { window.dispatchEvent(makeEvent(visible ? "focus" : "blur", window)); } catch (e) {}
          };
        })();
        """#
    }
}
