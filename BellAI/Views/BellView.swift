import SwiftUI

struct BellView: View {
    let onClose: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            BellHeaderView(onClose: onClose, onOpenSettings: onOpenSettings)
                .padding(.horizontal, 20)
                .padding(.top, 12)

            ScrollView {
                BellListeningView()
                    .padding(.top, 18)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    BellView(onClose: {}, onOpenSettings: {})
        .background(Color(red: 0.97, green: 0.96, blue: 0.97))
}
