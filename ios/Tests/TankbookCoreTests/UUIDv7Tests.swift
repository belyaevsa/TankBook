import Testing
import Foundation
@testable import TankbookCore

@Test func generatedIDsSortInCreationOrder() {
    var ids: [UUID] = []
    for _ in 0 ..< 20_000 {
        ids.append(UUID.v7())
    }

    #expect(ids == ids.sorted())
    #expect(Set(ids).count == ids.count)
}

@Test func idsCarryTheV7VersionAndVariantBits() {
    let id = UUID.v7()

    #expect(id.versionNibble == 7)
    #expect(id.variantBits == 0b10)
}

@Test func idsOrderCorrectlyAcrossMilliseconds() {
    let first = UUID.v7()
    usleep(3_000)
    let second = UUID.v7()

    #expect(first < second)
}

@Test func manyIdsKeepMonotonicOrderWithinOneMillisecond() {
    var ids: [UUID] = []
    for _ in 0 ..< 50_000 {
        ids.append(UUID.v7())
    }

    for (index, id) in ids.enumerated() {
        if index > 0 {
            #expect(ids[index - 1] < id)
        }
    }
}
