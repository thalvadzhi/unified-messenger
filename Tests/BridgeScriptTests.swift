import Foundation
import JavaScriptCore

private let bridgeStubs = """
var window = globalThis;
var posted = [];
var events = [];
var intervals = [];
var focused = 0;
var document = {
    title: "Messenger",
    head: null,
    addEventListener: function () {},
    dispatchEvent: function (e) { events.push("document:" + e.type); return true; }
};
window.addEventListener = function () {};
window.dispatchEvent = function (e) { events.push("window:" + e.type); return true; };
window.focus = function () { focused += 1; };
window.webkit = { messageHandlers: { um: { postMessage: function (m) { posted.push(JSON.stringify(m)); } } } };
var setInterval = function (fn, ms) { intervals.push(fn); return intervals.length; };
function ServiceWorkerRegistration() {}
ServiceWorkerRegistration.prototype.showNotification = function () { return Promise.resolve(); };
"""

private func makeBridgeContext(_ service: ServiceID = .messenger) -> JSContext {
    let ctx = JSContext()!
    ctx.evaluateScript(bridgeStubs)
    ctx.evaluateScript(BridgeScript.source(for: service))
    return ctx
}

@discardableResult
private func js(_ ctx: JSContext, _ script: String) -> JSValue {
    ctx.evaluateScript(script)
}

private func posted(_ ctx: JSContext) -> [[String: Any]] {
    let count = Int(js(ctx, "posted.length").toInt32())
    return (0..<count).compactMap { i in
        let s = js(ctx, "posted[\(i)]").toString() ?? ""
        return (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any]
    }
}

