// XCTestPrimer — the cheat-sheet for reading this target.
//
// This file is COMMENT-ONLY on purpose: it is the legend for the Rosetta
// translations in RosettaTests.swift. Each test there carries a
// `// ROSETTA:` note pointing back at a construct explained here.
//
// ─────────────────────────────────────────────────────────────────────────
// CONSTRUCT MAP — Swift Testing ⇄ XCTest
// ─────────────────────────────────────────────────────────────────────────
//
//   Swift Testing                      XCTest
//   ─────────────────────────────      ────────────────────────────────
//   @Suite struct FooTests             final class FooTests: XCTestCase
//   @Test func bar()                   func testBar()   (name MUST start
//                                      with "test" — discovery is by name
//                                      prefix, not by attribute)
//   #expect(a == b)                    XCTAssertEqual(a, b)
//   #expect(x)                         XCTAssertTrue(x)
//   #expect(a != b)                    XCTAssertNotEqual(a, b)
//   #expect(throws: E.self) { ... }    XCTAssertThrowsError(try ...) {
//                                        error in ... }   (closure gets the
//                                      error for further asserts)
//   try #require(optional)             try XCTUnwrap(optional)
//   Issue.record("msg")                XCTFail("msg")
//   @Test(arguments: [...])            no equivalent — write a loop, or one
//                                      test per case (see RosettaTests for
//                                      the loop form)
//   init()/deinit on the struct        setUp()/tearDown() overrides
//
// ─────────────────────────────────────────────────────────────────────────
// GOTCHAS — where the mental model differs, not just the spelling
// ─────────────────────────────────────────────────────────────────────────
//
// 1. PARALLEL STRUCTS vs SERIAL CLASSES.
//    Swift Testing instantiates a FRESH STRUCT per test and runs tests in
//    parallel by default — shared mutable state between tests is
//    impossible unless you smuggle it through a global. XCTestCase methods
//    run SERIALLY on ONE class per test method instance, and instance
//    properties reset per test — but globals and static state persist and
//    XCTest won't race-check you. The discipline Swift Testing enforces by
//    construction, XCTest leaves to your review habits.
//
// 2. #require vs XCTUnwrap.
//    Both unwrap-or-abort-the-test. The difference: `try #require(x)` also
//    works for boolean preconditions (#require(a > 0)) and its failure
//    STOPS the current test immediately; XCTUnwrap only unwraps optionals,
//    and a plain failed XCTAssert does NOT stop the test — later lines
//    still run against broken state unless you set
//    `continueAfterFailure = false`.
//
// 3. ASYNC: both frameworks accept `async throws` test methods and you
//    should always prefer plain `await` over expectations for async code.
//    XCTestExpectation predates async/await; it survives for the cases
//    await can't express directly — "this callback fires N times", "this
//    stream pushes an update while I'm doing something else". ONE
//    deliberate example lives at the bottom of RosettaTests; everything
//    else awaits.
//
// 4. NO TRAITS. Swift Testing's `.serialized`, `.enabled(if:)`, tags and
//    parameterized arguments have no XCTest equivalents — the XCTest
//    idioms are: serial-by-default classes, `try XCTSkipIf(...)`, schemes/
//    plans for grouping, and hand-rolled loops for parameters.
