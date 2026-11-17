import Testing
@testable import Cicada

struct HubMirrorTests {
    @Test func officialHostsLeaveTheEnvironmentAlone() {
        #expect(HubMirror.environment(["PATH": "/bin"], mirrored: false) == ["PATH": "/bin"])
    }
    @Test func mirrorPointsHubAndPipAtMainlandHosts() {
        let environment = HubMirror.environment(["PATH": "/bin"], mirrored: true)
        #expect(environment["HF_ENDPOINT"] == "https://hf-mirror.com")
        #expect(environment["PIP_INDEX_URL"] == "https://mirrors.aliyun.com/pypi/simple/")
        #expect(environment["PATH"] == "/bin")
    }
    @Test func theUsersOwnEndpointsWin() {
        let environment = HubMirror.environment(["HF_ENDPOINT": "https://example.test", "PIP_INDEX_URL": "https://pypi.test/simple"], mirrored: true)
        #expect(environment["HF_ENDPOINT"] == "https://example.test")
        #expect(environment["PIP_INDEX_URL"] == "https://pypi.test/simple")
    }
}
