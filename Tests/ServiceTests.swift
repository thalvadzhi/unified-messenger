import Foundation

func runServiceTests() {
    func u(_ s: String) -> URL { URL(string: s)! }
    let m = Service.messenger, i = Service.instagram
    test("start URLs are home") {
        check(m.isHome(m.startURL), "messenger")
        check(i.isHome(i.startURL), "instagram")
    }
    test("messenger home hosts") {
        check(m.isHome(u("https://www.messenger.com/t/123")), "thread")
        check(m.isHome(u("https://MESSENGER.COM/")), "bare uppercase")
        check(m.isHome(u("https://www.facebook.com/messages/t/1")), "fb messages")
        check(m.isHome(u("https://www.facebook.com/messages")), "fb messages no slash")
    }
    test("messenger away") {
        check(!m.isHome(u("https://www.facebook.com/profile.php?id=1")), "fb profile")
        check(!m.isHome(u("https://www.facebook.com/messagesfoo")), "prefix lookalike")
        check(!m.isHome(u("https://auth.meta.com/login")), "meta")
        check(!m.isHome(u("https://evilmessenger.com/")), "lookalike host")
        check(!m.isHome(u("https://www.instagram.com/direct/inbox/")), "instagram")
    }
    test("instagram home") {
        check(i.isHome(u("https://www.instagram.com/direct/t/1")), "thread")
        check(i.isHome(u("https://instagram.com/direct")), "bare")
    }
    test("instagram away") {
        check(!i.isHome(u("https://www.instagram.com/p/abc/")), "post")
        check(!i.isHome(u("https://www.instagram.com/")), "feed")
        check(!i.isHome(u("https://www.facebook.com/messages/")), "facebook")
    }
}
