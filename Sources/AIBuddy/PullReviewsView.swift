import SwiftUI
import BuddyCore

struct PullReviewsView: View {
    @ObservedObject var workspace: Workspace
    let pull: PullRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button { workspace.closeReviews() } label: {
                Label("My pull requests", systemImage: "chevron.left")
            }.buttonStyle(.plain).font(Focus.font(12, weight: .medium))
                .foregroundStyle(Focus.accentText).accessibilityIdentifier("back-to-my-prs")
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) { title; Spacer(minLength: 12); actions }
                VStack(alignment: .leading, spacing: 16) { title; actions }
            }
            Rectangle().fill(Focus.border).frame(height: 1)
            if workspace.reviewsLoading {
                ProgressView("Loading reviews…").frame(maxWidth: .infinity).padding(.vertical, 40)
            } else if let error = workspace.reviewsError {
                VStack(alignment: .leading, spacing: 12) {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Focus.warning)
                    Button("Try again") { workspace.openReviews(pull) }
                        .buttonStyle(FocusButtonStyle()).accessibilityIdentifier("retry-reviews")
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Focus.warningSurface).clipShape(RoundedRectangle(cornerRadius: 6))
            } else if let history = workspace.reviewHistory {
                feedback(history)
            }
            Spacer(minLength: 0)
        }.font(Focus.font(14)).frame(maxWidth: 940).padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    private var title: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(pull.repository, systemImage: "folder")
                Text("#\(pull.number)").monospacedDigit()
                if pull.draft { Text("Draft") }
            }.font(Focus.font(12)).foregroundStyle(Focus.muted)
            Text(pull.title).font(Focus.font(26, weight: .semibold))
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }
    private var actions: some View {
        HStack(spacing: 8) {
            Link(destination: pull.url) { Label("GitHub", systemImage: "arrow.up.right") }
                .buttonStyle(FocusButtonStyle()).accessibilityLabel("Open on GitHub")
            Button { workspace.openReviews(pull) } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }.buttonStyle(FocusButtonStyle()).disabled(workspace.reviewsLoading)
                .accessibilityIdentifier("refresh-reviews")
        }.fixedSize()
    }
    @ViewBuilder private func feedback(_ history: ReviewHistory) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Feedback").font(Focus.font(17, weight: .semibold)).accessibilityAddTraits(.isHeader)
            Spacer()
            Text(history.feedbackSummary)
                .font(Focus.font(12)).foregroundStyle(Focus.muted)
        }
        if history.partial {
            Label("Review history is incomplete. Open this PR on GitHub to see the full history.", systemImage: "exclamationmark.triangle")
                .font(Focus.font(12)).foregroundStyle(Focus.warning)
                .padding(12).background(Focus.warningSurface).clipShape(RoundedRectangle(cornerRadius: 6))
        }
        if history.reviews.isEmpty && !history.partial {
            Label("No reviews yet", systemImage: "bubble.left.and.bubble.right")
                .font(Focus.font(14)).foregroundStyle(Focus.muted).padding(.vertical, 12)
        }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12, pinnedViews: [.sectionHeaders]) {
                ForEach(history.feedbackGroups) { group in
                    Section {
                        ForEach(group.reviews) { review in reviewCard(review) }
                        ForEach(group.comments) { comment in commentCard(comment) }
                        Color.clear.frame(height: 8)
                    } header: { ReviewerHeading(group: group).zIndex(2) }
                }
            }.padding(.bottom, 12)
        }.accessibilityIdentifier("review-history")
    }
    private func reviewCard(_ review: SubmittedReview) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack { reviewLabel(review); Spacer(); timestamp(review.submittedAt) }
                VStack(alignment: .leading, spacing: 8) { reviewLabel(review); timestamp(review.submittedAt) }
            }
            if let body = review.body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ReviewMessageView(body)
            } else {
                Text("No summary provided.").font(Focus.font(13)).foregroundStyle(Focus.muted)
            }
        }.padding(20).reviewSurface()
    }
    private func reviewLabel(_ review: SubmittedReview) -> some View {
        HStack(spacing: 10) {
            Label("Review", systemImage: "text.bubble").font(Focus.font(12)).foregroundStyle(Focus.muted)
            ReviewStatus(state: review.state, title: review.status)
        }
    }
    private func commentCard(_ comment: ReviewComment) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Code comment", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(Focus.font(12, weight: .medium)).foregroundStyle(Focus.muted)
                    Spacer()
                    timestamp(comment.createdAt)
                }
                Text(comment.location).font(.system(size: 12, design: .monospaced))
                    .accessibilityIdentifier("review-comment-location-\(comment.id)")
                    .foregroundStyle(Focus.accentText).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(.horizontal, 20).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Focus.background)
            Rectangle().fill(Focus.border).frame(height: 1)
            ReviewMessageView(comment.body).padding(20)
        }.reviewSurface()
    }
    private func timestamp(_ date: Date?) -> some View {
        Group {
            if let date { Text(date.formatted(date: .abbreviated, time: .shortened)) }
        }.font(Focus.font(12)).foregroundStyle(Focus.muted)
    }
}

private struct ReviewerHeading: View {
    let group: ReviewFeedbackGroup
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Focus.soft)
                if group.isBot {
                    Image(systemName: "cpu").font(.system(size: 19, weight: .medium))
                } else {
                    Text(group.initials).font(Focus.font(13, weight: .semibold))
                }
            }.foregroundStyle(Focus.accentText).frame(width: 40, height: 40).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(group.author).font(Focus.font(15, weight: .semibold)).textSelection(.enabled).accessibilityAddTraits(.isHeader)
                    if group.isBot {
                        Text("BOT").font(Focus.font(10, weight: .semibold)).tracking(0.5)
                            .accessibilityIdentifier("reviewer-bot-\(group.id)")
                            .foregroundStyle(Focus.accentText).padding(.horizontal, 5).padding(.vertical, 3)
                            .background(Focus.soft).clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text(group.summary)
                    .font(Focus.font(12)).foregroundStyle(Focus.muted)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 12).background(Focus.background)
            .accessibilityElement(children: .contain).accessibilityIdentifier("reviewer-\(group.id)")
    }
}
private struct ReviewStatus: View {
    let state: String
    let title: String
    private var color: Color { state == "APPROVED" ? Focus.success : state == "CHANGES_REQUESTED" ? Focus.warning : Focus.accentText }
    private var symbol: String { state == "APPROVED" ? "checkmark.circle" : state == "CHANGES_REQUESTED" ? "exclamationmark.bubble" : "bubble.left" }
    var body: some View {
        Label(title, systemImage: symbol).font(Focus.font(12, weight: .medium)).foregroundStyle(color)
            .accessibilityIdentifier("review-status-\(state)")
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(state == "CHANGES_REQUESTED" ? Focus.warningSurface : Focus.sidebar)
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
private extension View {
    func reviewSurface() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading).background(Focus.surface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Focus.border))
            .accessibilityElement(children: .contain)
    }
}
