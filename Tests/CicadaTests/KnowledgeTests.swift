import Foundation
import Testing
@testable import Cicada

struct KnowledgeTests {
    @Test func assemblesModulesInOrderWithTagsAndSkipsEmptyFiles() {
        let text = Knowledge.assemble([
            "05_target_company.md": "# 目标公司\nJD",
            "00_profile.md": "  # 个人简介\n十年 Android  \n",
            "03_projects.md": "\n  \n",
        ])
        #expect(text == "<profile>\n# 个人简介\n十年 Android\n</profile>\n<target_company>\n# 目标公司\nJD\n</target_company>")
        #expect(Knowledge.assemble([:]).isEmpty)
    }

    @Test func everyModuleHasADistinctFileAndTag() {
        #expect(Set(Knowledge.parts.map(\.file)).count == Knowledge.parts.count)
        #expect(Set(Knowledge.parts.map(\.tag)).count == Knowledge.parts.count)
        #expect(Knowledge.parts.map(\.file) == Knowledge.parts.map(\.file).sorted())
    }
}
