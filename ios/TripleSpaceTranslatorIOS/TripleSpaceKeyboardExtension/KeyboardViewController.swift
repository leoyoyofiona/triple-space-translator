import UIKit
import Foundation
@preconcurrency import Translation

final class KeyboardViewController: UIInputViewController {
    private var detector = TriplePressDetector(requiredPressCount: 3, windowMs: 500)
    private let translator = AppleSystemTranslator()

    private let statusLabel = UILabel()
    private let globeButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private let spaceButton = UIButton(type: .system)
    private let enterButton = UIButton(type: .system)

    private var isBusy = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUi()
        setStatus("Ready: triple-space to translate")
    }

    private func setupUi() {
        view.backgroundColor = .secondarySystemBackground

        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 2

        globeButton.setTitle("🌐", for: .normal)
        globeButton.titleLabel?.font = .systemFont(ofSize: 22)
        globeButton.addTarget(self, action: #selector(handleGlobeTap), for: .touchUpInside)

        deleteButton.setTitle("⌫", for: .normal)
        deleteButton.titleLabel?.font = .systemFont(ofSize: 22)
        deleteButton.addTarget(self, action: #selector(handleDeleteTap), for: .touchUpInside)

        spaceButton.setTitle("space", for: .normal)
        spaceButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        spaceButton.addTarget(self, action: #selector(handleSpaceTap), for: .touchUpInside)

        enterButton.setTitle("↩︎", for: .normal)
        enterButton.titleLabel?.font = .systemFont(ofSize: 22)
        enterButton.addTarget(self, action: #selector(handleEnterTap), for: .touchUpInside)

        [globeButton, deleteButton, spaceButton, enterButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.backgroundColor = .systemBackground
            $0.layer.cornerRadius = 8
            $0.layer.borderWidth = 0.5
            $0.layer.borderColor = UIColor.separator.cgColor
            $0.heightAnchor.constraint(equalToConstant: 42).isActive = true
        }

        let row = UIStackView(arrangedSubviews: [globeButton, deleteButton, spaceButton, enterButton])
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fill

        globeButton.widthAnchor.constraint(equalToConstant: 48).isActive = true
        deleteButton.widthAnchor.constraint(equalToConstant: 64).isActive = true
        enterButton.widthAnchor.constraint(equalToConstant: 64).isActive = true

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        row.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(statusLabel)
        view.addSubview(row)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            row.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            row.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            row.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10)
        ])
    }

    @objc private func handleGlobeTap(_ sender: UIButton) {
        advanceToNextInputMode()
    }

    @objc private func handleDeleteTap() {
        textDocumentProxy.deleteBackward()
    }

    @objc private func handleEnterTap() {
        textDocumentProxy.insertText("\n")
    }

    @objc private func handleSpaceTap() {
        textDocumentProxy.insertText(" ")

        guard detector.registerPress() else {
            return
        }

        Task { @MainActor in
            await handleTripleSpaceTrigger()
        }
    }

    @MainActor
    private func handleTripleSpaceTrigger() async {
        if isBusy {
            return
        }

        isBusy = true
        defer { isBusy = false }

        guard let context = textDocumentProxy.documentContextBeforeInput, !context.isEmpty else {
            setStatus("No input text found")
            return
        }

        let candidate = context.removingTrailingSpaces(3).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else {
            setStatus("Empty text after removing trigger spaces")
            return
        }

        guard candidate.containsChinese else {
            setStatus("No Chinese detected, skipped")
            return
        }

        do {
            setStatus("Translating...")
            let translated = try await translator.translateToEnglish(candidate)
            guard !translated.isEmpty else {
                setStatus("Translation is empty")
                return
            }

            replaceContext(beforeInput: context, with: translated)
            setStatus("Translated and replaced")
        } catch {
            setStatus("Translate failed: \(error.localizedDescription)")
        }
    }

    private func replaceContext(beforeInput context: String, with translated: String) {
        for _ in context {
            textDocumentProxy.deleteBackward()
        }
        textDocumentProxy.insertText(translated)
    }

    private func setStatus(_ message: String) {
        statusLabel.text = message
    }
}

private struct TriplePressDetector {
    private let requiredPressCount: Int
    private let windowMs: Int
    private var timestamps: [UInt64] = []

    init(requiredPressCount: Int, windowMs: Int) {
        self.requiredPressCount = requiredPressCount
        self.windowMs = windowMs
    }

    mutating func registerPress() -> Bool {
        let now = DispatchTime.now().uptimeNanoseconds
        let windowNs = UInt64(windowMs) * 1_000_000

        timestamps.append(now)
        timestamps = timestamps.filter { now >= $0 && now - $0 <= windowNs }

        if timestamps.count >= requiredPressCount {
            timestamps.removeAll(keepingCapacity: true)
            return true
        }

        return false
    }
}

private struct AppleSystemTranslator {
    private let sourceLanguage = Locale.Language(identifier: "zh-Hans")
    private let targetLanguage = Locale.Language(identifier: "en")

    @MainActor
    func translateToEnglish(_ text: String) async throws -> String {
        let session = TranslationSession(installedSource: sourceLanguage, target: targetLanguage)
        let response = try await session.translate(text)
        return response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    func removingTrailingSpaces(_ count: Int) -> String {
        var value = self
        var remaining = count
        while remaining > 0 && value.last == " " {
            value.removeLast()
            remaining -= 1
        }
        return value
    }

    var containsChinese: Bool {
        return range(of: #"[\u3400-\u9FFF]"#, options: .regularExpression) != nil
    }
}
