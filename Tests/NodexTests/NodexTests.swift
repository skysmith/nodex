import Foundation
import XCTest

final class NodexTests: XCTestCase {
    func testMotionUsageDescriptionIsBundled() throws {
        let root = packageRoot()
        let plistURL = root.appendingPathComponent("Sources/nodex/Info.plist")
        let plist = try String(contentsOf: plistURL, encoding: .utf8)

        XCTAssertTrue(plist.contains("NSMotionUsageDescription"))
        XCTAssertTrue(plist.contains("AirPods motion"))
    }

    func testReadmeDocumentsSkillInstallAndWrapper() throws {
        let root = packageRoot()
        let readmeURL = root.appendingPathComponent("README.md")
        let readme = try String(contentsOf: readmeURL, encoding: .utf8)

        XCTAssertTrue(readme.contains("~/.codex/skills/nodex-interview"))
        XCTAssertTrue(readme.contains("bin/nodex"))
        XCTAssertTrue(readme.contains("bin/nodex-motion"))
        XCTAssertTrue(readme.contains("--voice kokoro"))
        XCTAssertTrue(readme.contains("--confirm"))
    }

    func testMotionWrapperConfirmsByDefault() throws {
        let root = packageRoot()
        let wrapperURL = root.appendingPathComponent("bin/nodex-motion")
        let wrapper = try String(contentsOf: wrapperURL, encoding: .utf8)

        XCTAssertTrue(wrapper.contains("--confirm|--no-confirm"))
        XCTAssertTrue(wrapper.contains("ARGS+=(--confirm)"))
    }

    func testPublicDocsDoNotContainLocalWorkspacePath() throws {
        let root = packageRoot()
        let publicFiles = [
            root.appendingPathComponent("README.md"),
            root.appendingPathComponent("codex-skill/nodex-interview/SKILL.md"),
            root.appendingPathComponent("Sources/nodex/main.swift")
        ]

        for file in publicFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(contents.contains("/" + "Users/"), "\(file.path) should not contain local user paths")
            XCTAssertFalse(contents.contains("Documents" + "/codex"), "\(file.path) should not contain local workspace paths")
        }
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
