import SwiftUI

/// `.empty`: how to get recordings in, with a Sync button (mockup 13).
struct EmptyLibraryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            FieldyArtwork(width: 230, radar: true)
            Text("Your recordings will show up here")
                .font(Typography.largeTitle)
                .kerning(-0.36)
                .foregroundStyle(Palette.label)
                .padding(.top, 14)
                .padding(.bottom, 8)
            Text("Record with your Fieldy wherever you are. When you're back at your Mac, sync and EarBud copies each recording over and turns it into text.")
                .font(Typography.lead)
                .cssLineHeight(1.5, size: 14)
                .foregroundStyle(Palette.label2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 14) {
                EmptyStep(number: 1, title: "Record", text: "Press the button on your Fieldy once to start recording, and again to stop.")
                EmptyStep(number: 2, title: "Sync", text: "Keep your Fieldy near this Mac and click Sync. You can also sync from the menu bar.")
                EmptyStep(number: 3, title: "Read and listen", text: "Each recording gets a transcript, made right here on your Mac. Nothing goes online.")
            }
            .padding(.top, 30)
            .padding(.bottom, 26)
            Button {
                model.syncNow()
            } label: {
                Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(EarBudButtonStyle(kind: .primary, size: .large))
            Text("If a day goes by without a sync, EarBud will send you a reminder.")
                .font(Typography.footnote)
                .foregroundStyle(Palette.label3)
                .padding(.top, 14)
        }
        .padding(.horizontal, 80)
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.content)
    }
}

/// `.estep`.
private struct EmptyStep: View {
    var number: Int
    var title: String
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Text("\(number)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Palette.accentTint))
                Text(title).font(Typography.stepTitle).foregroundStyle(Palette.label)
            }
            Text(text)
                .font(Typography.callout)
                .cssLineHeight(1.42, size: 12.5)
                .foregroundStyle(Palette.label2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 17)
        .frame(width: 236, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .softCard(radius: 12)
        .accessibilityElement(children: .combine)
    }
}
