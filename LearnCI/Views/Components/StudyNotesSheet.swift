import SwiftUI
import SwiftData

struct StudyNotesSheet: View {
    let resource: StudyResourceRef
    let block: StudyBlock
    let currentMediaTime: Double
    let userID: String
    let onSeek: (Double) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allNotes: [StudyNote]

    @State private var draft = ""
    @State private var editingNoteID: UUID?
    @State private var editingDraft = ""

    init(
        resource: StudyResourceRef,
        block: StudyBlock,
        currentMediaTime: Double,
        userID: String,
        onSeek: @escaping (Double) -> Void
    ) {
        self.resource = resource
        self.block = block
        self.currentMediaTime = currentMediaTime
        self.userID = userID
        self.onSeek = onSeek
        _allNotes = Query(sort: \StudyNote.updatedAt, order: .reverse)
    }

    private var blockNotes: [StudyNote] {
        allNotes.filter {
            $0.userID == userID &&
            $0.resourceId == resource.resourceId &&
            $0.blockIndex == block.index
        }
    }

    private var isEditingNote: Bool {
        editingNoteID != nil
    }

    var body: some View {
        NavigationStack {
            List {
                if !isEditingNote {
                    Section("New note") {
                        TextField("Note at current playback position…", text: $draft, axis: .vertical)
                            .lineLimit(3...6)
                        Button("Save note") {
                            saveNote()
                        }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section("Notes for this block") {
                    if blockNotes.isEmpty {
                        Text("No notes yet for this block.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(blockNotes, id: \.id) { note in
                            if editingNoteID == note.id {
                                editingRow(for: note)
                            } else {
                                noteRow(note)
                            }
                        }
                        .onDelete(perform: deleteNotes)
                    }
                }
            }
            .navigationTitle("Study Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if isEditingNote {
                        Button("Cancel") {
                            cancelEditing()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isEditingNote {
                        Button("Save") {
                            if let note = blockNotes.first(where: { $0.id == editingNoteID }) {
                                saveEditedNote(note)
                            }
                        }
                        .disabled(editingDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func noteRow(_ note: StudyNote) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(formattedOffset(note.offsetSec))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                Button {
                    startEditing(note)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Edit note")

                Button {
                    onSeek(note.mediaTime)
                    dismiss()
                } label: {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Jump to note time")
            }
            .font(.body)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func editingRow(for note: StudyNote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Edit note…", text: $editingDraft, axis: .vertical)
                .lineLimit(3...8)
            Text(formattedOffset(note.offsetSec))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func startEditing(_ note: StudyNote) {
        editingNoteID = note.id
        editingDraft = note.body
    }

    private func cancelEditing() {
        editingNoteID = nil
        editingDraft = ""
    }

    private func saveNote() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let offset = max(0, currentMediaTime - block.mediaStart)
        let note = StudyNote(
            userID: userID,
            resource: resource,
            blockIndex: block.index,
            offsetSec: offset,
            mediaTime: currentMediaTime,
            body: trimmed
        )
        modelContext.insert(note)
        try? modelContext.save()
        draft = ""
    }

    private func saveEditedNote(_ note: StudyNote) {
        let trimmed = editingDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        note.body = trimmed
        note.updatedAt = Date()
        try? modelContext.save()
        cancelEditing()
    }

    private func deleteNotes(at offsets: IndexSet) {
        for index in offsets {
            let note = blockNotes[index]
            if editingNoteID == note.id {
                cancelEditing()
            }
            modelContext.delete(note)
        }
        try? modelContext.save()
    }

    private func formattedOffset(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let secs = total % 60
        return String(format: "+%d:%02d in block", minutes, secs)
    }
}
