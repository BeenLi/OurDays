import CloudKit
import SwiftData
import SwiftUI

/// The comments list + input, reused by `EventDetailView` (regular events) and
/// `JointEventDetailView` (joint events). Behavior is identical for both; only the
/// `EventCommentAnchor` differs, which is what keys the thread and routes CloudKit writes.
struct EventCommentsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings
    @Environment(AppServices.self) private var services
    @Query(sort: \EventComment.createdAt) private var comments: [EventComment]
    @State private var commentBody = ""
    @State private var commentError: String?
    /// My comment being edited in the composer; nil while composing a new one.
    @State private var editingComment: EventComment?
    @FocusState private var isComposerFocused: Bool
    let anchor: EventCommentAnchor

    private var threadComments: [EventComment] {
        comments.filter { $0.eventMirrorID == anchor.key && $0.deletedAt == nil }
    }

    var body: some View {
        let strings = settings.strings
        Section {
            ForEach(threadComments) { comment in
                EventCommentBubble(
                    comment: comment,
                    isMine: comment.authorMemberID == settings.currentMemberID,
                    authorName: authorDisplayName(comment.authorMemberID),
                    editedMark: comment.editedAt == nil ? nil : strings.commentEditedMark
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .swipeActions {
                    if CommentDeletionPolicy.canDelete(comment, currentMemberID: settings.currentMemberID) {
                        Button(role: .destructive) {
                            deleteComment(comment)
                        } label: {
                            Label(strings.deleteButton, systemImage: "trash")
                        }
                    }
                    if CommentEditPolicy.canEdit(comment, currentMemberID: settings.currentMemberID) {
                        Button {
                            startEditing(comment)
                        } label: {
                            Label(strings.editButton, systemImage: "pencil")
                        }
                        .tint(OurDaysTheme.secondaryInk)
                    }
                }
            }

            if let editingComment {
                HStack(spacing: 8) {
                    Image(systemName: "pencil")
                        .font(.caption.weight(.semibold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(strings.editingCommentTitle)
                            .font(.caption.weight(.semibold))
                        Text(editingComment.body)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Button {
                        cancelEditing()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(strings.cancelButton)
                }
                .foregroundStyle(OurDaysTheme.secondaryInk)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 0, trailing: 20))
            }

            HStack(spacing: 10) {
                TextField(strings.addCommentPlaceholder, text: $commentBody, axis: .vertical)
                    .focused($isComposerFocused)
                    .lineLimit(1...4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(OurDaysTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(OurDaysTheme.border, lineWidth: 1)
                    )
                Button {
                    if let editingComment {
                        saveEdit(editingComment)
                    } else {
                        addComment()
                    }
                } label: {
                    Image(systemName: editingComment == nil ? "arrow.up" : "checkmark")
                        .font(.headline)
                        .foregroundStyle(OurDaysTheme.onInkFill)
                        .frame(width: 44, height: 44)
                        .background(OurDaysTheme.inkFill, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.35)
                .accessibilityLabel(editingComment == nil ? strings.addCommentPlaceholder : strings.saveButton)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            if let commentError {
                Text(commentError)
                    .font(.caption)
                    .foregroundStyle(OurDaysTheme.destructive)
                    .listRowBackground(Color.clear)
            }
        } header: {
            Text(strings.commentsSection)
                .font(.footnote.weight(.bold))
                .foregroundStyle(OurDaysTheme.secondaryInk)
                .textCase(nil)
        }
    }

    private var canSend: Bool {
        if let editingComment {
            return CommentEditPolicy.editedBody(original: editingComment.body, draft: commentBody) != nil
        }
        return !commentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func authorDisplayName(_ authorMemberID: String) -> String {
        MemberDisplayNamePolicy.displayName(
            forMemberID: authorMemberID,
            currentMemberID: settings.currentMemberID,
            currentDisplayName: settings.currentDisplayName,
            selfFallback: settings.strings.meTitle,
            partnerDisplayName: settings.partnerStatusDisplayName
        )
    }

    /// Soft-deletes my comment locally, then writes `deletedAt` to the same zone the
    /// comment was saved to, so it disappears for the partner too. If this upload fails,
    /// the next sync pushes it again (`CommentDeletionPolicy.deletionsNeedingReupload`).
    private func deleteComment(_ comment: EventComment) {
        if editingComment?.id == comment.id {
            cancelEditing()
        }
        services.commentService.delete(comment)
        do {
            try modelContext.save()
            commentError = nil
        } catch {
            commentError = error.localizedDescription
            return
        }
        let anchor = anchor
        let currentMemberID = settings.currentMemberID
        if let cloudKit = services.cloudKitIfAvailable {
            Task {
                do {
                    try await cloudKit.saveCommentForSync(
                        comment,
                        eventOwnerMemberID: anchor.ownerMemberID,
                        currentMemberID: currentMemberID,
                        eventRecordName: anchor.recordName
                    )
                } catch {
                    commentError = CloudKitSharingFailureMessage.userFacingMessage(for: error)
                }
            }
        }
    }

    private func startEditing(_ comment: EventComment) {
        editingComment = comment
        commentBody = comment.body
        commentError = nil
        isComposerFocused = true
    }

    private func cancelEditing() {
        editingComment = nil
        commentBody = ""
    }

    /// Saves the new body locally (`editedAt` set), then writes it to the same zone the
    /// comment lives in, like the delete. If this upload fails, the next sync pushes it
    /// again (`CommentEditPolicy.editsNeedingReupload`), and the import keeps the local
    /// body until the cloud has it.
    private func saveEdit(_ comment: EventComment) {
        guard CommentEditPolicy.canEdit(comment, currentMemberID: settings.currentMemberID),
              let newBody = CommentEditPolicy.editedBody(original: comment.body, draft: commentBody)
        else { return }
        services.commentService.edit(comment, body: newBody)
        do {
            try modelContext.save()
            commentError = nil
        } catch {
            commentError = error.localizedDescription
            return
        }
        cancelEditing()
        isComposerFocused = false
        let anchor = anchor
        let currentMemberID = settings.currentMemberID
        if let cloudKit = services.cloudKitIfAvailable {
            Task {
                do {
                    try await cloudKit.saveCommentForSync(
                        comment,
                        eventOwnerMemberID: anchor.ownerMemberID,
                        currentMemberID: currentMemberID,
                        eventRecordName: anchor.recordName
                    )
                } catch {
                    commentError = CloudKitSharingFailureMessage.userFacingMessage(for: error)
                }
            }
        }
    }

    private func addComment() {
        let comment = services.commentService.createComment(
            eventMirrorID: anchor.key,
            authorMemberID: settings.currentMemberID,
            body: commentBody
        )
        modelContext.insert(comment)
        do {
            try modelContext.save()
            commentError = nil
            let anchor = anchor
            let currentMemberID = settings.currentMemberID
            if let cloudKit = services.cloudKitIfAvailable {
                Task {
                    do {
                        try await cloudKit.saveCommentForSync(
                            comment,
                            eventOwnerMemberID: anchor.ownerMemberID,
                            currentMemberID: currentMemberID,
                            eventRecordName: anchor.recordName
                        )
                    } catch {
                        commentError = CloudKitSharingFailureMessage.userFacingMessage(for: error)
                    }
                }
            }
            commentBody = ""
        } catch {
            commentError = error.localizedDescription
        }
    }
}

/// One comment as a chat bubble: the partner on the left in a white bubble, me on the
/// right in my identity color — the same left/right reading as any messaging app.
/// Both sides carry the author's avatar outside the bubble, so my side is not just a
/// coloured block: the teal ring on the right mirrors the coral ring on the left.
struct EventCommentBubble: View {
    let comment: EventComment
    let isMine: Bool
    let authorName: String
    /// "Edited" when the author changed the body after sending; nil otherwise.
    var editedMark: String?

    private var caption: String {
        let time = comment.createdAt.formatted(date: .omitted, time: .shortened)
        guard let editedMark else { return "\(authorName) · \(time)" }
        return "\(authorName) · \(time) · \(editedMark)"
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMine {
                Spacer(minLength: 48)
            } else {
                MemberAvatarForID(memberID: comment.authorMemberID, size: 28)
            }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                Text(comment.body)
                    .font(.body)
                    .foregroundStyle(isMine ? Color.white : OurDaysTheme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        isMine ? OurDaysIdentity.me.color : OurDaysTheme.surface,
                        in: UnevenRoundedRectangle(
                            topLeadingRadius: 18,
                            bottomLeadingRadius: isMine ? 18 : 6,
                            bottomTrailingRadius: isMine ? 6 : 18,
                            topTrailingRadius: 18,
                            style: .continuous
                        )
                    )
                    .textSelection(.enabled)
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(OurDaysTheme.secondaryInk)
                    .padding(.horizontal, 6)
            }

            if isMine {
                MemberAvatarForID(memberID: comment.authorMemberID, size: 28)
            } else {
                Spacer(minLength: 48)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
