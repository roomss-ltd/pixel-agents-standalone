import SwiftUI

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(toast.activity.color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textStrong)
                Text(toast.subtitle).font(.system(size: 11)).foregroundStyle(Theme.textMuted).lineLimit(1)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.panelBg, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(toast.activity.color.opacity(0.3), lineWidth: 1))
        .shadow(radius: 8)
    }
}
