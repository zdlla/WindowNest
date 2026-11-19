import AppKit
import SwiftUI
import Carbon
import ApplicationServices

@MainActor
final class GlobalShortcutController: ObservableObject {
    @Published private(set) var status = "未启用全局快捷键"
    @Published private(set) var recording = false
    @Published private(set) var commandControlStatus = ""
    var onTrigger: (() -> Void)?
    private let preferences: AppearanceStore
    private var handler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var active: GlobalShortcut?
    private var serial: UInt32 = 0
    private var armed = false
    private var singleMonitors: [Any] = []
    private var activeSingle: ShortcutSingleKey?
    private var tap = SingleKeyTap()
    private var commandControlMonitors: [Any] = []
    private var commandControlTap = CommandControlTap()
    private let signature: OSType = 0x574E5354 // WNST

    init(preferences: AppearanceStore) {
        self.preferences = preferences
        var events = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = InstallEventHandler(GetEventDispatcherTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr else { return OSStatus(eventNotHandledErr) }
            return MainActor.assumeIsolated {
                let controller = Unmanaged<GlobalShortcutController>.fromOpaque(context).takeUnretainedValue()
                guard identifier.signature == controller.signature, identifier.id == controller.serial,
                      controller.hotKey != nil, !controller.recording else { return OSStatus(eventNotHandledErr) }
                if GetEventKind(event) == UInt32(kEventHotKeyPressed) { controller.armed = true }
                else if controller.armed { controller.armed = false; controller.onTrigger?() }
                return noErr
            }
        }, events.count, &events, context, &handler)
        if result != noErr { status = "系统快捷键服务不可用，请退出重开窗匣。" }
    }

    func apply() {
        guard !recording else { return }
        let settings = preferences.settings
        configureCommandControl(settings.globalShortcutEnabled && settings.commandControlShortcutEnabled)
        guard settings.globalShortcutEnabled else { unregister(); status = "未启用全局快捷键"; return }
        if let single = settings.shortcutSingleKey {
            if !AXIsProcessTrusted() { unregister(); status = "单键呼出需要窗匣的辅助功能权限，授权后返回即可。"; return }
            if activeSingle == single, singleMonitors.count == 2 { return }
            _ = registerSingle(single, persist: false)
            return
        }
        guard let chord = settings.globalShortcut else { unregister(); return }
        guard active != chord || hotKey == nil else { return }
        _ = register(chord, persist: false)
    }

    func enable(_ value: Bool) {
        if value {
            if let single = preferences.settings.shortcutSingleKey { _ = chooseSingle(single) }
            else if let chord = preferences.settings.globalShortcut { _ = choose(chord) }
            else { _ = chooseSingle(.rightOption) }
        }
        else {
            preferences.update { $0.globalShortcutEnabled = false }
            if !preferences.settings.globalShortcutEnabled { unregister(); stopCommandControl(); status = "已停用，原组合已释放" }
        }
    }
    @discardableResult func choose(_ chord: GlobalShortcut) -> Bool { register(chord, persist: true) }
    @discardableResult func chooseSingle(_ key: ShortcutSingleKey) -> Bool { registerSingle(key, persist: true) }
    func clear() {
        preferences.update { $0.globalShortcutEnabled = false; $0.globalShortcut = nil; $0.shortcutSingleKey = nil; $0.commandControlShortcutEnabled = false }
        if preferences.settings.globalShortcut == nil { unregister(); stopCommandControl(); status = "已清除快捷键" }
    }
    private func register(_ chord: GlobalShortcut, persist: Bool) -> Bool {
        if let reason = conflict(chord) { status = reason; return false }
        if active?.keyCode == chord.keyCode, active?.modifiers == chord.modifiers, hotKey != nil {
            if persist { preferences.update { $0.globalShortcut = chord; $0.shortcutSingleKey = nil; $0.globalShortcutEnabled = true } }
            guard !persist || (preferences.settings.globalShortcut == chord && preferences.settings.globalShortcutEnabled) else {
                status = "快捷键未能保存，原设置已保留"; return false
            }
            active = chord
            status = "\(chord.display) · 已启用，按一次呼出，再按一次收起"
            return true
        }
        guard handler != nil else { status = "系统快捷键服务不可用"; return false }
        var candidate: EventHotKeyRef?
        let next = serial &+ 1
        let result = RegisterEventHotKey(UInt32(chord.keyCode), chord.modifiers,
            EventHotKeyID(signature: signature, id: next), GetEventDispatcherTarget(), OptionBits(kEventHotKeyExclusive), &candidate)
        guard result == noErr, let candidate else {
            status = result == eventHotKeyExistsErr ? "这个组合已被其他程序占用，请换一个。" : "系统未能注册这个组合，请尝试其他按键。"
            return false
        }
        if persist {
            preferences.update { $0.globalShortcut = chord; $0.shortcutSingleKey = nil; $0.globalShortcutEnabled = true }
            guard preferences.settings.globalShortcut == chord, preferences.settings.globalShortcutEnabled else {
                UnregisterEventHotKey(candidate); status = "快捷键未能保存，原设置已保留"; return false
            }
        }
        unregister()
        hotKey = candidate; active = chord; serial = next
        status = "\(chord.display) · 已启用，按一次呼出，再按一次收起"
        return true
    }

    func conflict(_ chord: GlobalShortcut) -> String? {
        if chord.isReserved { return "这是 macOS 的常用保留组合，请选择其他快捷键。" }
        guard chord.isValid else { return "请使用至少两个修饰键（⌃、⌥、⇧、⌘）加一个按键。" }
        var symbolic: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&symbolic) == noErr, let entries = symbolic?.takeRetainedValue() as? [[String: Any]] else {
            return "暂时无法读取系统快捷键，未保存这个组合。请稍后重试。"
        }
        if entries.contains(where: {
            ($0[kHISymbolicHotKeyEnabled as String] as? Bool) == true &&
            ($0[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint16Value == chord.keyCode &&
            (($0[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value ?? 0) & GlobalShortcut.mask == chord.modifiers
        }) { return "这个组合已用于系统功能，请换一个；不会覆盖系统设置。" }
        if let item = menuConflict(NSApp.mainMenu, chord: chord) { return "这个组合与窗匣菜单“\(item)”冲突，请换一个。" }
        return nil
    }
    private func menuConflict(_ menu: NSMenu?, chord: GlobalShortcut) -> String? {
        for item in menu?.items ?? [] {
            if let found = menuConflict(item.submenu, chord: chord) { return found }
            if !item.keyEquivalent.isEmpty, item.keyEquivalent.uppercased() == chord.keyLabel.uppercased(),
                Self.carbonModifiers(item.keyEquivalentModifierMask) == chord.modifiers { return item.title }
        }
        return nil
    }
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= GlobalShortcut.command }
        if flags.contains(.option) { result |= GlobalShortcut.option }
        if flags.contains(.control) { result |= GlobalShortcut.control }
        if flags.contains(.shift) { result |= GlobalShortcut.shift }
        return result
    }
    func beginRecording() { recording = true; unregister(); stopCommandControl(); status = "请按下新的快捷键；Esc 取消" }
    func endRecording() { recording = false; apply() }
    private func registerSingle(_ key: ShortcutSingleKey, persist: Bool) -> Bool {
        guard AXIsProcessTrusted() else { status = "请先开启窗匣辅助功能权限，再启用单键呼出。"; return false }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        var candidates: [Any] = []
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.receiveSingle(event) }
        }) { candidates.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.receiveSingle(event)
            return event // Never swallow Option/Command or ordinary typing.
        }) { candidates.append(local) }
        guard candidates.count == 2 else {
            candidates.forEach(NSEvent.removeMonitor); status = "单键监听未能启动，请检查辅助功能权限后重开窗匣。"; return false
        }
        if persist {
            preferences.update { $0.shortcutSingleKey = key; $0.globalShortcutEnabled = true }
            guard preferences.settings.shortcutSingleKey == key, preferences.settings.globalShortcutEnabled else {
                candidates.forEach(NSEvent.removeMonitor); status = "未能保存单键设置，原设置保留"; return false
            }
        }
        unregister(); singleMonitors = candidates; activeSingle = key
        status = "\(key.title) · 已启用，轻按松开即可呼出 / 收起"
        return true
    }
    private func receiveSingle(_ event: NSEvent) {
        guard !recording, let key = activeSingle else { return }
        if IsSecureEventInputEnabled() { tap.reset(); return }
        guard event.type == .flagsChanged, event.keyCode == key.keyCode else { tap.cancelChord(); return }
        // Use the event's own side-specific flags, not the live key state:
        // a fast tap may already be released when a global callback runs.
        // NX_DEVICERALTKEYMASK / NX_DEVICERCMDKEYMASK (IOLLEvent.h).
        let sideMask: UInt = key == .rightOption ? 0x40 : 0x10
        let oppositeMask: UInt = key == .rightOption ? 0x20 : 0x8
        let raw = event.modifierFlags.rawValue
        let modifiers = Self.carbonModifiers(event.modifierFlags)
        let down = raw & sideMask != 0 || (raw & 0xFF == 0 && modifiers & key.modifier != 0 && !tap.isDown)
        let only = raw & oppositeMask == 0 && !event.modifierFlags.contains(.function) && modifiers == (down ? key.modifier : 0)
        if tap.update(down: down, onlyModifier: only, time: event.timestamp) { onTrigger?() }
    }
    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }; hotKey = nil; active = nil; armed = false
        singleMonitors.forEach(NSEvent.removeMonitor); singleMonitors.removeAll(); activeSingle = nil; tap.reset()
    }
    private func configureCommandControl(_ enabled: Bool) {
        guard enabled else { stopCommandControl(); commandControlStatus = ""; return }
        guard AXIsProcessTrusted() else { stopCommandControl(); commandControlStatus = "⌘ + ⌃ 需要辅助功能权限"; return }
        guard commandControlMonitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.receiveCommandControl(event) }
        }) { commandControlMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.receiveCommandControl(event); return event
        }) { commandControlMonitors.append(local) }
        guard commandControlMonitors.count == 2 else {
            stopCommandControl(); commandControlStatus = "⌘ + ⌃ 监听未能启动，请检查辅助功能权限"; return
        }
        commandControlStatus = "⌘ + ⌃ · 已启用，同时按下后松开即可呼出 / 收起"
    }
    private func receiveCommandControl(_ event: NSEvent) {
        guard !recording else { return }
        if IsSecureEventInputEnabled() { commandControlTap.reset(); return }
        guard event.type == .flagsChanged else { commandControlTap.cancelChord(); return }
        if event.modifierFlags.contains(.function) { commandControlTap.cancelChord() }
        if commandControlTap.update(modifiers: Self.carbonModifiers(event.modifierFlags), time: event.timestamp) { onTrigger?() }
    }
    private func stopCommandControl() {
        commandControlMonitors.forEach(NSEvent.removeMonitor); commandControlMonitors.removeAll(); commandControlTap.reset()
    }
    func stop() { unregister(); stopCommandControl(); if let handler { RemoveEventHandler(handler) }; handler = nil }
}
