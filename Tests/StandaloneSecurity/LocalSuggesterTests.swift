import Foundation

extension SecurityRegression {
    static func localSuggesterTests() async {
        func suggestion(_ basename: String, _ note: String = "") -> LocalNameSuggestionResult {
            LocalNameSuggester.dictionarySuggestion(basename: basename, userNote: note)
        }
        func checkSuggestion(_ value: LocalNameSuggestionResult, _ description: String, _ source: LocalNameSuggestionSource) throws {
            try check(value.status == .suggested && value.suggestion?.description == description && value.suggestion?.source == source && !value.modelAttemptFailed,
                      "Unexpected suggestion: \(value)")
        }
        test("local suggestion: English fallback normalizes and labels its source") {
            try checkSuggestion(suggestion("Meeting Notes.pdf"), "meeting_notes", .existingEnglish)
        }
        test("local suggestion: technical bilingual glossary preserves meaning") {
            try checkSuggestion(suggestion("CEM-EIT唯一性证明.pdf"), "cem_eit_uniqueness_proof", .localDictionary)
            try checkSuggestion(suggestion("完全电极模型电阻抗层析成像唯一性证明.pdf"), "cem_eit_uniqueness_proof", .localDictionary)
        }
        test("local suggestion: compound suffix never enters description") {
            try checkSuggestion(suggestion("KIT4重建结果.nii.gz"), "kit4_reconstruction_results", .localDictionary)
            try checkSuggestion(suggestion("Experiment Results.TAR.GZ"), "experiment_results", .existingEnglish)
        }
        test("local suggestion: explicit note takes priority over basename") {
            try checkSuggestion(suggestion("unrelated_invoice.pdf", "非光滑优化学习笔记"), "nonsmooth_optimization_study_notes", .localDictionary)
        }
        test("local suggestion: unknown Chinese cannot silently disappear") {
            for basename in ["尚未收录内容.pdf", "CEM-EIT未知内容唯一性证明.pdf", "唯一性证明未收录词.pdf", "未收录词会议记录.pdf"] {
                let value = suggestion(basename)
                try check(value.status == .needsManualEnglish && value.suggestion == nil && !value.modelAttemptFailed, "Unknown text was discarded: \(basename) => \(value)")
            }
        }
        test("local suggestion: unknown note cannot hide behind usable English filename") {
            let value = suggestion("meeting_notes.pdf", "未知中文")
            try check(value.status == .needsManualEnglish && value.suggestion == nil, "Untranslatable note was ignored")
        }
        test("local suggestion: known date category and version fields stay separate") {
            try checkSuggestion(suggestion("2026_10_20_research_cem_eit_proof_v01.pdf"), "cem_eit_proof", .existingEnglish)
            try checkSuggestion(suggestion("2026_10_research_cem_eit_v03.tar.gz"), "cem_eit", .existingEnglish)
            try checkSuggestion(suggestion("undated_learning_proximal_methods_v2.pdf"), "proximal_methods", .existingEnglish)
        }
        test("local suggestion: stray dates versions categories and suffixes blocked") {
            for note in ["proof 2026 10 21", "proof 20261021", "proof v02", "research proof", "proof pdf", "version proof", "proof version"] {
                let value = suggestion("plain.pdf", note)
                try check(value.status == .needsManualEnglish && value.suggestion == nil, "Non-description field accepted: \(note)")
            }
        }
        test("local suggestion: path and URL basenames rejected") {
            for name in ["../document.pdf", "/private/tmp/document.pdf", "file://host/document.pdf", "a\\b.pdf", "a:b.pdf", ".", "..", ".gitignore"] {
                let value = suggestion(name)
                try check(value.status == .invalidInput && value.suggestion == nil && !value.modelAttemptFailed, "Path or fixed input accepted: \(String(reflecting: name))")
            }
        }
        test("local suggestion: basename controls and invisible formatting rejected") {
            for scalar in ["\u{0}", "\n", "\r", "\t", "\u{1B}", "\u{7F}", "\u{202E}", "\u{2066}"] {
                let value = suggestion("report" + scalar + ".pdf")
                try check(value.status == .invalidInput && value.suggestion == nil, "Control filename accepted")
            }
        }
        test("local suggestion: note controls cannot enter model prompt") {
            for scalar in ["\u{0}", "\n", "\r", "\t", "\u{202E}"] {
                let value = suggestion("plain.pdf", "report" + scalar + "notes")
                try check(value.status == .invalidInput && value.suggestion == nil && !value.modelAttemptFailed, "Control note accepted")
            }
        }
        test("local suggestion: basename limits and surrounding whitespace enforced") {
            for name in ["", " report.pdf", "report.pdf ", String(repeating: "a", count: 256)] {
                try check(suggestion(name).status == .invalidInput, "Malformed basename accepted")
            }
            try check(suggestion(String(repeating: "a", count: 251) + ".pdf", "report notes").status == .suggested, "255-byte basename not allowed")
        }
        test("local suggestion: note input bytes and output bytes bounded independently") {
            try check(suggestion("plain.pdf", String(repeating: "a", count: 1_001)).status == .invalidInput, "Overlong note accepted")
            try check(suggestion("plain.pdf", String(repeating: "中", count: 334)).status == .invalidInput, "UTF8-byte bound bypassed")
            try check(suggestion("plain.pdf", String(repeating: "a", count: 81)).status == .needsManualEnglish, "Overlong description accepted")
            try check(suggestion("plain.pdf", String(repeating: "a", count: 80)).suggestion?.description.utf8.count == 80, "80-byte description rejected")
        }
        test("local suggestion: destructive command tokens blocked after normalization") {
            for note in ["sudo rm all files", "curl https example com", "bash shell report", "chmod secret file", "osascript action", "launchctl load service", "eval input", "$(rm all_files)", "`sudo reboot`", "report; shutdown"] {
                let value = suggestion("plain.pdf", note)
                try check(value.status == .needsManualEnglish && value.suggestion == nil, "Command-shaped result accepted: \(note)")
            }
        }
        test("local suggestion: normalized output is an ASCII descriptor only") {
            for name in ["Meeting Notes.pdf", "KIT4重建结果.nii.gz", "CEM-EIT唯一性证明.pdf"] {
                let value = suggestion(name)
                guard let description = value.suggestion?.description else { throw ReviewFailure(description: "Expected descriptor") }
                try check(description.range(of: "^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$", options: .regularExpression) != nil && !description.contains(".") && !description.contains("/") && !description.contains("\\"), "Unsafe description shape")
            }
        }
        await testAsync("local suggestion: model is opt-in and remains disabled by default") {
            let value = await LocalNameSuggester().suggest(basename: "会议记录.pdf")
            try checkSuggestion(value, "meeting_notes", .localDictionary)
            try check(value.suggestion?.source != .appleOnDevice && !value.modelAttemptFailed, "Default call attempted model")
        }
        await testAsync("local suggestion: explicit disabled-model call uses deterministic fallback") {
            let value = await LocalNameSuggester().suggest(basename: "CEM-EIT proof.pdf", useOnDeviceModel: false)
            try checkSuggestion(value, "cem_eit_proof", .existingEnglish)
        }
        await testAsync("local suggestion: invalid input does not attempt the disabled model") {
            let value = await LocalNameSuggester().suggest(basename: "../secret.pdf", useOnDeviceModel: false)
            try check(value.status == .invalidInput && value.suggestion == nil && !value.modelAttemptFailed, "Invalid input reached suggestion path")
        }
        await testAsync("local suggestion: cancellation returns no name or attempted model") {
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return await LocalNameSuggester().suggest(basename: "notes.pdf", useOnDeviceModel: false)
            }
            let value = await task.value
            try check(value.status == .cancelled && value.suggestion == nil && !value.modelAttemptFailed, "Cancelled request produced a result")
        }
    }
}
