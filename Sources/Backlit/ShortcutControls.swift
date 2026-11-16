import SwiftUI
import AppKit

struct LogoShortcutControls: View {
    @ObservedObject var model: AppModel
    @State private var recording: LogoShortcutAction?
    @State private var captureIssue: String?
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            ForEach(LogoShortcutAction.allCases) { action in
                HStack {
                    Text(action.title)
                    Spacer()
                    Button(model.logoShortcuts[action]?.label ?? "Off") {
                        captureIssue = nil; model.setShortcutRecording(true); recording = action
                    }.frame(minWidth:95).accessibilityLabel("Change " + action.title.lowercased() + " shortcut")
                    Button("Reset") { _ = model.setLogoShortcut(action.defaultBinding,action:action) }
                    Button("Disable") { _ = model.setLogoShortcut(nil,action:action) }
                        .disabled(model.logoShortcuts[action] == nil)
                }
                if let issue = model.shortcutIssues[action] {
                    Text(issue).font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                }
            }
            Text("Brightness shortcuts change the manual level by 5%. They keep the current behavior and on/off state. Battery brightness stays automatic.")
                .font(.system(size:11)).foregroundStyle(.secondary)
            Divider()
            Toggle("Shift + hardware brightness keys (experimental)",isOn:Binding(
                get:{model.shiftBrightnessEnabled},set:{model.configureShiftBrightness($0,prompt:true)})).toggleStyle(.switch)
            Text("Off by default. Requires Accessibility and Input Monitoring. Keyboard support varies: verify that the screen does not also change. Regular shortcuts work without these permissions.")
                .font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Text(model.shiftBrightnessStatus).font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            HStack {
                Link("Open Accessibility",destination:URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                Link("Open Input Monitoring",destination:URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
            }.font(.system(size:11))
        }.font(.system(size:12))
        .sheet(item:$recording,onDismiss:{model.setShortcutRecording(false)}) { action in
            VStack(spacing:18) {
                Text(action.title).font(.title2)
                Text("Press Command, Control or Option with a regular key. Escape cancels.").foregroundStyle(.secondary)
                ShortcutRecorder(capture:{binding in
                    if model.setLogoShortcut(binding,action:action) { recording = nil }
                    else { captureIssue = model.shortcutIssues[action] }
                },invalid:{captureIssue = $0},cancel:{recording = nil}).frame(width:380,height:70)
                if let captureIssue { Text(captureIssue).font(.system(size:12)).foregroundStyle(.secondary).frame(maxWidth:440) }
                Button("Cancel") { recording = nil }
            }.padding(32)
        }
        .onDisappear { model.setShortcutRecording(false) }
    }
}
