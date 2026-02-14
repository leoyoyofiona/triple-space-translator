import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("中文三空格翻英文")
                .font(.title2.weight(.semibold))

            Text("在任何输入框里输入中文，0.5 秒内连按三次空格，自动翻译并替换当前输入框内容。")
                .foregroundStyle(.secondary)

            GroupBox("权限状态") {
                VStack(alignment: .leading, spacing: 10) {
                    permissionRow(
                        title: "Accessibility",
                        granted: model.hasAccessibilityPermission,
                        actionTitle: "去授权"
                    ) {
                        model.requestAccessibilityPermission()
                    }

                    permissionRow(
                        title: "Input Monitoring",
                        granted: model.hasInputMonitoringPermission,
                        actionTitle: "去授权"
                    ) {
                        model.requestInputMonitoringPermission()
                    }

                    Button("刷新权限状态") {
                        model.refreshPermissions()
                        model.setMonitorEnabled(model.monitorEnabled)
                    }
                }
                .padding(.top, 4)
            }

            Toggle(isOn: Binding(
                get: { model.monitorEnabled },
                set: { model.setMonitorEnabled($0) }
            )) {
                Text("启用全局三空格监听")
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(model.isTranslating ? .orange : .green)
                    .frame(width: 9, height: 9)
                Text(model.isTranslating ? "翻译中" : "空闲")
                    .font(.subheadline)
            }

            GroupBox("最近状态") {
                Text(model.lastStatus)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }

            Spacer(minLength: 0)

            Text("提示：首次授权后，建议退出并重新打开本应用。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .onAppear {
            model.refreshPermissions()
            model.setMonitorEnabled(model.monitorEnabled)
        }
    }

    private func permissionRow(
        title: String,
        granted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(granted ? "已授权" : "未授权")
                .foregroundStyle(granted ? .green : .red)
            if !granted {
                Button(actionTitle, action: action)
            }
        }
    }
}
