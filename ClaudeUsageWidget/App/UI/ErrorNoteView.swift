import SwiftUI

struct ErrorNoteView: View {
    let note: String

    var body: some View {
        Label(note, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
    }
}
