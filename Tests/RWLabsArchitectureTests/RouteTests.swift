import XCTest
@testable import RWLabsArchitecture

final class RouteTests: XCTestCase {
    func testCustomSchemeKeepsFirstSegmentInPath() {
        let route = Route(url: URL(string: "myapp://product/123?ref=mail")!)
        XCTAssertEqual(route.path, "/product/123")
        XCTAssertEqual(route.queryItems, ["ref": "mail"])
        XCTAssertEqual(route.matches(pattern: "/product/:id"), ["id": "123"])
    }

    func testUniversalLinkUsesPath() {
        let route = Route(url: URL(string: "https://example.com/product/123")!)
        XCTAssertEqual(route.path, "/product/123")
        XCTAssertTrue(route.isMatch("/product/:id"))
    }

    func testCustomSchemeWithOnlyHost() {
        XCTAssertEqual(Route(url: URL(string: "myapp://settings")!).path, "/settings")
    }

    func testMatchingRules() {
        let route = Route(path: "/product/123/")
        XCTAssertEqual(route.matches(pattern: "/product/:id"), ["id": "123"], "trailing slash ignored")
        XCTAssertNil(route.matches(pattern: "/products/:id"), "literal must match")
        XCTAssertNil(route.matches(pattern: "/product/:id/reviews"), "segment count must match")
        let params: [String: String]? = Route(path: "/a").matches(pattern: "/a")
        XCTAssertEqual(params, [:])
    }

    func testBuildsStandardCustomSchemeURLAndRoundTrips() {
        let route = Route(path: "/product/123", queryItems: ["ref": "share", "a": "1"])
        let url = route.url(scheme: "myapp")
        XCTAssertEqual(url?.absoluteString, "myapp://product/123?a=1&ref=share")
        XCTAssertEqual(Route(url: url!), route)
    }

    func testBuildsUniversalLink() {
        let url = Route(path: "/product/123").url(scheme: "https", host: "example.com")
        XCTAssertEqual(url?.absoluteString, "https://example.com/product/123")
        XCTAssertNil(Route(path: "/x").url(scheme: "https"), "web scheme needs a host")
    }
}
