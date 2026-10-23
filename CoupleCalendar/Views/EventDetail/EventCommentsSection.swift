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
                    authorName: authorDisplayName(comment.authorMemberID)
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .swipeActions {
                    Button(role: .destructive) {
                        services.commentService.delete(comment)
                        try? modelContext.save()
                    } label: {
                        Label(strings.deleteButton, systemImage: "trash")
                    }
                }
            }

            HStack(spacing: 10) {
                TextField(strings.addCommentPlaceholder, text: $commentBody, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(OurDaysTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(OurDaysTheme.border, lineWidth: 1)
                    )
                Button {
                    addComment()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline)
                        .foregroundStyle(OurDaysTheme.onInkFill)
                        .frame(width: 44, height: 44)
                        .background(OurDaysTheme.inkFill, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(commentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(commentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1)
                .accessibilityLabel(strings.addCommentPlaceholder)
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

    private func authorDisplayName(_ authorMemberID: String) -> String {
        MemberDisplayNamePolicy.displayName(
            forMemberID: authorMemberID,
            currentMemberID: settings.currentMemberID,
            currentDisplayName: settings.currentDisplayName,
            selfFallback: settings.strings.meTitle,
            partnerDisplayName: settings.partnerStatusDisplayName
        )
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
                Text("\(authorName) · \(comment.createdAt.formatted(date: .omitted, time: .shortened))")
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