func runBridgeScriptTests() {
    test("bridge handler name") { check(BridgeScript.handlerName == "um", BridgeScript.handlerName) }

    test("bridge loads without exception") {
        let ctx = makeBridgeContext()
        check(ctx.exception == nil, "\(String(describing: ctx.exception))")
    }

    test("bridge permission granted") {
        let ctx = makeBridgeContext()
        check(js(ctx, "Notification.permission === 'granted'").toBool(), "permission")
        check(js(ctx, "'Notification' in window").toBool(), "in window")
    }

    test("bridge requestPermission promise and callback") {
        let ctx = makeBridgeContext()
        js(ctx, "var cb = null; var pr = null; Notification.requestPermission(function (p) { cb = p; }).then(function (p) { pr = p; });")
        check(js(ctx, "cb === 'granted'").toBool(), "callback")
        // Promise jobs drain after evaluateScript returns.
        check(js(ctx, "pr === 'granted'").toBool(), "promise")
        check(ctx.exception == nil, "\(String(describing: ctx.exception))")
    }

    test("bridge posts initial title with service") {
        let ctx = makeBridgeContext(.instagram)
        let first = posted(ctx).first
        check(first?["type"] as? String == "title", "\(String(describing: first))")
        check(first?["title"] as? String == "Messenger", "\(String(describing: first))")
        check(first?["service"] as? String == "instagram", "\(String(describing: first))")
    }

    test("bridge title interval posts only on change") {
        let ctx = makeBridgeContext()
        let before = posted(ctx).count
        js(ctx, "intervals.forEach(function (f) { f(); });")
        check(posted(ctx).count == before, "no change, no post")
        js(ctx, "document.title = '(2) Messenger'; intervals.forEach(function (f) { f(); });")
        let last = posted(ctx).last
        check(posted(ctx).count == before + 1, "one post")
        check(last?["type"] as? String == "title" && last?["title"] as? String == "(2) Messenger", "\(String(describing: last))")
    }

    test("bridge new Notification posts notify") {
        let ctx = makeBridgeContext()
        js(ctx, "var n = new Notification('Ann', {body: 'hi', tag: 't1'}); var clicked = false; n.onclick = function () { clicked = true; };")
        check(ctx.exception == nil, "\(String(describing: ctx.exception))")
        let last = posted(ctx).last
        check(last?["type"] as? String == "notify", "\(String(describing: last))")
        check(last?["title"] as? String == "Ann", "title")
        check(last?["body"] as? String == "hi", "body")
        check(last?["tag"] as? String == "t1", "tag")
        check(last?["service"] as? String == "messenger", "service")
        let id = last?["id"] as? String ?? ""
        check(!id.isEmpty, "id")
        js(ctx, "__umNotificationClicked(\(String(reflecting: id)))")
        check(js(ctx, "clicked === true").toBool(), "onclick")
        check(js(ctx, "focused === 1").toBool(), "focus")
    }

    test("bridge notification ids are unique and listeners fire") {
        let ctx = makeBridgeContext()
        js(ctx, "var a = new Notification('A'); var b = new Notification('B'); var hits = 0; b.addEventListener('click', function (e) { hits += 1; });")
        let notes = posted(ctx).filter { $0["type"] as? String == "notify" }
        check(notes.count == 2, "\(notes)")
        let ids = notes.compactMap { $0["id"] as? String }
        check(Set(ids).count == 2, "\(ids)")
        check(notes.first?["body"] as? String == "" && notes.first?["tag"] as? String == "", "defaults")
        js(ctx, "__umNotificationClicked(\(String(reflecting: ids.last ?? "")))")
        check(js(ctx, "hits === 1").toBool(), "listener")
        js(ctx, "__umNotificationClicked('nope')")
        check(ctx.exception == nil, "unknown id is harmless")
    }

    test("bridge notification ids differ across page loads") {
        let a = makeBridgeContext(), b = makeBridgeContext()
        js(a, "new Notification('x')"); js(b, "new Notification('x')")
        let ida = posted(a).last?["id"] as? String ?? "", idb = posted(b).last?["id"] as? String ?? ""
        check(!ida.isEmpty && !idb.isEmpty && ida != idb, "\(ida) vs \(idb)")
    }

    test("bridge install flag is not enumerable") {
        let ctx = makeBridgeContext()
        check(js(ctx, "window.__umInstalled === true && Object.keys(window).indexOf('__umInstalled') < 0").toBool(), "")
    }

    test("bridge close calls onclose") {
        let ctx = makeBridgeContext()
        js(ctx, "var closed = false; var c = new Notification('C'); c.onclose = function () { closed = true; }; c.close();")
        check(js(ctx, "closed === true").toBool(), "onclose")
        check(ctx.exception == nil, "\(String(describing: ctx.exception))")
    }

    test("bridge showNotification posts notify") {
        let ctx = makeBridgeContext()
        js(ctx, "new ServiceWorkerRegistration().showNotification('Bob', {body: 'yo', tag: 't2'});")
        let last = posted(ctx).last
        check(last?["type"] as? String == "notify" && last?["title"] as? String == "Bob", "\(String(describing: last))")
        check(last?["body"] as? String == "yo" && last?["tag"] as? String == "t2", "\(String(describing: last))")
    }

    test("bridge visibility toggles") {
        let ctx = makeBridgeContext()
        check(js(ctx, "document.visibilityState === 'hidden' && document.hidden === true && document.hasFocus() === false").toBool(), "initially hidden")
        js(ctx, "events = []; __umSetVisible(true);")
        check(js(ctx, "document.visibilityState === 'visible'").toBool(), "visible")
        check(js(ctx, "document.hidden === false").toBool(), "hidden false")
        check(js(ctx, "document.hasFocus() === true").toBool(), "focus")
        check(js(ctx, "events.indexOf('document:visibilitychange') >= 0 && events.indexOf('window:focus') >= 0").toBool(), js(ctx, "events.join()").toString())
        js(ctx, "events = []; __umSetVisible(false);")
        check(js(ctx, "document.visibilityState === 'hidden'").toBool(), "hidden again")
        check(js(ctx, "document.hidden === true").toBool(), "hidden true")
        check(js(ctx, "document.hasFocus() === false").toBool(), "no focus")
        check(js(ctx, "events.indexOf('window:blur') >= 0").toBool(), js(ctx, "events.join()").toString())
    }

    test("bridge install guard") {
        let ctx = makeBridgeContext()
        let titles = posted(ctx).filter { $0["type"] as? String == "title" }.count
        ctx.evaluateScript(BridgeScript.source(for: .messenger))
        check(ctx.exception == nil, "\(String(describing: ctx.exception))")
        let after = posted(ctx).filter { $0["type"] as? String == "title" }.count
        check(titles == 1 && after == 1, "\(titles) -> \(after)")
    }

    test("bridge survives missing webkit") {
        let ctx = JSContext()!
        ctx.evaluateScript(bridgeStubs + "delete window.webkit;")
        ctx.evaluateScript(BridgeScript.source(for: .messenger))
        js(ctx, "new Notification('x'); __umSetVisible(true);")
        check(ctx.exception == nil, "\(String(describing: ctx.exception))")
    }
}
