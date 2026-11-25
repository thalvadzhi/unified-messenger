func runUnreadCountTests() {
    test("plain count") { check(UnreadCount.parse(title: "(3) Messenger") == 3, "3") }
    test("no count") { check(UnreadCount.parse(title: "Messenger") == 0, "0") }
    test("trailing text") { check(UnreadCount.parse(title: "(12) Instagram • Chats") == 12, "12") }
    test("99+") { check(UnreadCount.parse(title: "(99+) Messenger") == 99, "99") }
    test("leading whitespace") { check(UnreadCount.parse(title: "  (2) Messenger") == 2, "2") }
    test("non-numeric parens") { check(UnreadCount.parse(title: "(beta) Messenger") == 0, "0") }
    test("count not at start") { check(UnreadCount.parse(title: "Messenger (4)") == 0, "0") }
    test("empty") { check(UnreadCount.parse(title: "") == 0, "0") }
}
