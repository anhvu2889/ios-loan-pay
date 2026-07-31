import Foundation
import Testing
import LoanPayDomain

@Suite struct IdentifierTests {
    @Test func encodesAsBareString() throws {
        let data = try JSONEncoder().encode(LoanID("loan-42"))
        #expect(String(data: data, encoding: .utf8) == "\"loan-42\"")
    }

    @Test func decodesFromBareString() throws {
        let id = try JSONDecoder().decode(LoanID.self, from: Data("\"loan-42\"".utf8))
        #expect(id == LoanID("loan-42"))
    }
}
