import PhotosUI
import SwiftUI
import UIKit

// pick a photo, hand back JPEG data (the server rejects HEIC and anything over 10 MB)
struct PhotoPickerButton: View {
    enum Style { case icon, mealCard, logMeal }
    var isDisabled = false
    var style: Style = .icon
    var onPick: (Data) -> Void

    @State private var item: PhotosPickerItem?
    @State private var showsPhotoError = false

    var body: some View {
        PhotosPicker(selection: $item, matching: .images) {
            pickerLabel
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(style == .icon ? "Send a photo" : "Understand a meal from a photo")
        .onChange(of: item) { _, picked in
            guard let picked else { return }
            item = nil
            Task {
                guard let data = try? await picked.loadTransferable(type: Data.self),
                      let jpeg = Self.jpeg(from: data) else {
                    showsPhotoError = true
                    return
                }
                guard !isDisabled else { return }
                onPick(jpeg)
            }
        }
        .alert("Couldn't open photo", isPresented: $showsPhotoError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Choose another photo or try downloading it to your device first.")
        }
    }

    @ViewBuilder
    private var pickerLabel: some View {
        let accent = Color(red: 1, green: 0.18, blue: 0.45)
        switch style {
        case .icon:
            Image(systemName: "photo")
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(accent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        case .logMeal:
            Text("Log meal").font(.subheadline.weight(.semibold))
                .foregroundStyle(accent).frame(minHeight: 44)
        case .mealCard:
            HStack(spacing: 14) {
                Image(systemName: "camera").font(.system(size: 22, weight: .light)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Understand a meal from a photo")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(red: 0.16, green: 0.13, blue: 0.15))
                    Text("Upload a photo for BellAI to analyze")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(accent)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 1, green: 0.90, blue: 0.94), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    // 1600 px is plenty to recognise a meal, and keeps the upload fast
    private static func jpeg(from data: Data, maxSide: CGFloat = 1_600) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format)
            .jpegData(withCompressionQuality: 0.8) { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
