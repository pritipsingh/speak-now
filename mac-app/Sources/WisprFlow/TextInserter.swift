import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Where the dictated text ended up.
enum InsertResult {
    case inserted  // dropped into a text field
    case noTarget  // no field found — caller should show the copy toast
}

/// Inserts text into the frontmost app, finding a target even when nothing is focused.
///
/// Order of preference:
///   1. The currently focused editable element (paste at the caret).
///   2. Otherwise, the editable text field **closest to the mouse pointer** in the
///      frontmost window — focus it, then paste.
///   3. Otherwise, give up and report `.noTarget` so the caller can copy-to-clipboard
///      and show a toast.
///
/// Native apps expose their fields well; browser web content exposes a limited
/// accessibility tree, so on some websites step 2 won't find the input (falls through
/// to the toast). Requires Accessibility permission.
final class TextInserter {
    private let pasteboard = NSPasteboard.general

    @discardableResult
    func insert(_ text: String) -> InsertResult {
        guard !text.isEmpty else { return .noTarget }

        if focusedEditableElement() != nil {
            paste(text)
            return .inserted
        }

        if let field = closestEditableFieldToPointer() {
            AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                self?.paste(text)
            }
            return .inserted
        }

        return .noTarget
    }

    // MARK: - Finding a target

    private func focusedEditableElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        guard let focused = copyElement(systemWide, kAXFocusedUIElementAttribute) else {
            return nil
        }
        return isEditable(focused) ? focused : nil
    }

    /// The editable field nearest the mouse pointer in the frontmost window.
    private func closestEditableFieldToPointer() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(
            appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        let root =
            copyElement(appElement, kAXFocusedWindowAttribute)
            ?? copyElement(appElement, kAXMainWindowAttribute)
            ?? appElement

        var candidates: [(element: AXUIElement, frame: CGRect)] = []
        collectEditable(root, depth: 0, into: &candidates)
        guard !candidates.isEmpty else { return nil }

        let pointer = pointerInAXCoordinates()
        return candidates.min(by: {
            distance(from: pointer, to: $0.frame) < distance(from: pointer, to: $1.frame)
        })?.element
    }

    private func collectEditable(
        _ element: AXUIElement, depth: Int,
        into result: inout [(element: AXUIElement, frame: CGRect)]
    ) {
        if depth > 60 { return }
        if isEditable(element), let frame = frameOf(element),
            frame.width > 1, frame.height > 1
        {
            result.append((element, frame))
        }
        guard let children = copyElements(element, kAXChildrenAttribute) else { return }
        for child in children {
            collectEditable(child, depth: depth + 1, into: &result)
        }
    }

    private func isEditable(_ element: AXUIElement) -> Bool {
        let role = stringValue(element, kAXRoleAttribute)
        if role == (kAXTextFieldRole as String) || role == (kAXTextAreaRole as String) {
            return true
        }
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        return settable.boolValue && hasAttribute(element, kAXSelectedTextAttribute)
    }

    // MARK: - Geometry

    /// Mouse location in Accessibility (top-left origin) screen coordinates.
    private func pointerInAXCoordinates() -> CGPoint {
        let mouse = NSEvent.mouseLocation  // bottom-left origin
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: mouse.x, y: primaryHeight - mouse.y)
    }

    private func frameOf(_ element: AXUIElement) -> CGRect? {
        guard let posValue = copyValue(element, kAXPositionAttribute),
            let sizeValue = copyValue(element, kAXSizeAttribute)
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue, .cgPoint, &point)
        AXValueGetValue(sizeValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    /// Shortest distance from a point to a rectangle (0 if inside).
    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    // MARK: - AX helpers

    private func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let v = value, CFGetTypeID(v) == AXUIElementGetTypeID()
        else { return nil }
        return (v as! AXUIElement)
    }

    private func copyElements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? [AXUIElement]
    }

    private func copyValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let v = value, CFGetTypeID(v) == AXValueGetTypeID()
        else { return nil }
        return (v as! AXValue)
    }

    private func stringValue(_ element: AXUIElement, _ attribute: String) -> String {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return (value as? String) ?? ""
    }

    private func hasAttribute(_ element: AXUIElement, _ attribute: String) -> Bool {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success,
            let list = names as? [String]
        else { return false }
        return list.contains(attribute)
    }

    // MARK: - Clipboard paste

    private func paste(_ text: String) {
        let saved = savedClipboard()
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        sendCommandV()
        restoreClipboard(saved, after: 0.35)
    }

    private func savedClipboard() -> [NSPasteboardItem]? {
        pasteboard.pasteboardItems?.compactMap { item in
            let copy = NSPasteboardItem()
            var wrote = false
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                    wrote = true
                }
            }
            return wrote ? copy : nil
        }
    }

    private func restoreClipboard(_ saved: [NSPasteboardItem]?, after delay: TimeInterval) {
        guard let saved, !saved.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.pasteboard.clearContents()
            self.pasteboard.writeObjects(saved)
        }
    }

    private func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
